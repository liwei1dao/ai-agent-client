package com.aiagent.agent_runtime.pipeline

import com.aiagent.agent_runtime.*
import com.aiagent.local_db.AppDatabase
import java.util.UUID

/**
 * SttPipelineNode — 调用 STT 插件，推送 7 种 STT 事件
 *
 * 短语音 / 通话模式：
 *   - 在收到 isFinal=true 的识别结果时，由本节点生成 requestId（UUID）
 *   - 生成后立即回调 onFinalResult(requestId, text)，触发 AgentSession.onUserInput
 *
 * 文本模式不经过此节点。
 */
class SttPipelineNode(
    private val sessionId: String,
    private val config: AgentSessionConfig,
    private val db: AppDatabase,
    private val eventSink: AgentEventSink,
    private val onFinalResult: (requestId: String, text: String) -> Unit,
) {
    // STT 插件实例通过插件注册表获取（此处用接口占位）
    private var isListening = false

    suspend fun startListening() {
        isListening = true
        pushEvent(SttEventData(sessionId, requestId = "", kind = "listeningStarted"))
        // TODO: 启动注册的 STT 插件原生实现
        // sttPlugin.startListening()
        // 事件处理见 onSttRawEvent()
    }

    suspend fun stopListening() {
        isListening = false
        // sttPlugin.stopListening()
        pushEvent(SttEventData(sessionId, requestId = "", kind = "listeningStopped"))
    }

    /**
     * STT 插件回调（在原生 SDK 回调线程调用）
     * 此方法由 STT 插件实现调用。
     */
    fun onSttRawEvent(kind: String, text: String?, isFinal: Boolean) {
        when (kind) {
            "vadSpeechStart" -> {
                pushEvent(SttEventData(sessionId, requestId = "", kind = "vadSpeechStart"))
            }
            "vadSpeechEnd" -> {
                pushEvent(SttEventData(sessionId, requestId = "", kind = "vadSpeechEnd"))
            }
            "partial" -> {
                pushEvent(
                    SttEventData(
                        sessionId, requestId = "",
                        kind = "partialResult", text = text,
                    )
                )
            }
            "final" -> {
                if (text.isNullOrBlank()) return
                // ★ 短语音/通话模式：由原生 STT 层生成 requestId
                val requestId = UUID.randomUUID().toString()
                pushEvent(
                    SttEventData(
                        sessionId, requestId = requestId,
                        kind = "finalResult", text = text,
                    )
                )
                // 触发 AgentSession 开始 LLM 管线
                onFinalResult(requestId, text)
            }
            "error" -> {
                pushEvent(
                    SttEventData(
                        sessionId, requestId = "",
                        kind = "error",
                        errorCode = "stt_error", errorMessage = text,
                    )
                )
            }
        }
    }

    fun release() {
        isListening = false
    }

    private fun pushEvent(event: SttEventData) {
        eventSink.onSttEvent(event)
    }
}
