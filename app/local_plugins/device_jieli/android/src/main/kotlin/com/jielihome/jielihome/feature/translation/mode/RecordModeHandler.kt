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
 * MODE_RECORD —— 单向录音翻译。
 * 输入：手机麦  →  推到外部
 * 输出：speaker  ←  外部回送 TTS PCM；当前不依赖耳机回送，直接交给宿主自行播放（可选）。
 *
 * 注：本模式完全不动 RCSP，只用手机麦。耳机端不需要进入翻译模式。
 */
class RecordModeHandler(
    private val context: Context,
    btManager: JL_BluetoothManager,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    override val modeId = TranslationModeIds.MODE_RECORD
    override val inputStreams = listOf(TranslationStreams.IN_MIC)
    override val outputStreams = listOf(TranslationStreams.OUT_SPEAKER)

    private var mic: PhoneMicCapture? = null

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        val frameMs = (args["frameDurationMs"] as? Int) ?: 20
        mic = PhoneMicCapture(
            context, sampleRate, frameMs,
            onFrame = { pcm -> pushFrame(TranslationStreams.IN_MIC, pcm, AudioFormat(sampleRate, 1, 16)) },
            onError = { code, msg -> emitError(code, msg) },
        )
        if (mic?.start() != true) return
        working = true
        emitLog("RecordMode start sampleRate=$sampleRate")
    }

    override fun stop() {
        if (!working) return
        mic?.stop()
        mic = null
        working = false
        emitLog("RecordMode stop")
    }

    override fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        if (outputStreamId != TranslationStreams.OUT_SPEAKER) return false
        // RECORD 模式下耳机不参与回送；如果宿主想播给用户听，自己用 AudioTrack 播即可。
        emitLog("recv tts pcm=${pcm.size}B final=$isFinal (host-side playback)")
        return true
    }
}
