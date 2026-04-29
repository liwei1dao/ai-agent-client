package com.jielihome.jielihome.feature.translation.mode

import android.content.Context
import com.jieli.bluetooth.bean.translation.AudioData
import com.jieli.bluetooth.bean.translation.TranslationMode
import com.jieli.bluetooth.constant.Constants
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.feature.ConnectFeature
import com.jielihome.jielihome.feature.translation.AudioFormat
import com.jielihome.jielihome.feature.translation.BaseTranslationModeHandler
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationModeIds
import com.jielihome.jielihome.feature.translation.TranslationStreams
import com.jielihome.jielihome.feature.translation.runtime.RcspTranslationRuntime
import java.io.File

/**
 * MODE_CALL_TRANSLATION —— 通话翻译，eSCO 上下行各一路单声道。
 * 输入：uplink（本机用户）+ downlink（对端）
 * 输出：uplink（TTS 给对端听）+ downlink（TTS 给本机用户听）
 *
 * 实现：通过 [RcspTranslationRuntime] 让耳机进入 SDK 翻译模式，
 *      OPUS 流式解码后按 source 分流推到 bridge；
 *      回送 TTS PCM 时编码 OPUS 后通过同一 runtime 写回耳机。
 */
class CallTranslationModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    private val connectFeature: ConnectFeature,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    override val modeId = TranslationModeIds.MODE_CALL_TRANSLATION
    override val inputStreams = listOf(TranslationStreams.IN_UPLINK, TranslationStreams.IN_DOWNLINK)
    override val outputStreams = listOf(TranslationStreams.OUT_UPLINK, TranslationStreams.OUT_DOWNLINK)

    private var runtime: RcspTranslationRuntime? = null

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val address = args["address"] as? String
            ?: connectFeature.connectedDevice()?.address
        val device = address?.let { connectFeature.deviceByAddress(it) }
            ?: connectFeature.connectedDevice()
        if (device == null) {
            emitError(-200, "no connected device; pass args.address or connect first")
            return
        }

        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        val audioType = parseAudioType(args["audioType"]) ?: Constants.AUDIO_TYPE_OPUS
        // Recording strategy 选择：
        //   STRATEGY_DEVICE_AUTO_RECORDING(2) —— 耳机自动检测真实 SCO 通话才开始录，
        //     手机端没在打电话时耳机不会上推 PCM，本场景（双向 AI 通话翻译）行不通。
        //   STRATEGY_DEVICE_ALWAYS_RECORDING(1) —— 一进入翻译模式就持续上推双声道
        //     PCM，正是 AI 通话翻译需要的"始终开麦"语义。
        // 允许通过 args["strategy"] 覆盖（数值或字符串 "auto"/"always"/"custom"）。
        val strategy = parseStrategy(args["strategy"])
            ?: TranslationMode.STRATEGY_DEVICE_ALWAYS_RECORDING
        val sdkMode = TranslationMode(
            TranslationMode.MODE_CALL_TRANSLATION,
            audioType,
            1,                                    // 单声道
            sampleRate,
        ).setRecordingStrategy(strategy)

        val rt = RcspTranslationRuntime(
            btManager = btManager,
            device = device,
            mode = sdkMode,
            tempDir = File(context.cacheDir, "jieli_translation_tts"),
            onPcm = { source, pcm ->
                val streamId = when (source) {
                    AudioData.SOURCE_E_SCO_UP_LINK -> TranslationStreams.IN_UPLINK
                    AudioData.SOURCE_E_SCO_DOWN_LINK -> TranslationStreams.IN_DOWNLINK
                    else -> return@RcspTranslationRuntime
                }
                pushFrame(streamId, pcm, AudioFormat(sampleRate, 1, 16))
            },
            onError = { code, msg -> emitError(code, msg) }
        )
        rt.start().fold(
            {
                runtime = rt
                working = true
                emitLog("CallTranslation start device=${device.address} audioType=$audioType sampleRate=$sampleRate")
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
        emitLog("CallTranslation stop")
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
