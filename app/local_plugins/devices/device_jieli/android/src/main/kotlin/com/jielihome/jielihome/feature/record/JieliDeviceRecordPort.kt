package com.jielihome.jielihome.feature.record

import android.bluetooth.BluetoothDevice
import android.util.Log
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl
import com.jieli.bluetooth.interfaces.rcsp.callback.OnRcspActionCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.TranslationCallback
import com.jielihome.jielihome.audio.OpusStreamDecoder
import com.jielihome.jielihome.core.JieliHomeServer
import com.jielihome.jielihome.feature.translation.runtime.NoOpAITranslationApi
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import java.util.concurrent.atomic.AtomicLong

/** 录音音频帧（已解码为 PCM_S16LE，双声道交织 L/R/L/R …）。 */
data class DeviceRecordFrame(
    val address: String,
    /** 当前固定为 [JieliDeviceRecordPort.STREAM_STEREO]。双声道交织 PCM；左=本端，右=对端 */
    val streamId: String,
    val pcm: ByteArray,
    val sampleRate: Int,
    val channels: Int = 2,
    val bitsPerSample: Int = 16,
    val tsMs: Long,
) {
    override fun equals(other: Any?): Boolean = this === other
    override fun hashCode(): Int = System.identityHashCode(this)
}

/** 录音错误。 */
data class DeviceRecordError(val address: String?, val code: Int, val message: String?)

/**
 * 设备录音端口 —— **立体声通话翻译模式（MODE_CALL_TRANSLATION_WITH_STEREO=6）+ 双声道**版。
 *
 * # 设计要点
 * 与 [com.jielihome.jielihome.feature.assistant.JieliAssistantPort] 是同构关系，只是
 * 一个单声道、一个双声道：
 * - JieliAssistantPort：mode=MODE_RECORD(1) + ch=1，耳机麦单通道上行
 * - 本类：              mode=MODE_CALL_TRANSLATION_WITH_STEREO(6) + ch=2，耳机持续
 *                       上推双声道（L=本端 UPLINK / R=对端 DOWNLINK）OPUS（source =
 *                       SOURCE_E_SCO_MIX），由 [OpusStreamDecoder] 解码成 16k/16bit
 *                       /stereo 交织 PCM 抛给 [audioFrames]
 *
 * 通路：
 *   耳机双麦 → 耳机固件 OPUS 编码（stereo, MIX） → onReceiveAudioData
 *     → OpusStreamDecoder(channel=2, packetSize=80) → 16k/16bit/stereo 交织 PCM
 *     → SharedFlow
 *
 * # 与 [DeviceRecordFeature] 的关系
 * 两者都是录音通路实现，但走两条独立的 TranslationImpl：
 *   - [DeviceRecordFeature]：MODE_CALL_TRANSLATION + ch=1，单声道分两路（uplink/downlink）
 *   - 本类：                MODE_CALL_TRANSLATION_WITH_STEREO + ch=2，双声道一路 stereo
 * SDK enterMode 是设备级互斥的，两者不能同时活跃。Port 内部不再依赖 feature；
 * MethodRouter / Flutter 侧仍走 feature，保持兼容。
 *
 * # 设备能力
 * 进入前会校验 `TranslationImpl.isSupportCallTranslationWithStereo`；不支持的耳机直接
 * 失败返回，避免下发后耳机状态机卡 IDLE 静默丢帧。
 *
 * # 格式
 * PCM_S16LE / 16 kHz / **stereo** / 20 ms。stereo 16k/16bit/20ms ≈ 80 B/OPUS 帧。
 *
 * # 线程安全
 * `start` / `stop` 通过 `synchronized(this)` 互斥；
 * SharedFlow.tryEmit 自身线程安全；SDK 回调线程不固定，所有共享状态用 @Volatile 标记。
 */
class JieliDeviceRecordPort(
    private val server: JieliHomeServer,
) {
    companion object {
        private const val TAG = "JieliDeviceRecordPort"

        /** 双声道交织 PCM，左=本端（耳机麦），右=对端（通话对方/参考） */
        const val STREAM_STEREO = "in.stereo"
    }

    private val _audioFrames = MutableSharedFlow<DeviceRecordFrame>(
        replay = 0,
        extraBufferCapacity = 256,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    private val _errors = MutableSharedFlow<DeviceRecordError>(
        replay = 0,
        extraBufferCapacity = 16,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    /** 录音 PCM 帧流（双声道交织）。 */
    val audioFrames: Flow<DeviceRecordFrame> = _audioFrames.asSharedFlow()

    /** 错误流。 */
    val errors: Flow<DeviceRecordError> = _errors.asSharedFlow()

    @Volatile private var entered = false
    @Volatile private var device: BluetoothDevice? = null
    @Volatile private var sampleRateHz = 16000
    @Volatile private var decoder: OpusStreamDecoder? = null
    @Volatile private var translationImpl: TranslationImpl? = null
    @Volatile private var translationCallback: TranslationCallback? = null

    val isRecording: Boolean get() = entered

    /** 调试统计：每秒打一次 SDK PCM 帧产出量 */
    private val upCount = AtomicLong(0)
    @Volatile private var lastReportMs = 0L
    /** 首帧 flag：首次 onModeChange / onReceiveAudioData / 首次 PCM 帧发射都各打一条 INFO */
    @Volatile private var rxFirstModeChangeLogged = false
    @Volatile private var rxFirstAudioLogged = false

    /**
     * 启动设备录音上行（MODE_RECORDING_TRANSLATION + stereo + DEVICE_ALWAYS_RECORDING）。
     *
     * @param address 目标设备 MAC；null 取当前已连设备
     * @param sampleRate 采样率（Hz），默认 16000
     */
    @Synchronized
    fun start(address: String? = null, sampleRate: Int = 16000): Result<Unit> {
        if (entered) return Result.failure(IllegalStateException("already recording"))

        // 与 TranslationFeature 互斥：两者都调用 enterMode，同时只能一个活跃
        if (server.translationFeature.isWorking()) server.translationFeature.stop()

        val dev = address?.let { server.connectFeature.deviceByAddress(it) }
            ?: server.connectFeature.connectedDevice()
            ?: return Result.failure(
                IllegalStateException("device.record.no_device: pass args.address or connect first")
            )

        sampleRateHz = sampleRate

        // 1. 启动 Opus 解码器：耳机推上来的录音流是 stereo OPUS。
        //    packetSize 是单帧真实大小：stereo 16k/16bit/20ms ≈ 80 B（mono 是 40 B）。
        //    详见 OpusStreamDecoder 注释。
        val od = OpusStreamDecoder(
            channel = 2,
            packetSize = 80,
            sampleRate = sampleRate,
            onPcm = { stereoPcm -> emitStereoFrame(dev.address, stereoPcm) },
            onError = { c, m ->
                _errors.tryEmit(
                    DeviceRecordError(
                        address = dev.address,
                        code = c,
                        message = "opus stereo decode: ${m ?: ""}",
                    )
                )
            },
        ).also { it.start() }
        decoder = od

        // 2. 构造 TranslationImpl + 前置校验
        val impl = TranslationImpl(server.internalBtManager, NoOpAITranslationApi(), dev)
        if (!impl.isInit) {
            runCatching { impl.destroy() }
            cleanup()
            return Result.failure(
                IllegalStateException("device.record.rcsp_not_init: RCSP not init for ${dev.address}")
            )
        }
        if (!impl.isSupportTranslation) {
            runCatching { impl.destroy() }
            cleanup()
            return Result.failure(
                IllegalStateException("device.record.not_supported: device does not support translation")
            )
        }
        if (!impl.isSupportCallTranslationWithStereo) {
            runCatching { impl.destroy() }
            cleanup()
            return Result.failure(
                IllegalStateException("device.record.stereo_not_supported: device does not support stereo call translation")
            )
        }

        // 3. 注册 TranslationCallback
        val cb = object : TranslationCallback {
            override fun onModeChange(d: BluetoothDevice, m: TranslationMode) {
                if (!rxFirstModeChangeLogged) {
                    rxFirstModeChangeLogged = true
                    Log.i(TAG, "[SDK<-DEV] onModeChange FIRST addr=${d.address} mode=${m.mode} type=${m.audioType} ch=${m.channel} sr=${m.sampleRate} strategy=${m.recordingStrategy}")
                } else {
                    Log.i(TAG, "[SDK<-DEV] onModeChange addr=${d.address} mode=${m.mode} strategy=${m.recordingStrategy}")
                }
                if (m.mode == TranslationMode.MODE_IDLE) {
                    _errors.tryEmit(
                        DeviceRecordError(
                            address = d.address,
                            code = -1,
                            message = "headset exited MODE_CALL_TRANSLATION_WITH_STEREO → MODE_IDLE",
                        )
                    )
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
                    Constants.AUDIO_TYPE_PCM -> emitStereoFrame(d.address, payload)
                    Constants.AUDIO_TYPE_OPUS -> decoder?.feedEncoded(payload)
                    else -> Log.w(TAG, "[SDK<-DEV] onReceiveAudioData unknown type=${data.type} (skip)")
                }
            }

            override fun onError(d: BluetoothDevice, code: Int, msg: String) {
                Log.e(TAG, "[SDK<-DEV] TranslationCallback.onError code=$code msg=$msg")
                _errors.tryEmit(
                    DeviceRecordError(
                        address = d.address,
                        code = code,
                        message = msg,
                    )
                )
            }
        }
        impl.addTranslationCallback(cb)
        translationImpl = impl
        translationCallback = cb
        device = dev

        // 4. 下发 enterMode(MODE_CALL_RECORD=7, OPUS, ch=2, sr, STRATEGY_DEVICE_ALWAYS_RECORDING)
        //    - mode=6：立体声通话翻译模式，耳机 RCSP 状态机进入 STEREO 状态，固件按
        //              SOURCE_E_SCO_MIX 上推双声道交织 OPUS
        //    - ch=2：  双声道（L=本端 UPLINK 耳机麦，R=对端 DOWNLINK 通话音/参考）
        //    - STRATEGY_DEVICE_ALWAYS_RECORDING=1：耳机固件自主采集并持续上推，APP 不用手机麦
        val sdkMode = TranslationMode(
            TranslationMode.MODE_CALL_RECORD,
            Constants.AUDIO_TYPE_OPUS,
            2,
            sampleRate,
        ).setRecordingStrategy(TranslationMode.STRATEGY_DEVICE_ALWAYS_RECORDING)
        Log.i(TAG, "[APP->SDK] enterMode addr=${dev.address} mode=${sdkMode.mode}(MODE_CALL_TRANSLATION_WITH_STEREO) type=${sdkMode.audioType}(OPUS) ch=${sdkMode.channel} sr=${sdkMode.sampleRate} strategy=${sdkMode.recordingStrategy}(DEVICE_ALWAYS_RECORDING)")
        impl.enterMode(sdkMode, cb)

        entered = true
        Log.d(TAG, "entered device record mode (MODE_CALL_TRANSLATION_WITH_STEREO=6, ch=2, DEVICE_ALWAYS_RECORDING)")
        return Result.success(Unit)
    }

    private fun emitStereoFrame(address: String, pcm: ByteArray) {
        upCount.incrementAndGet()
        val now = System.currentTimeMillis()
        if (now - lastReportMs >= 1000L) {
            Log.d(TAG, "uplink stereo PCM stats (last 1s): frames=${upCount.getAndSet(0)} bytes/frame=${pcm.size}")
            lastReportMs = now
        }
        val frame = DeviceRecordFrame(
            address = address,
            streamId = STREAM_STEREO,
            pcm = pcm,
            sampleRate = sampleRateHz,
            channels = 2,
            bitsPerSample = 16,
            tsMs = now,
        )
        if (!_audioFrames.tryEmit(frame)) {
            Log.w(TAG, "audioFrames buffer overflow; dropped streamId=$STREAM_STEREO")
        }
    }

    /** 停止设备录音上行。幂等。 */
    @Synchronized
    fun stop() {
        if (!entered) return
        entered = false
        cleanup()
        Log.d(TAG, "exited device record mode")
    }

    /** 释放 enterMode / decoder / callback；可被 start 失败路径调用，幂等 */
    private fun cleanup() {
        val impl = translationImpl
        val cb = translationCallback
        val addr = device?.address
        if (impl != null) {
            runCatching {
                Log.i(TAG, "[APP->SDK] exitMode addr=$addr mode=${TranslationMode.MODE_CALL_RECORD}")
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
        translationImpl = null
        translationCallback = null
        decoder = null
        device = null
        rxFirstModeChangeLogged = false
        rxFirstAudioLogged = false
    }

    /** 兼容旧签名：本类不再依赖 EventDispatcher，无需 release。 */
    fun release() {
        stop()
    }
}
