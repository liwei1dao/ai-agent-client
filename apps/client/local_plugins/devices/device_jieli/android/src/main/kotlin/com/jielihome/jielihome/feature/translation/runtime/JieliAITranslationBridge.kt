package com.jielihome.jielihome.feature.translation.runtime

import android.util.Log
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.bean.translation.TranslationResult
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.interfaces.rcsp.translation.AITranslationCallback
import com.jieli.bluetooth.interfaces.rcsp.translation.IAITranslationApi
import com.jieli.jl_audio_decode.callback.OnStateCallback
import com.jieli.jl_audio_decode.opus.OpusManager
import com.jielihome.jielihome.audio.OpusStreamDecoder
import com.jielihome.jielihome.feature.translation.TranslationStreams
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.atomic.AtomicLong

/**
 * 杰理 SDK 的 [IAITranslationApi] 实现 —— call translation 路径专用的「上下行接力桥」。
 *
 * # 为什么要有这个 bridge
 * 早先的实现（旧 [RcspTranslationRuntime]）走的是"自己手写 writeAudioData 队列"的方案：
 *  1. 用 [com.jieli.bluetooth.interfaces.rcsp.translation.TranslationCallback.onReceiveAudioData]
 *     拿上行 OPUS，自己解码；
 *  2. 把外部翻译服务回送的 PCM 周期切片 → OPUS 编码 → 用自己的 WriteScheduler 串行调
 *     [com.jieli.bluetooth.impl.rcsp.translation.TranslationImpl.writeAudioData] 推回耳机。
 *
 * 实测踩到的两个坑：
 *  - 周期切片（每 1s）→ 多段独立 OPUS → 耳机端解码器频繁 reset → 杂音 / 断续；
 *  - 自己维护 in-flight=1 的写队列，溢出丢最老 → utterance 中段被截掉。
 *
 * 官方 demo 的真正用法（[com.jieli.bt.sdk.tool.translation.AITranslationImpl]）：实现
 * [IAITranslationApi]，把整段 utterance 编一次 OPUS，包成 [AudioData] 塞进
 * [TranslationResult.translationTTSData] 然后调 [AITranslationCallback.onTranslateResult]，
 * **SDK 内部** 接管 cmd=52 切包 / 发送时序 / 缓冲水位。
 *
 * # 上下行职责
 * - **上行**（headset → app）：SDK 主动调 [writeAudio]，audioData.type = OPUS / PCM；
 *   按 [AudioData.source] 分流到 up/down/stereo decoder，解码后通过 [onPcm] 抛出去。
 * - **下行**（app → headset）：[feedTtsPcm] 累积外部翻译服务回送的 PCM，**纯 isFinal 驱动**：
 *   `isFinal=true` 时把累积 PCM 编成一段 OPUS，组装 [TranslationResult] 丢给 SDK。
 *   不再有周期 flush。如果上层一直不发 isFinal，缓冲到 [PCM_BUFFER_HARD_LIMIT_BYTES]
 *   兜底强制 flush，避免内存爆。
 *
 * # 与 [NoOpAITranslationApi] 的区别
 * - [NoOpAITranslationApi]：纯录音通路（JieliAssistantPort / JieliDeviceRecordPort 等）
 *   只想拿原始 PCM，不希望 SDK 触发 AI 流程。
 * - 本类：通话翻译需要"上行解码 + 下行 SDK 接管 TTS 注入"，要走 SDK 的标准 AI hook。
 *
 * # 线程
 * - SDK 回调线程不固定；解码器 / 编码器调用都不假设线程。
 * - [feedTtsPcm] 可被任意线程调用，per-leg 缓冲用 [bufferLock] 互斥。
 * - OPUS 文件编码异步（[OpusManager.encodeFile] 内部线程），完成后回到 SDK callback。
 */
class JieliAITranslationBridge(
    private val mode: TranslationMode,
    private val tempDir: File,
    /** 解码后的上行 PCM 出口；source 为 SDK 原值（SOURCE_E_SCO_UP_LINK / DOWN_LINK / MIX）。 */
    private val onPcm: (source: Int, pcm: ByteArray) -> Unit,
    /** 解码 / 编码失败的统一出口。 */
    private val onError: (code: Int, msg: String?) -> Unit,
    private val opusPacketSize: Int = if (mode.channel == 2) 80 else 200,
) : IAITranslationApi {

    companion object {
        private const val TAG = "JieliAITranslationBridge"
        /** 单段 utterance PCM 上限：≈ 60s 16k mono 16bit = 1.92MB。超限强制 flush 兜底。 */
        private const val PCM_BUFFER_HARD_LIMIT_BYTES = 2 * 1024 * 1024
    }

    private val isPcmMode = mode.audioType == Constants.AUDIO_TYPE_PCM
    private val sampleRateHz = mode.sampleRate.takeIf { it > 0 } ?: 16000

    @Volatile private var sdkCallback: AITranslationCallback? = null
    @Volatile private var working = false

    /** 上行 OPUS 解码器：通话翻译有 up/down 两路单声道，stereo 模式只一路双声道。 */
    private val upDecoder: OpusStreamDecoder? = if (isPcmMode) null else OpusStreamDecoder(
        channel = 1,
        packetSize = opusPacketSize,
        sampleRate = sampleRateHz,
        onPcm = { pcm -> onPcm(AudioData.SOURCE_E_SCO_UP_LINK, pcm) },
        onError = { c, m -> onError(c, "upDecoder: $m") },
    )
    private val downDecoder: OpusStreamDecoder? =
        if (!isPcmMode && mode.mode == TranslationMode.MODE_CALL_TRANSLATION) OpusStreamDecoder(
            channel = 1,
            packetSize = opusPacketSize,
            sampleRate = sampleRateHz,
            onPcm = { pcm -> onPcm(AudioData.SOURCE_E_SCO_DOWN_LINK, pcm) },
            onError = { c, m -> onError(c, "downDecoder: $m") },
        ) else null
    private val stereoDecoder: OpusStreamDecoder? =
        if (!isPcmMode && mode.mode == TranslationMode.MODE_CALL_TRANSLATION_WITH_STEREO) OpusStreamDecoder(
            channel = 2, packetSize = 80,
            sampleRate = sampleRateHz,
            onPcm = { pcm -> onPcm(AudioData.SOURCE_E_SCO_MIX, pcm) },
            onError = { c, m -> onError(c, "stereoDecoder: $m") },
        ) else null

    /** Per-leg PCM 缓冲：key = outputStreamId（OUT_UPLINK / OUT_DOWNLINK / OUT_SPEAKER）。 */
    private val pcmBuffers = mutableMapOf<String, ByteArrayOutputStream>()
    private val bufferLock = Any()
    private val encodeSeq = AtomicLong(0)

    /** 调试统计 */
    @Volatile private var rxFirstLogged = false
    private val rxFirstPerSource = java.util.concurrent.ConcurrentHashMap<Int, Boolean>()

    // ─── IAITranslationApi 实现 ───────────────────────────────────────────

    override fun isWorking(): Boolean = working

    override fun startTranslating(mode: TranslationMode, callback: AITranslationCallback) {
        Log.i(TAG, "[SDK->APP] startTranslating mode=${mode.mode} type=${mode.audioType} sr=${mode.sampleRate} ch=${mode.channel}")
        sdkCallback = callback
        if (!tempDir.exists()) tempDir.mkdirs()
        upDecoder?.start()
        downDecoder?.start()
        stereoDecoder?.start()
        working = true
        callback.onStart()
    }

    override fun stopTranslating() {
        Log.i(TAG, "[SDK->APP] stopTranslating")
        working = false
        runCatching { upDecoder?.stop() }
        runCatching { downDecoder?.stop() }
        runCatching { stereoDecoder?.stop() }
        // 兜底：剩余 buffer 直接丢，不补发 onTranslateResult（utterance 已被打断）。
        synchronized(bufferLock) {
            pcmBuffers.values.forEach { it.reset() }
            pcmBuffers.clear()
        }
        sdkCallback?.onStop(0, "stopTranslating")
        sdkCallback = null
    }

    override fun writeAudio(data: AudioData) {
        if (!working) return
        if (data.type != mode.audioType) {
            // SDK 极少数情况下会推与 mode.audioType 不一致的帧（例如握手期残留）；忽略不报错。
            return
        }
        val payload = data.audioData ?: return
        if (payload.isEmpty()) return

        // 首帧（总）
        if (!rxFirstLogged) {
            rxFirstLogged = true
            Log.i(TAG, "[SDK->APP] writeAudio FIRST source=${data.source} type=${data.type} size=${payload.size}")
        }
        // 首帧（按 source）
        if (rxFirstPerSource.putIfAbsent(data.source, true) == null) {
            Log.i(TAG, "[SDK->APP] writeAudio FIRST source=${data.source} size=${payload.size}")
        }

        if (isPcmMode) {
            onPcm(data.source, payload)
            return
        }
        when (data.source) {
            AudioData.SOURCE_E_SCO_UP_LINK -> upDecoder?.feedEncoded(payload)
            AudioData.SOURCE_E_SCO_DOWN_LINK -> downDecoder?.feedEncoded(payload)
            AudioData.SOURCE_E_SCO_MIX -> stereoDecoder?.feedEncoded(payload)
            else -> Log.w(TAG, "[SDK->APP] writeAudio unknown source=${data.source} size=${payload.size}")
        }
    }

    // ─── 下行：外部翻译服务的 TTS PCM 接力 ─────────────────────────────────

    /**
     * 把外部翻译服务回送的 TTS PCM 接力给 SDK。
     *
     * 策略：
     *  - PCM 模式：每次调用作为一段 [AudioData] 直接交给 SDK。
     *  - OPUS 模式：累积 per-leg buffer；`isFinal=true` 或缓冲到 [PCM_BUFFER_HARD_LIMIT_BYTES]
     *    时整段编码 → 通过 [AITranslationCallback.onTranslateResult] 交给 SDK，SDK 内部
     *    完成 cmd=52 切包 / 发送 / 速率控制。
     *
     * @return 是否接受本帧（false 表示丢弃，例如未启动 / 缓冲爆 / SDK callback 缺失）
     */
    fun feedTtsPcm(outputStreamId: String, pcm: ByteArray, isFinal: Boolean): Boolean {
        if (!working) return false
        val cb = sdkCallback ?: return false
        val source = sourceOf(outputStreamId)

        if (isPcmMode) {
            postTranslationResult(cb, source, Constants.AUDIO_TYPE_PCM, pcm)
            return true
        }
        // OPUS 模式：累积 + isFinal/超限触发整段编码
        val pendingFlush: ByteArray? = synchronized(bufferLock) {
            val buf = pcmBuffers.getOrPut(outputStreamId) { ByteArrayOutputStream() }
            if (pcm.isNotEmpty()) {
                if (buf.size() + pcm.size > PCM_BUFFER_HARD_LIMIT_BYTES) {
                    Log.w(TAG, "feedTtsPcm leg=$outputStreamId buffer hit hard limit ${PCM_BUFFER_HARD_LIMIT_BYTES}, force flush")
                    val out = buf.toByteArray() + pcm
                    buf.reset()
                    return@synchronized out
                }
                buf.write(pcm)
            }
            if (isFinal) {
                val out = buf.toByteArray()
                buf.reset()
                if (out.isEmpty()) null else out
            } else null
        }
        if (pendingFlush != null) {
            encodeAndDeliverAsync(cb, source, outputStreamId, pendingFlush)
        }
        return true
    }

    private fun postTranslationResult(
        cb: AITranslationCallback,
        source: Int,
        audioType: Int,
        bytes: ByteArray,
    ) {
        val result = TranslationResult().also {
            it.translationTTSData = AudioData(source, audioType, bytes)
        }
        runCatching { cb.onTranslateResult(result) }.onFailure {
            Log.w(TAG, "onTranslateResult threw: ${it.message}")
        }
    }

    private fun encodeAndDeliverAsync(
        cb: AITranslationCallback,
        source: Int,
        leg: String,
        pcmBytes: ByteArray,
    ) {
        val seq = encodeSeq.incrementAndGet()
        val pcmFile = File(tempDir, "tts_${source}_$seq.pcm")
        val opusFile = File(tempDir, "tts_${source}_$seq.opus")
        try {
            pcmFile.writeBytes(pcmBytes)
        } catch (e: Throwable) {
            Log.w(TAG, "encodeAndDeliver leg=$leg seq=$seq write pcm failed: ${e.message}")
            return
        }
        // OpusManager 默认 OpusOption（带 head），与 demo `MachineTranslation.tryToTTS` 一致；
        // SDK 接收端按"完整带 head 的 OPUS 段"解析，所以一次 onTranslateResult = 一段 utterance。
        val encoder = OpusManager()
        encoder.encodeFile(pcmFile.absolutePath, opusFile.absolutePath, object : OnStateCallback {
            override fun onStart() {}
            override fun onComplete(path: String?) {
                try {
                    val opusBytes = if (opusFile.exists()) opusFile.readBytes() else null
                    if (opusBytes == null || opusBytes.isEmpty()) {
                        Log.w(TAG, "encodeAndDeliver leg=$leg seq=$seq: empty opus output")
                    } else {
                        Log.d(TAG, "encodeAndDeliver leg=$leg seq=$seq pcm=${pcmBytes.size}B opus=${opusBytes.size}B → onTranslateResult")
                        postTranslationResult(cb, source, Constants.AUDIO_TYPE_OPUS, opusBytes)
                    }
                } finally {
                    runCatching { encoder.release() }
                    runCatching { pcmFile.delete() }
                    runCatching { opusFile.delete() }
                }
            }
            override fun onError(code: Int, message: String?) {
                Log.w(TAG, "encodeAndDeliver leg=$leg seq=$seq encodeFile error code=$code msg=$message")
                runCatching { encoder.release() }
                runCatching { pcmFile.delete() }
                runCatching { opusFile.delete() }
                onError(code, "encodeFile $leg: $message")
            }
        })
    }

    private fun sourceOf(outputStreamId: String): Int = when (outputStreamId) {
        TranslationStreams.OUT_UPLINK -> AudioData.SOURCE_E_SCO_UP_LINK
        TranslationStreams.OUT_DOWNLINK -> AudioData.SOURCE_E_SCO_DOWN_LINK
        else -> AudioData.SOURCE_PHONE_MIC
    }
}
