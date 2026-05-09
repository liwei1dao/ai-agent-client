package com.jielihome.jielihome.feature.translation.mode

import android.content.Context
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

    override val modeId = TranslationModeIds.MODE_CALL_TRANSLATION_WITH_STEREO
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
                if (source != AudioData.SOURCE_E_SCO_MIX) return@RcspTranslationRuntime
                val (left, right) = PcmKit.splitStereo16(stereoPcm)
                val fmt = AudioFormat(sampleRate, 1, 16)
                pushFrame(TranslationStreams.IN_UPLINK, left, fmt)
                pushFrame(TranslationStreams.IN_DOWNLINK, right, fmt)
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
        emitLog("StereoCallTranslation stop")
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
