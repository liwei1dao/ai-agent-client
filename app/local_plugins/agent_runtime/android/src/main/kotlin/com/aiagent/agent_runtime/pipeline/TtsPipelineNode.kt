package com.aiagent.agent_runtime.pipeline

import com.aiagent.agent_runtime.*
import kotlinx.coroutines.CancellationException

/**
 * TtsPipelineNode — 调用 TTS 插件原生实现，推送 7 种 TTS 事件
 *
 * 打断机制：
 *   - AgentSession 在新输入到来时取消 activeJob，此时 speak() 挂起点被取消
 *   - 触发 playbackInterrupted 事件
 */
class TtsPipelineNode(
    private val sessionId: String,
    private val config: AgentSessionConfig,
    private val eventSink: AgentEventSink,
) {
    // TTS 插件实例通过插件注册表获取（此处用接口占位）
    // private lateinit var ttsPlugin: TtsPlugin

    suspend fun speak(requestId: String, text: String) {
        try {
            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "synthesisStart"))

            // TODO: 调用 TTS 插件合成
            // val audioData = ttsPlugin.synthesize(text)

            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "synthesisReady"))
            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "playbackStart"))

            // TODO: 播放音频，按帧推送 playbackProgress
            // audioPlayer.play(audioData) { progressMs, durationMs ->
            //     pushTtsEvent(TtsEventData(sessionId, requestId, "playbackProgress",
            //         progressMs = progressMs, durationMs = durationMs))
            // }

            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "playbackDone"))
        } catch (e: CancellationException) {
            pushTtsEvent(TtsEventData(sessionId, requestId, kind = "playbackInterrupted"))
            throw e  // 重新抛出，让协程正常取消
        } catch (e: Exception) {
            pushTtsEvent(
                TtsEventData(
                    sessionId, requestId, kind = "error",
                    errorCode = "tts_error", errorMessage = e.message,
                )
            )
        }
    }

    fun release() {
        // ttsPlugin.dispose()
    }

    private fun pushTtsEvent(event: TtsEventData) {
        eventSink.onTtsEvent(event)
    }
}
