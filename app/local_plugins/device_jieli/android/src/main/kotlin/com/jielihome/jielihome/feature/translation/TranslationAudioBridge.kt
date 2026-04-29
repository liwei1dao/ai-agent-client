package com.jielihome.jielihome.feature.translation

/**
 * 翻译音频桥：插件 ↔ 外部翻译服务 的双向接口。
 *
 * - 「采集面」：ModeHandler 调用 [emitAudioFrame] 把解码后的 PCM 帧推出去。
 *   默认实现走 EventChannel 推到 Dart，由 Dart 转发到外部翻译服务。
 *   也可以由宿主原生代码替换成自定义实现（比如直接走 gRPC）。
 *
 * - 「回放面」：[feedTranslatedAudio] 是入口，外部翻译服务调用，把 TTS PCM 注入进来。
 *   交给当前 ModeHandler 编码并回送到耳机/A2DP。
 *
 * - 文本结果（字幕）走 [emitTranslationResult]，纯展示用，不影响音频路径。
 */
interface TranslationAudioBridge {

    /** 插件→外部 ：推一帧采集到的 PCM 音频 */
    fun emitAudioFrame(
        modeId: Int,
        streamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        seq: Long,
        tsMs: Long,
        isFinal: Boolean = false,
    )

    /** 插件→外部 ：推翻译文本（可选）。requestId 由调用方贯穿同一段翻译，便于字幕拼接 */
    fun emitTranslationResult(
        modeId: Int,
        srcLang: String?,
        srcText: String?,
        destLang: String?,
        destText: String?,
        requestId: String? = null,
    )

    /** 插件→外部 ：日志 */
    fun emitLog(modeId: Int, content: String)

    /** 插件→外部 ：错误 */
    fun emitError(modeId: Int, code: Int, message: String?)

    /** 外部→插件 ：注入翻译完成的 TTS PCM；插件负责回送到 outputStreamId 对应的物理通道 */
    fun feedTranslatedAudio(
        modeId: Int,
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean
}
