package com.jielihome.jielihome.feature.translation.mode

import android.content.Context
import android.util.Log
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.audio.PcmKit
import com.jielihome.jielihome.feature.ConnectFeature
import com.jielihome.jielihome.feature.translation.AudioFormat
import com.jielihome.jielihome.feature.translation.BaseTranslationModeHandler
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationModeIds
import com.jielihome.jielihome.feature.translation.TranslationStreams
import com.jielihome.jielihome.feature.translation.runtime.RcspTranslationRuntime
import java.io.File
import kotlin.math.sqrt

/**
 * MODE_CALL_TRANSLATION_WITH_STEREO —— 立体声通话翻译。
 * SDK 上来一路立体声 PCM（左=上行，右=下行），软件分离后等价于普通通话翻译两路。
 */
class StereoCallTranslationModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    private val connectFeature: ConnectFeature,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    companion object {
        private const val TAG = "StereoCallTransHandler"
    }

    override val modeId = TranslationModeIds.MODE_CALL_TRANSLATION_WITH_STEREO
    override val inputStreams = listOf(TranslationStreams.IN_UPLINK, TranslationStreams.IN_DOWNLINK)
    override val outputStreams = listOf(TranslationStreams.OUT_UPLINK, TranslationStreams.OUT_DOWNLINK)

    private var runtime: RcspTranslationRuntime? = null

    // 诊断：每秒打一次 L/R 能量。可定位 “对方说话没接入” 是因为
    // SDK 根本没推 stereo（看 bridge writeAudio FIRST source 日志），
    // 还是 R 声道恒为 0（耳机端无 SCO 下行）。
    private var diagFrameCount: Long = 0
    private var diagRmsL: Double = 0.0
    private var diagRmsR: Double = 0.0
    private var diagLastReportMs: Long = 0
    private val diagLock = Any()

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val address = args["address"] as? String
            ?: connectFeature.connectedDevice()?.address
        val device = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice()
        if (device == null) {
            emitError(-200, "no connected device")
            return
        }
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        val audioType = parseAudioType(args["audioType"]) ?: Constants.AUDIO_TYPE_OPUS
        // 与 demo 对齐：默认 ALWAYS_RECORDING，进 mode 即持续上推 PCM；
        // AUTO 会在没有真实通话事件时静默不出帧。
        val strategy = parseStrategy(args["strategy"])
            ?: TranslationMode.STRATEGY_DEVICE_ALWAYS_RECORDING
        val sdkMode = TranslationMode(
            TranslationMode.MODE_CALL_TRANSLATION_WITH_STEREO,
            audioType,
            2,                                    // 立体声
            sampleRate,
        ).setRecordingStrategy(strategy)

        val rt = RcspTranslationRuntime(
            btManager = btManager,
            device = device,
            mode = sdkMode,
            tempDir = File(context.cacheDir, "jieli_translation_tts"),
            onPcm = { source, stereoPcm ->
                if (source != AudioData.SOURCE_E_SCO_MIX) {
                    Log.w(TAG, "drop non-MIX source=$source size=${stereoPcm.size} (mode=6 expects SOURCE_E_SCO_MIX)")
                    return@RcspTranslationRuntime
                }
                val (left, right) = PcmKit.splitStereo16(stereoPcm)
                val fmt = AudioFormat(sampleRate, 1, 16)
                pushFrame(TranslationStreams.IN_UPLINK, left, fmt)
                pushFrame(TranslationStreams.IN_DOWNLINK, right, fmt)
                reportChannelEnergy(left, right)
            },
            onError = { code, msg -> emitError(code, msg) }
        )
        rt.start().fold(
            {
                runtime = rt
                working = true
                emitLog("StereoCallTranslation start device=${device.address} audioType=$audioType sampleRate=$sampleRate")
            },
            { emitError(-201, it.message); rt.stop() },
        )
    }

    private fun parseStrategy(raw: Any?): Int? = when (raw) {
        null -> null
        is Int -> raw
        is Number -> raw.toInt()
        is String -> when (raw.lowercase()) {
            "custom" -> TranslationMode.STRATEGY_CUSTOM_RECORDING
            "always" -> TranslationMode.STRATEGY_DEVICE_ALWAYS_RECORDING
            "auto" -> TranslationMode.STRATEGY_DEVICE_AUTO_RECORDING
            else -> raw.toIntOrNull()
        }
        else -> null
    }

    private fun parseAudioType(raw: Any?): Int? = when (raw) {
        null -> null
        is Int -> raw
        is Number -> raw.toInt()
        is String -> when (raw.lowercase()) {
            "opus" -> Constants.AUDIO_TYPE_OPUS
            "pcm" -> Constants.AUDIO_TYPE_PCM
            "speex" -> Constants.AUDIO_TYPE_SPEEX
            "msbc", "m_sbc" -> Constants.AUDIO_TYPE_M_SBC
            "jla_v2", "jlav2" -> Constants.AUDIO_TYPE_JLA_V2
            else -> raw.toIntOrNull()
        }
        else -> null
    }

    override fun stop() {
        if (!working) return
        runtime?.stop()
        runtime = null
        working = false
        synchronized(diagLock) {
            diagFrameCount = 0; diagRmsL = 0.0; diagRmsR = 0.0; diagLastReportMs = 0
        }
        emitLog("StereoCallTranslation stop")
    }

    /**
     * 每秒打一次左右两路 16-bit PCM 的 RMS 能量。
     *
     * 判读：
     *  - L/R 都 > 0 → SDK 推 stereo MIX、对端音频也接进来了；如果业务侧还说"接不到"，
     *    那是 captureBridge 或 pumpAudioFrames 后续链路的事。
     *  - L > 0, R ≈ 0 → SDK 推 stereo 但 right 恒静音（耳机端没有真实 SCO 下行；
     *    AI 助理场景下 mode=6 的已知限制：见 JIELI_SDK_COMMANDS.md §三）。
     *  - 一直没日志 → SDK 根本没推 SOURCE_E_SCO_MIX；看 bridge 的
     *    "writeAudio FIRST source=X" 日志确认 SDK 实际推的 source。
     */
    private fun reportChannelEnergy(left: ByteArray, right: ByteArray) {
        val now = System.currentTimeMillis()
        val rmsL = pcm16Rms(left)
        val rmsR = pcm16Rms(right)
        synchronized(diagLock) {
            diagFrameCount++
            diagRmsL += rmsL
            diagRmsR += rmsR
            if (diagLastReportMs == 0L) diagLastReportMs = now
            if (now - diagLastReportMs >= 1000L && diagFrameCount > 0) {
                val avgL = diagRmsL / diagFrameCount
                val avgR = diagRmsR / diagFrameCount
                Log.d(
                    TAG,
                    "stereo energy (last ${now - diagLastReportMs}ms): " +
                        "frames=$diagFrameCount L_rms=${"%.1f".format(avgL)} R_rms=${"%.1f".format(avgR)} " +
                        "(R≈0 ⇒ no SCO downlink)"
                )
                diagFrameCount = 0; diagRmsL = 0.0; diagRmsR = 0.0; diagLastReportMs = now
            }
        }
    }

    private fun pcm16Rms(pcm: ByteArray): Double {
        if (pcm.size < 2) return 0.0
        var sumSq = 0.0
        var n = 0
        var i = 0
        while (i + 1 < pcm.size) {
            val s = ((pcm[i].toInt() and 0xff) or (pcm[i + 1].toInt() shl 8)).toShort().toInt()
            sumSq += (s * s).toDouble()
            n++
            i += 2
        }
        return if (n == 0) 0.0 else sqrt(sumSq / n)
    }

    override fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        if (outputStreamId != TranslationStreams.OUT_UPLINK &&
            outputStreamId != TranslationStreams.OUT_DOWNLINK) return false
        return runtime?.feedTtsPcm(outputStreamId, pcm, isFinal) ?: false
    }
}
