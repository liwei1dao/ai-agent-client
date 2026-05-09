package com.aiagent.device_plugin_interface

import kotlinx.coroutines.flow.Flow

/**
 * AI 助理场景的音频载荷编码。
 *
 * 与 [CallAudioCodec] 并列但语义独立 —— AI 助理是单向对话（用户麦 → AI → 耳机扬声器），
 * 没有通话翻译的 UPLINK/DOWNLINK 概念。
 */
enum class AssistantAudioCodec { OPUS, PCM_S16LE }

/** AI 助理场景的音频格式描述。 */
data class AssistantAudioFormat(
    val codec: AssistantAudioCodec,
    val sampleRate: Int,
    val channels: Int,
    val frameMs: Int,
) {
    companion object {
        /** 16 kHz / mono / 20 ms 一帧 OPUS（耳机原生格式） */
        val OPUS_16K_MONO_20MS = AssistantAudioFormat(AssistantAudioCodec.OPUS, 16000, 1, 20)

        /** 16 kHz / mono / 20 ms 一帧 PCM_S16LE = 640 字节 */
        val PCM_S16LE_16K_MONO_20MS = AssistantAudioFormat(AssistantAudioCodec.PCM_S16LE, 16000, 1, 20)
    }
}

/**
 * device → 编排器：一帧用户麦克风音频（单路上行）。
 *
 * 与 [CallAudioFrame] 的区别：**无 leg 字段**。AI 助理场景只有"用户说话"一路输入，
 * 不存在"远端通话音"的概念。
 */
data class AssistantAudioFrame(
    val codec: AssistantAudioCodec,
    val sampleRate: Int,
    val channels: Int,
    val bytes: ByteArray,
    /** 单调递增帧序号；丢帧后**不得**回填。 */
    val sequence: Long,
    /** 单调递增的捕获时间戳（微秒）。 */
    val timestampUs: Long,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AssistantAudioFrame) return false
        return sequence == other.sequence && bytes.contentEquals(other.bytes)
    }
    override fun hashCode(): Int {
        var r = sequence.hashCode()
        r = 31 * r + bytes.contentHashCode()
        return r
    }
}

/**
 * 编排器 → device：把 AI 的 TTS 音频回灌给耳机扬声器播放。
 *
 * 与 [TranslatedAudioFrame] 的区别：**无 leg 字段**。AI 助理只有一个回放方向
 * （AI 回复 → 戴耳机的用户），不存在"回灌给对端"的概念。
 *
 * @param isFinal 本帧是否为当前 utterance 的最后一帧。device 端可能据此决定是否
 *   触发整段编码 / 一次性下发（例如 jieli RCSP 场景下按"一段 = 一个 AudioData"下发）。
 */
data class AssistantPlaybackFrame(
    val codec: AssistantAudioCodec,
    val sampleRate: Int,
    val channels: Int,
    val bytes: ByteArray,
    val isFinal: Boolean = false,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is AssistantPlaybackFrame) return false
        return codec == other.codec && bytes.contentEquals(other.bytes)
    }
    override fun hashCode(): Int {
        var r = codec.hashCode()
        r = 31 * r + bytes.contentHashCode()
        return r
    }
}

/** AI 助理场景下由 device 抛出的错误（不致命：编排器决定是否 stop）。 */
data class AssistantError(
    val code: String,
    val message: String,
)

/**
 * AI 助理设备能力端口（device 侧）。
 *
 * 由设备厂商插件按需实现（例如杰理基于 RCSP `MODE_CALL_TRANSLATION` 的 `UP_LINK` 上行 +
 * `OUT_UPLINK` 回灌落地一份 `JieliAssistantPort`）。`assistant_server` 编排器统一通过
 * 本接口拿用户麦克风 PCM、回灌 AI TTS，不依赖具体 vendor。
 *
 * 与 [DeviceCallTranslationPort] 并列但**语义完全独立**：
 * - 不存在 leg 概念（通话翻译特有的上下行）
 * - 上行流只有一路（用户麦）
 * - 下行回灌只有一路（耳机扬声器）
 *
 * 生命周期：
 * ```
 * idle → enter(format) → active → exit() → idle
 * ```
 *
 * 铁律：
 * - 同一设备同一时刻**至多一个** active 端口；重复 `enter` 抛
 *   `IllegalStateException("device.assistant.busy")`；
 * - 协商格式（[enter] 入参）必须出自 [supportedSourceFormats] 列出的范围；
 * - [reportPlayback] 的 codec/sampleRate/channels 必须落在 [supportedSinkFormats] 内；
 * - [exit] 后 [audioFrames]/[errors] 仍可订阅，但不再产新事件。
 */
interface DeviceAssistantPort {
    /** 该端口能向上派发的用户麦克风音频格式集合。 */
    fun supportedSourceFormats(): Set<AssistantAudioFormat>

    /** 该端口能接受的 TTS 回灌格式集合。 */
    fun supportedSinkFormats(): Set<AssistantAudioFormat>

    /**
     * 进入 AI 助理模式。
     *
     * @param sourceFormat 协商好的源音频格式（必须 ∈ [supportedSourceFormats]）。
     * device 侧据此决定是否做 OPUS↔PCM 转换。
     */
    fun enter(sourceFormat: AssistantAudioFormat)

    /**
     * 用户麦克风上行音频帧流。`enter` 之后开始派发，`exit` 后停止。
     * 必须是 broadcast / replayable 不变的实现，编排器多次订阅安全。
     */
    val audioFrames: Flow<AssistantAudioFrame>

    /**
     * 把 AI 的 TTS 音频回灌给耳机扬声器。
     *
     * @throws IllegalArgumentException codec 不在 [supportedSinkFormats] 内
     * @throws IllegalStateException 当前未在 active 状态
     */
    fun reportPlayback(frame: AssistantPlaybackFrame)

    /** 退出 AI 助理模式，归还设备 RCSP / 音频通道。 */
    fun exit()

    /** 错误流。**不致命**——编排器自行决定是否 [exit]。 */
    val errors: Flow<AssistantError>
}
