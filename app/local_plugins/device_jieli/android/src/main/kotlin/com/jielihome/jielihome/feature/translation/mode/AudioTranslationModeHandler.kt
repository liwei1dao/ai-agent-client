package com.jielihome.jielihome.feature.translation.mode

import com.jieli.bluetooth.impl.JL_BluetoothManager
import com.jielihome.jielihome.audio.LocalPlayer
import com.jielihome.jielihome.feature.translation.AudioFormat
import com.jielihome.jielihome.feature.translation.BaseTranslationModeHandler
import com.jielihome.jielihome.feature.translation.TranslationAudioBridge
import com.jielihome.jielihome.feature.translation.TranslationModeIds
import com.jielihome.jielihome.feature.translation.TranslationStreams

/**
 * MODE_AUDIO_TRANSLATION —— 音视频翻译。
 * 输入：本地音频文件（由调用方自行解码并通过 [feedFilePcm] 灌进来，避免插件依赖各种封装格式解析）
 * 输出：本机扬声器（A2DP），不回耳机
 */
class AudioTranslationModeHandler(
    btManager: JL_BluetoothManager,
    bridge: TranslationAudioBridge,
) : BaseTranslationModeHandler(btManager, bridge) {

    override val modeId = TranslationModeIds.MODE_AUDIO_TRANSLATION
    override val inputStreams = listOf(TranslationStreams.IN_AUDIO_FILE)
    override val outputStreams = listOf(TranslationStreams.OUT_LOCAL_PLAYBACK)

    private var player: LocalPlayer? = null

    override fun start(args: Map<String, Any?>) {
        if (working) return
        val sampleRate = (args["sampleRate"] as? Int) ?: 16000
        val channels = (args["channels"] as? Int) ?: 1
        player = LocalPlayer(sampleRate, channels).also { it.start() }
        working = true
        emitLog("AudioTranslation start sampleRate=$sampleRate channels=$channels")
    }

    /** 调用方把解码出的 PCM 灌进来推给翻译服务 */
    @Suppress("unused")
    fun feedFilePcm(pcm: ByteArray, sampleRate: Int = 16000) {
        if (!working) return
        pushFrame(TranslationStreams.IN_AUDIO_FILE, pcm, AudioFormat(sampleRate, 1, 16))
    }

    override fun stop() {
        if (!working) return
        player?.stop()
        player = null
        working = false
        emitLog("AudioTranslation stop")
    }

    override fun onTranslatedAudio(
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        if (outputStreamId != TranslationStreams.OUT_LOCAL_PLAYBACK) return false
        player?.feed(pcm)
        return true
    }
}
