package com.jielihome.jielihome.feature.translation

import com.jielihome.jielihome.bridge.EventDispatcher

/**
 * 默认桥实现：采集帧通过 EventChannel 推到 Dart（base64 PCM），
 * Dart 把 PCM 喂给外部翻译服务，再通过 MethodChannel 回调 [TranslationFeature.feedTranslatedAudio]。
 *
 * 16kHz / 16bit / 单声道 PCM 流量约 32KB/s，base64 后 ~43KB/s，跨通道开销可控。
 * 若宿主想完全 native 直连翻译服务，可实现自己的 [TranslationAudioBridge] 并通过
 * [TranslationFeature.setBridge] 替换。
 */
class EventChannelAudioBridge(
    private val dispatcher: EventDispatcher,
    /** 由 TranslationFeature 注入：把 PCM 真正塞回当前 ModeHandler */
    var injector: TranslationAudioInjector? = null,
) : TranslationAudioBridge {

    override fun emitAudioFrame(
        modeId: Int,
        streamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        seq: Long,
        tsMs: Long,
        isFinal: Boolean,
    ) {
        // EventChannel 原生支持 byte[] → Uint8List，直接传字节流，避免 base64 33% 体积膨胀。
        dispatcher.send(
            mapOf(
                "type" to "translationAudio",
                "modeId" to modeId,
                "streamId" to streamId,
                "sampleRate" to format.sampleRate,
                "channels" to format.channels,
                "bitsPerSample" to format.bitsPerSample,
                "seq" to seq,
                "tsMs" to tsMs,
                "final" to isFinal,
                "pcm" to pcm,
            )
        )
    }

    override fun emitTranslationResult(
        modeId: Int,
        srcLang: String?,
        srcText: String?,
        destLang: String?,
        destText: String?,
        requestId: String?,
    ) {
        dispatcher.send(
            mapOf(
                "type" to "translationResult",
                "modeId" to modeId,
                "srcLang" to srcLang,
                "srcText" to srcText,
                "destLang" to destLang,
                "destText" to destText,
                "requestId" to requestId,
            )
        )
    }

    override fun emitLog(modeId: Int, content: String) {
        dispatcher.send(
            mapOf("type" to "translationLog", "modeId" to modeId, "content" to content)
        )
    }

    override fun emitError(modeId: Int, code: Int, message: String?) {
        dispatcher.send(
            mapOf(
                "type" to "translationError",
                "modeId" to modeId,
                "code" to code,
                "message" to message
            )
        )
    }

    override fun feedTranslatedAudio(
        modeId: Int,
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean {
        return injector?.inject(modeId, outputStreamId, pcm, format, isFinal) ?: false
    }
}

/**
 * 内部接口：TranslationFeature 决定当前 ModeHandler 是谁，由它消费 PCM。
 */
fun interface TranslationAudioInjector {
    fun inject(
        modeId: Int,
        outputStreamId: String,
        pcm: ByteArray,
        format: AudioFormat,
        isFinal: Boolean,
    ): Boolean
}
