package com.aiagent.plugin_interface

/**
 * 外部音频源格式。
 *
 * 用于"agent 不开自家麦克风、由调用方推送音频帧"的场景（典型：通话翻译——
 * 帧来自蓝牙耳机 RCSP，由 translate_server 编排器经 [NativeAgent.pushExternalAudioFrame]
 * 喂给翻译型 agent）。
 */
data class ExternalAudioFormat(
    val codec: Codec,
    val sampleRate: Int,
    val channels: Int,
    val frameMs: Int,
) {
    enum class Codec { OPUS, PCM_S16LE }

    companion object {
        /** 16 kHz / mono / 20 ms 一帧 OPUS（耳机端原生格式） */
        val OPUS_16K_MONO_20MS = ExternalAudioFormat(Codec.OPUS, 16000, 1, 20)

        /** 16 kHz / mono / 20 ms 一帧 PCM_S16LE = 640 字节 */
        val PCM_S16LE_16K_MONO_20MS = ExternalAudioFormat(Codec.PCM_S16LE, 16000, 1, 20)
    }
}

/**
 * Agent / Service 对外部音频源的接受能力。
 *
 * 协商规则（在 translate_server 编排器内）：
 * 1. 优先 OPUS（零转码，最低延迟）；
 * 2. 否则 PCM_S16LE，由 device 侧负责 OPUS→PCM 解码。
 *
 * 默认值 = `false / false` 表示 agent 不支持外部音频源；调用方据此抛
 * `agent does not support external audio`。
 */
data class ExternalAudioCapability(
    val acceptsOpus: Boolean,
    val acceptsPcm: Boolean,
    val preferredSampleRate: Int = 16000,
    val preferredChannels: Int = 1,
    val preferredFrameMs: Int = 20,
) {
    val supportsExternalAudio: Boolean get() = acceptsOpus || acceptsPcm

    companion object {
        val UNSUPPORTED = ExternalAudioCapability(false, false)
    }
}

/**
 * 单帧外部音频载荷。
 *
 * - 上行（调用方 → service / agent）通过 [pushExternalAudioFrame(ByteArray)] 直接传字节，
 *   格式由 [startExternalAudio] 协商；不需要 wrap 成 [ExternalAudioFrame]。
 * - 下行（service / agent → 调用方）通过 [ExternalAudioSink] 回灌，必须 wrap，
 *   因为 TTS 的输出格式可能与上行不一致（典型：上行 16kHz mono；TTS 输出 24kHz mono）。
 */
data class ExternalAudioFrame(
    val codec: ExternalAudioFormat.Codec,
    val sampleRate: Int,
    val channels: Int,
    val bytes: ByteArray,
    val timestampUs: Long = 0L,
    /** 本帧是否为当前 TTS utterance 的最后一帧（段边界）。下游可据此触发整段编码/一次性下发。 */
    val isFinal: Boolean = false,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ExternalAudioFrame) return false
        return codec == other.codec && sampleRate == other.sampleRate &&
            channels == other.channels && bytes.contentEquals(other.bytes)
    }
    override fun hashCode(): Int {
        var r = codec.hashCode()
        r = 31 * r + sampleRate
        r = 31 * r + channels
        r = 31 * r + bytes.contentHashCode()
        return r
    }
}

/**
 * 外部音频下行回写通道（service / agent → 调用方）。
 *
 * 通话翻译场景下，编排器把它注入 service，service 端把 TTS 字节回写过来，编排器
 * 再调 device 的 [DeviceCallTranslationPort.reportTranslated] 灌回耳机。
 */
interface ExternalAudioSink {
    /** TTS 一帧。同 sink 实例可能收到不同采样率的多帧。 */
    fun onTtsFrame(frame: ExternalAudioFrame)

    /** service 端非致命错误（连接抖动 / 协议错误等），sink 收到后由调用方决定是否 stop。 */
    fun onError(code: String, message: String) {}
}
