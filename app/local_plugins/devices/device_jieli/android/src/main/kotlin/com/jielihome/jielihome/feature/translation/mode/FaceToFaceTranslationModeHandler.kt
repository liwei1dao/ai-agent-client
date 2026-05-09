package com.jielihome.jielihome.feature.translation.mode

import android.content.Context
import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.audio.LocalPlayer
import com.jielihome.jielihome.audio.PhoneMicCapture
import com.jielihome.jielihome.feature.translation.AudioFormat
import com.jielihome.jielihome.feature.translation.BaseTranslationModeHandler
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationModeIds
import com.jielihome.jielihome.feature.translation.TranslationStreams

/**
 * MODE_FACE_TO_FACE_TRANSLATION —— 面对面翻译。
 * 输入：手机麦
 * 输出：本机扬声器（自带的 LocalPlayer，A2DP/外放都行）
 */
class FaceToFaceTranslationModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    override val modeId = TranslationModeIds.MODE_FACE_TO_FACE_TRANSLATION
    override val inputStreams = listOf(TranslationStreams.IN_MIC)
    override val outputStreams = listOf(TranslationStreams.OUT_SPEAKER)

    private var mic: PhoneMicCapture? = null
    private var player: LocalPlayer? = null

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        mic = PhoneMicCapture(
            context, sampleRate,
            onFrame = { pcm -> pushFrame(TranslationStreams.IN_MIC, pcm, AudioFormat(sampleRate, 1, 16)) },
            onError = { code, msg -> emitError(code, msg) },
        )
        if (mic?.start() != true) return
        player = LocalPlayer(sampleRate, 1).also { it.start() }
        working = true
        emitLog("FaceToFaceTranslation start")
    }

    override fun stop() {
        if (!working) return
        mic?.stop(); mic = null
        player?.stop(); player = null
        working = false
        emitLog("FaceToFaceTranslation stop")
    }

    override fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        if (outputStreamId != TranslationStreams.OUT_SPEAKER) return false
        player?.feed(pcm)
        return true
    }
}
