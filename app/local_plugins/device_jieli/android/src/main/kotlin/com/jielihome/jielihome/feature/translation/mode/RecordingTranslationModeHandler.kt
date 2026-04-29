package com.jielihome.jielihome.feature.translation.mode

import android.content.Context
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.audio.PhoneMicCapture
import com.jielihome.jielihome.feature.translation.AudioFormat
import com.jielihome.jielihome.feature.translation.BaseTranslationModeHandler
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationModeIds
import com.jielihome.jielihome.feature.translation.TranslationStreams

/**
 * MODE_RECORDING_TRANSLATION —— 流式录音翻译。等同于 RecordMode 的实时版，差别只在语义：
 * 调用方实现实时 STT/翻译流水线、不缓存整段录音再发。
 */
class RecordingTranslationModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    override val modeId = TranslationModeIds.MODE_RECORDING_TRANSLATION
    override val inputStreams = listOf(TranslationStreams.IN_MIC)
    override val outputStreams = listOf(TranslationStreams.OUT_SPEAKER)

    private var mic: PhoneMicCapture? = null

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        mic = PhoneMicCapture(
            context, sampleRate,
            onFrame = { pcm -> pushFrame(TranslationStreams.IN_MIC, pcm, AudioFormat(sampleRate, 1, 16)) },
            onError = { code, msg -> emitError(code, msg) },
        )
        if (mic?.start() != true) return
        working = true
        emitLog("RecordingTranslation start sampleRate=$sampleRate")
    }

    override fun stop() {
        if (!working) return
        mic?.stop()
        mic = null
        working = false
        emitLog("RecordingTranslation stop")
    }

    override fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        if (outputStreamId != TranslationStreams.OUT_SPEAKER) return false
        emitLog("recv tts ${pcm.size}B final=$isFinal")
        return true
    }
}
