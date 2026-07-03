package com.jielihome.jielihome.feature.translation

/**
 * 翻译流逻辑 ID 常量。
 * 「输入流」= 插件解码后推给翻译服务（设备麦克风、eSCO 上行/下行、本地音频文件等）。
 * 「输出流」= 翻译服务返回 TTS PCM 后，插件回送的目标（耳机扬声器、A2DP 本地、对端通话上行等）。
 */
object TranslationStreams {
    // 输入流：插件解码后推给翻译服务的音频
    const val IN_MIC = "in.mic"
    const val IN_UPLINK = "in.uplink"          // 通话上行：本机用户
    const val IN_DOWNLINK = "in.downlink"      // 通话下行：对端
    const val IN_AUDIO_FILE = "in.audioFile"   // 本地音频文件

    // 输出流：翻译服务回送 TTS 后插件应送达的目的地
    const val OUT_SPEAKER = "out.speaker"
    const val OUT_UPLINK = "out.uplink"        // 译文给对端听
    const val OUT_DOWNLINK = "out.downlink"    // 译文给本机用户听
    const val OUT_LOCAL_PLAYBACK = "out.localPlayback"
}

/** 一帧 PCM 音频规格 */
data class AudioFormat(
    val sampleRate: Int = 16000,
    val channels: Int = 1,
    val bitsPerSample: Int = 16,
)
