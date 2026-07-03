package com.aiagent.plugin_interface

import android.content.Context

/**
 * TTS（语音合成）服务原生接口
 *
 * 实现方：tts_azure 等服务插件
 * 使用方：agent_chat, agent_translate 等 Agent 类型插件
 *
 * 职责：文本合成 + 音频播放 + 打断控制
 *
 * 双步设计（流水线）：
 *   - synthesize(text) → TtsAudio：仅做文本→音频字节
 *   - play(audio)：仅做音频字节→扬声器
 *   - speak(text)：兼容老用法，等价于 synthesize then play（一段语义文本）
 *
 * 上层调度方应使用 synthesize + play 两步，做"边合成边播放"的流水线，
 * 避免出现"播放完一段后才开始合成下一段"的空白延迟。
 *
 * **强约束**：新增 TTS 厂商实现**必须**支持外部音频 sink（参见下方"外部音频源"小节），
 * 否则将无法用于通话翻译 / 面对面翻译等需要把 TTS PCM 回灌到耳机的复合场景。默认实现
 * 抛 UnsupportedOperationException 仅作为编译兜底，运行期触达即视为接口未实现完整。
 */
interface NativeTtsService {

    /**
     * 初始化 TTS 服务
     * @param configJson  服务配置 JSON（apiKey, region, voiceName 等）
     * @param context     Android Context
     */
    fun initialize(configJson: String, context: Context)

    /**
     * 仅合成（不播放）。
     *
     * 该方法**必须**支持并发调用——上层为做合成节流（≤2 并发）会同时发起多段合成。
     * 协程被取消时立即终止网络请求（OkHttp call.cancel）。
     */
    suspend fun synthesize(requestId: String, text: String): TtsAudio

    /**
     * 仅播放已合成的音频。
     *
     * 串行调用：调用方保证同一时刻只播放一段。
     * 协程返回时表示播放完成或被打断；中途事件通过 callback 推送。
     */
    suspend fun play(requestId: String, audio: TtsAudio, callback: TtsCallback)

    /**
     * 一站式：合成 + 播放（兼容旧用法）。
     *
     * 默认实现 = synthesize + play，事件按 §4.1 顺序闭合。
     * 单段场景（服务测试 / 翻译整段播报）可继续使用此方法。
     */
    suspend fun speak(requestId: String, text: String, callback: TtsCallback) {
        if (text.isBlank()) return
        try {
            callback.onSynthesisStart()
            val audio = synthesize(requestId, text)
            callback.onSynthesisReady(audio.durationMs ?: 0)
            callback.onPlaybackStart()
            play(requestId, audio, callback)
            callback.onPlaybackDone()
        } catch (e: kotlinx.coroutines.CancellationException) {
            callback.onPlaybackInterrupted()
            throw e
        } catch (e: Exception) {
            callback.onError("tts_error", e.message ?: "Unknown error")
        }
    }

    /** 停止当前播放（触发 playbackInterrupted）；同时取消所有正在进行的合成请求 */
    fun stop()

    /** 释放资源 */
    fun release()

    // ── 外部音频源 ──────────────────────────────────────────────────
    //
    // 与本地扬声器播放互斥。通话翻译场景：调用方先协商输出格式，再启动外部模式
    // （绑定 sink），后续 [play] 不再走 AudioTrack/MediaPlayer，而是把合成出来的
    // PCM 帧通过 [ExternalAudioSink.onTtsFrame] 回写给调用方（编排器再灌回耳机）。

    fun externalAudioCapability(): ExternalAudioCapability =
        ExternalAudioCapability.UNSUPPORTED

    /**
     * 启动外部音频输出模式。
     *
     * @param format 协商好的输出格式（必须落在 [externalAudioCapability] 内）
     * @param sink   PCM 帧回写通道；本服务在此模式下会把 [play] 的音频字节切帧后写入 sink
     * @throws UnsupportedOperationException 默认不支持。
     */
    fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        throw UnsupportedOperationException(
            "tts service ${this::class.simpleName} does not support external audio sink"
        )
    }

    /** 停止外部音频输出模式（恢复本地扬声器）。 */
    fun stopExternalAudio() {}
}

/**
 * 已合成的音频数据。
 *
 * @param data        音频字节（mp3 / pcm / opus 等，由 [format] 指定）
 * @param format      音频容器格式："mp3" / "pcm16" / "opus" 等；播放方据此选择解码路径
 * @param durationMs  音频实际时长（毫秒）；不可知时为 null（不要用 0 冒充）
 */
data class TtsAudio(
    val data: ByteArray,
    val format: String,
    val durationMs: Int? = null,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is TtsAudio) return false
        return data.contentEquals(other.data) && format == other.format && durationMs == other.durationMs
    }

    override fun hashCode(): Int {
        var result = data.contentHashCode()
        result = 31 * result + format.hashCode()
        result = 31 * result + (durationMs ?: 0)
        return result
    }
}

/**
 * TTS 事件回调
 */
interface TtsCallback {
    /** 合成请求已发出 */
    fun onSynthesisStart()

    /** 合成完成，音频数据就绪 */
    fun onSynthesisReady(durationMs: Int)

    /** 开始播放 */
    fun onPlaybackStart()

    /** 播放进度 */
    fun onPlaybackProgress(progressMs: Int)

    /** 播放完成 */
    fun onPlaybackDone()

    /** 播放被打断 */
    fun onPlaybackInterrupted()

    /** 错误 */
    fun onError(code: String, message: String)
}
