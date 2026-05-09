package com.aiagent.device_plugin_interface

import kotlinx.coroutines.flow.Flow

/**
 * 通话翻译两条腿（leg）的方向：
 * - [UPLINK]: 用户说出去（手机麦/耳机麦） → 翻译给对方
 * - [DOWNLINK]: 对方说过来（远端通话音） → 翻译给用户
 */
enum class CallTranslationLeg { UPLINK, DOWNLINK }

/** 通话翻译音频载荷的编码。 */
enum class CallAudioCodec { OPUS, PCM_S16LE }

/** 通话翻译协商时使用的音频格式描述。 */
data class CallAudioFormat(
    val codec: CallAudioCodec,
    val sampleRate: Int,
    val channels: Int,
    val frameMs: Int,
) {
    companion object {
        val OPUS_16K_MONO_20MS = CallAudioFormat(CallAudioCodec.OPUS, 16000, 1, 20)
        val PCM_S16LE_16K_MONO_20MS = CallAudioFormat(CallAudioCodec.PCM_S16LE, 16000, 1, 20)
    }
}

/** device → 编排器：一帧通话翻译音频。 */
data class CallAudioFrame(
    val leg: CallTranslationLeg,
    val codec: CallAudioCodec,
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
        if (other !is CallAudioFrame) return false
        return leg == other.leg && sequence == other.sequence && bytes.contentEquals(other.bytes)
    }
    override fun hashCode(): Int {
        var r = leg.hashCode()
        r = 31 * r + sequence.hashCode()
        r = 31 * r + bytes.contentHashCode()
        return r
    }
}

/** 编排器 → device：把已翻译的 TTS 音频回灌到指定 leg。
 *
 * @param isFinal 本帧是否为当前 utterance 的最后一帧。device 端可能据此决定是否触发整段编码 / 一次性下发
 *   （例如 jieli 通话翻译走 RCSP 时，需要按"一段 = 一个 AudioData"下发）。
 */
data class TranslatedAudioFrame(
    val leg: CallTranslationLeg,
    val codec: CallAudioCodec,
    val sampleRate: Int,
    val channels: Int,
    val bytes: ByteArray,
    val isFinal: Boolean = false,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TranslatedAudioFrame) return false
        return leg == other.leg && codec == other.codec && bytes.contentEquals(other.bytes)
    }
    override fun hashCode(): Int {
        var r = leg.hashCode()
        r = 31 * r + codec.hashCode()
        r = 31 * r + bytes.contentHashCode()
        return r
    }
}

/** 通话翻译过程中由 device 抛出的错误（不致命：编排器决定是否 stop）。 */
data class CallTranslationError(
    val code: String,
    val message: String,
)

/**
 * 通话翻译能力端口（device 侧）。
 *
 * 由设备厂商插件按需实现，例如杰理基于 RCSP `MODE_CALL_TRANSLATION` 落地一份
 * `JieliCallTranslationPort`。`translate_server` 编排器统一通过本接口拿音频帧、
 * 回灌 TTS，不依赖具体 vendor。
 *
 * 生命周期：
 * ```
 * idle → enter(format) → active → exit() → idle
 * ```
 *
 * 铁律：
 * - 同一设备同一时刻**至多一个** active 端口；重复 `enter` 抛
 *   `IllegalStateException("device.call_translation.busy")`；
 * - 协商格式（[enter] 入参）必须出自 [supportedSourceFormats] 列出的范围；
 * - [reportTranslated] 的 codec/sampleRate/channels 必须落在 [supportedSinkFormats] 内；
 * - [exit] 后 [audioFrames]/[errors] 仍可订阅，但不再产新事件。
 */
interface DeviceCallTranslationPort {
    /** 该端口能向上派发的音频源格式集合。 */
    fun supportedSourceFormats(): Set<CallAudioFormat>

    /** 该端口能接受的 TTS 回灌格式集合。 */
    fun supportedSinkFormats(): Set<CallAudioFormat>

    /**
     * 进入通话翻译模式。
     *
     * @param sourceFormat 协商好的源音频格式（必须 ∈ [supportedSourceFormats]）。
     * device 侧据此决定是否做 OPUS↔PCM 转换：例如耳机原生发 OPUS，agent 只吃
     * PCM 时编排器协商出 PCM，device 内部解码后再派发到 [audioFrames]。
     */
    fun enter(sourceFormat: CallAudioFormat)

    /**
     * 上行/下行音频帧。`enter` 之后开始派发，`exit` 后停止。
     * 必须是 broadcast / replayable 不变的实现，编排器多次订阅安全。
     */
    val audioFrames: Flow<CallAudioFrame>

    /**
     * 把已翻译的 TTS 音频回灌到指定 leg。
     *
     * @throws IllegalArgumentException codec 不在 [supportedSinkFormats] 内
     * @throws IllegalStateException 当前未在 active 状态
     */
    fun reportTranslated(frame: TranslatedAudioFrame)

    /** 退出通话翻译模式，归还设备 RCSP / 音频通道。 */
    fun exit()

    /** 错误流。**不致命**——编排器自行决定是否 [exit]。 */
    val errors: Flow<CallTranslationError>
}
