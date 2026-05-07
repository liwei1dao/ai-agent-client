package com.jielihome.jielihome.feature.assistant

import android.bluetooth.BluetoothDevice
import android.util.Log
import com.aiagent.device_plugin_interface.AssistantAudioCodec
import com.aiagent.device_plugin_interface.AssistantAudioFormat
import com.aiagent.device_plugin_interface.AssistantAudioFrame
import com.aiagent.device_plugin_interface.AssistantError
import com.aiagent.device_plugin_interface.AssistantPlaybackFrame
import com.aiagent.device_plugin_interface.DeviceAssistantPort
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspActionCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.TranslationCallback
import com.jielihome.jielihome.audio.LocalPlayer
import com.jielihome.jielihome.audio.OpusStreamDecoder
import com.jielihome.jielihome.core.JieliHomeServer
import com.jielihome.jielihome.feature.translation.runtime.NoOpAITranslationApi
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.util.concurrent.atomic.AtomicLong

/**
 * `DeviceAssistantPort` 的杰理实现 —— **录音模式（MODE_RECORD=1）通路**版。
 *
 * # 设计要点
 * 杰理 demo 里没有「AI 助理」这种产品形态，但其 [TranslationImpl.enterMode] +
 * `MODE_RECORD`(=1) + `STRATEGY_DEVICE_ALWAYS_RECORDING`(=1) 能让耳机持续上推
 * OPUS 音频帧到 [TranslationCallback.onReceiveAudioData]，完全满足 AI 助理的
 * 上行采集需求，我们就借这条录音模式通路：
 * - 上行采集：耳机麦 → 耳机固件 OPUS 编码 → onReceiveAudioData → OpusStreamDecoder
 *   → 16kHz PCM → SharedFlow 抛给编排器。**mode 字段 = 1，与 demo 行为一致**。
 * - 下行回灌：TTS PCM 写 [LocalPlayer]（AudioTrack + USAGE_MEDIA），由 Android
 *   蓝牙路由走 A2DP 通道送回耳机扬声器。不走 RCSP 下发，避免与 A2DP 媒体音频抢通道。
 *
 * # 与 [com.jielihome.jielihome.feature.translation.JieliCallTranslationPort] 的关系
 * 两者都走 TranslationImpl，但 mode 不同、策略不同：
 * - CallTranslation：mode=3/6（通话翻译），依赖真实 eSCO 通话
 * - 本类：mode=1（录音），纯上行，不依赖任何通话事件
 * 两者不会同时工作（enterMode 互斥）。
 *
 * # 格式
 * 仅放开 PCM_S16LE / 16 kHz / mono / 20 ms。
 * 上行 SDK 推 OPUS，由 [OpusStreamDecoder] 解码成 16 kHz PCM 推到 Flow。
 * 下行 PCM 直接写 AudioTrack。
 *
 * # 线程安全
 * `enter` / `exit` / `reportPlayback` 通过 `synchronized(this)` 互斥；
 * SharedFlow.tryEmit / AudioTrack.write 自身线程安全；
 * SDK 回调线程不固定，所有共享状态用 @Volatile 标记。
 */
class JieliAssistantPort(
    private val server: JieliHomeServer,
) : DeviceAssistantPort {

    companion object {
        private const val TAG = "JieliAssistantPort"
        private val PCM_16K_MONO_20MS = AssistantAudioFormat.PCM_S16LE_16K_MONO_20MS
    }

    private val _audioFrames = MutableSharedFlow<AssistantAudioFrame>(
        replay = 0,
        extraBufferCapacity = 128,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    private val _errors = MutableSharedFlow<AssistantError>(
        replay = 0,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    @Volatile private var entered = false
    @Volatile private var device: BluetoothDevice? = null
    @Volatile private var decoder: OpusStreamDecoder? = null
    @Volatile private var player: LocalPlayer? = null
    @Volatile private var translationImpl: TranslationImpl? = null
    @Volatile private var translationCallback: TranslationCallback? = null

    /** 调试统计：每秒打一次 SDK PCM 帧产出量 */
    private val upCount = AtomicLong(0)
    @Volatile private var lastReportMs = 0L
    /** 首帧 flag：首次 onModeChange / onReceiveAudioData / 首次 PCM 帧发射都各打一条 INFO */
    @Volatile private var rxFirstModeChangeLogged = false
    @Volatile private var rxFirstAudioLogged = false
    /** 上行帧自增序号 */
    private val seqGen = AtomicLong(0)

    override fun supportedSourceFormats(): Set<AssistantAudioFormat> = setOf(PCM_16K_MONO_20MS)
    override fun supportedSinkFormats(): Set<AssistantAudioFormat> = setOf(PCM_16K_MONO_20MS)

    override val audioFrames: Flow<AssistantAudioFrame> = _audioFrames.asSharedFlow()
    override val errors: Flow<AssistantError> = _errors.asSharedFlow()

    @Synchronized
    override fun enter(sourceFormat: AssistantAudioFormat) {
        require(sourceFormat == PCM_16K_MONO_20MS) {
            "JieliAssistantPort only supports PCM_S16LE/16k/mono/20ms (got $sourceFormat)"
        }
        check(!entered) { "device.assistant.busy" }

        val dev = server.connectFeature.connectedDevice()
            ?: throw IllegalStateException("device.assistant.no_device: no connected device")
        device = dev

        // 1. 启动本地 A2DP 播放器（接收 TTS PCM）
        val lp = LocalPlayer(sampleRate = 16000, channels = 1).also { it.start() }
        player = lp

        // 2. 启动 Opus 解码器：耳机上推的录音流是 OPUS，解码后丢回 SharedFlow
        val od = OpusStreamDecoder(
            channel = 1,
            packetSize = 200,
            sampleRate = 16000,
            onPcm = { pcm -> emitUplinkFrame(pcm) },
            onError = { c, m ->
                _errors.tryEmit(AssistantError(
                    code = "device.decoder_failed",
                    message = "opus: code=$c msg=${m ?: ""}",
                ))
            },
        ).also { it.start() }
        decoder = od

        // 3. 构造 TranslationImpl + 前置校验
        val impl = TranslationImpl(server.internalBtManager, NoOpAITranslationApi(), dev)
        if (!impl.isInit) {
            runCatching { impl.destroy() }
            cleanup()
            throw IllegalStateException("device.assistant.rcsp_not_init: RCSP not init for ${dev.address}")
        }
        if (!impl.isSupportTranslation) {
            runCatching { impl.destroy() }
            cleanup()
            throw IllegalStateException("device.assistant.not_supported: device does not support translation")
        }

        // 4. 注册 TranslationCallback —— 关键回调：onReceiveAudioData 拿 OPUS 帧
        val cb = object : TranslationCallback {
            override fun onModeChange(d: BluetoothDevice, m: TranslationMode) {
                if (!rxFirstModeChangeLogged) {
                    rxFirstModeChangeLogged = true
                    Log.i(TAG, "[SDK<-DEV] onModeChange FIRST addr=${d.address} mode=${m.mode} type=${m.audioType} ch=${m.channel} sr=${m.sampleRate} strategy=${m.recordingStrategy}")
                } else {
                    Log.i(TAG, "[SDK<-DEV] onModeChange addr=${d.address} mode=${m.mode} strategy=${m.recordingStrategy}")
                }
                if (m.mode == TranslationMode.MODE_IDLE) {
                    // 耳机主动退出 RECORD 模式（按键 / 超时 / 被抢占）
                    _errors.tryEmit(AssistantError(
                        code = "device.mode_exited",
                        message = "headset exited MODE_RECORD → MODE_IDLE",
                    ))
                }
            }

            override fun onReceiveAudioData(d: BluetoothDevice, data: AudioData) {
                val payload = data.audioData
                if (payload == null || payload.isEmpty()) {
                    Log.w(TAG, "[SDK<-DEV] onReceiveAudioData null/empty payload source=${data.source} type=${data.type}")
                    return
                }
                if (!rxFirstAudioLogged) {
                    rxFirstAudioLogged = true
                    Log.i(TAG, "[SDK<-DEV] onReceiveAudioData FIRST FRAME addr=${d.address} source=${data.source} type=${data.type} size=${payload.size}")
                }
                when (data.type) {
                    Constants.AUDIO_TYPE_PCM -> emitUplinkFrame(payload)
                    Constants.AUDIO_TYPE_OPUS -> decoder?.feedEncoded(payload)
                    else -> Log.w(TAG, "[SDK<-DEV] onReceiveAudioData unknown type=${data.type} (skip)")
                }
            }

            override fun onError(d: BluetoothDevice, code: Int, msg: String) {
                Log.e(TAG, "[SDK<-DEV] TranslationCallback.onError code=$code msg=$msg")
                _errors.tryEmit(AssistantError(
                    code = "device.translation_error",
                    message = "code=$code msg=$msg",
                ))
            }
        }
        impl.addTranslationCallback(cb)
        translationImpl = impl
        translationCallback = cb

        // 5. 下发 enterMode(MODE_RECORD=1, OPUS, ch=1, 16k, STRATEGY_DEVICE_ALWAYS_RECORDING)
        //    - mode=1：与 demo 录音模式对齐，耳机 RCSP 状态机进入 MODE_RECORD
        //    - STRATEGY_DEVICE_ALWAYS_RECORDING=1：耳机固件自主采集并持续上推，APP 不用手机麦
        val sdkMode = TranslationMode(
            TranslationMode.MODE_RECORD,
            Constants.AUDIO_TYPE_OPUS,
            1,
            16000,
        ).setRecordingStrategy(TranslationMode.STRATEGY_DEVICE_ALWAYS_RECORDING)
        Log.i(TAG, "[APP->SDK] enterMode addr=${dev.address} mode=${sdkMode.mode}(MODE_RECORD) type=${sdkMode.audioType}(OPUS) ch=${sdkMode.channel} sr=${sdkMode.sampleRate} strategy=${sdkMode.recordingStrategy}(DEVICE_ALWAYS_RECORDING)")
        impl.enterMode(sdkMode, cb)

        entered = true
        Log.d(TAG, "entered assistant mode (MODE_RECORD=1, DEVICE_ALWAYS_RECORDING, A2DP playback)")
    }

    private fun emitUplinkFrame(pcm: ByteArray) {
        upCount.incrementAndGet()
        val now = System.currentTimeMillis()
        if (now - lastReportMs >= 1000L) {
            Log.d(TAG, "uplink PCM stats (last 1s): frames=${upCount.getAndSet(0)} bytes/frame=${pcm.size}")
            lastReportMs = now
        }
        val frame = AssistantAudioFrame(
            codec = AssistantAudioCodec.PCM_S16LE,
            sampleRate = 16000,
            channels = 1,
            bytes = pcm,
            sequence = seqGen.incrementAndGet(),
            timestampUs = now * 1000L,
        )
        if (!_audioFrames.tryEmit(frame)) {
            Log.w(TAG, "audioFrames buffer overflow; dropped seq=${frame.sequence}")
        }
    }

    @Synchronized
    override fun reportPlayback(frame: AssistantPlaybackFrame) {
        check(entered) { "device.assistant.not_active" }
        require(frame.codec == AssistantAudioCodec.PCM_S16LE) {
            "JieliAssistantPort only accepts PCM_S16LE for sink (got ${frame.codec})"
        }
        // TTS PCM 写入本地 A2DP 播放器，由系统蓝牙路由送回耳机扬声器
        player?.feed(frame.bytes)
    }

    @Synchronized
    override fun exit() {
        if (!entered) return
        entered = false
        cleanup()
        Log.d(TAG, "exited assistant mode")
    }

    /** 释放 enterMode / decoder / player / callback；可被 enter 失败路径调用，幂等 */
    private fun cleanup() {
        val impl = translationImpl
        val cb = translationCallback
        val addr = device?.address
        if (impl != null) {
            runCatching {
                Log.i(TAG, "[APP->SDK] exitMode addr=$addr mode=${TranslationMode.MODE_RECORD}")
                impl.exitMode(object : OnRcspActionCallback<Int> {
                    override fun onSuccess(d: BluetoothDevice?, t: Int?) {
                        Log.i(TAG, "[APP->SDK] exitMode onSuccess addr=${d?.address} t=$t")
                    }
                    override fun onError(d: BluetoothDevice?, e: com.jieli.bluetooth.bean.base.BaseError?) {
                        Log.w(TAG, "[APP->SDK] exitMode onError addr=${d?.address} code=${e?.code} msg=${e?.message}")
                    }
                })
            }
            if (cb != null) runCatching { impl.removeTranslationCallback(cb) }
            runCatching { impl.destroy() }
        }
        runCatching { decoder?.stop() }
        runCatching { player?.stop() }
        translationImpl = null
        translationCallback = null
        decoder = null
        player = null
        device = null
        // 复位首帧标志，下次 enter 重新打点
        rxFirstModeChangeLogged = false
        rxFirstAudioLogged = false
    }
}
