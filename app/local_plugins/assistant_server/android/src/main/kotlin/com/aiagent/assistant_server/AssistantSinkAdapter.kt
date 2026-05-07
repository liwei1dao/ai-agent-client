package com.aiagent.assistant_server

import com.aiagent.plugin_interface.AgentEventSink
import com.aiagent.plugin_interface.LlmEventData
import com.aiagent.plugin_interface.SttEventData
import com.aiagent.plugin_interface.TtsEventData
import kotlinx.coroutines.CompletableDeferred

/**
 * 把单 chat agent 的 [AgentEventSink] 事件转译成 AI 助理统一的对话/状态/错误事件。
 *
 * 事件映射（按 [requestId] 配对一行对话：用户问 + AI 答）：
 *  - SttEventData(partialResult) → message(role=user, stage=partial, text, requestId=null)
 *  - SttEventData(finalResult)   → message(role=user, stage=final,   text, requestId)
 *  - LlmEventData(firstToken)    → message(role=assistant, stage=partial, text=delta, requestId)
 *  - LlmEventData(done)          → message(role=assistant, stage=final,   text=fullText, requestId)
 *
 * 这样 UI 可按 requestId 把"用户语音 → AI 回复"配成一对气泡，不依赖事件到达顺序。
 */
internal class AssistantSinkAdapter(
    private val sessionId: String,
    private val emit: (Map<String, Any?>) -> Unit,
    /** 第一次 onAgentReady 时 complete（成功）或 completeExceptionally（失败），编排器据此等待就绪。 */
    val connected: CompletableDeferred<Unit> = CompletableDeferred(),
) : AgentEventSink {

    override fun onSttEvent(event: SttEventData) {
        when (event.kind) {
            "partialResult" -> {
                emit(AssistantEvents.message(
                    sessionId = sessionId,
                    role = AssistantRole.USER.wireName,
                    stage = "partial",
                    text = event.text ?: "",
                    requestId = null,
                ))
            }
            "finalResult" -> {
                val reqId = event.requestId.takeIf { it.isNotBlank() } ?: return
                emit(AssistantEvents.message(
                    sessionId = sessionId,
                    role = AssistantRole.USER.wireName,
                    stage = "final",
                    text = event.text ?: "",
                    requestId = reqId,
                ))
            }
            "error" -> emit(AssistantEvents.error(
                sessionId = sessionId,
                code = event.errorCode ?: "stt.error",
                message = event.errorMessage ?: "stt error",
                role = AssistantRole.USER.wireName,
            ))
        }
    }

    override fun onLlmEvent(event: LlmEventData) {
        when (event.kind) {
            "firstToken" -> {
                val reqId = event.requestId.takeIf { it.isNotBlank() } ?: return
                emit(AssistantEvents.message(
                    sessionId = sessionId,
                    role = AssistantRole.ASSISTANT.wireName,
                    stage = "partial",
                    text = event.textDelta ?: "",
                    requestId = reqId,
                ))
            }
            "done" -> {
                val reqId = event.requestId.takeIf { it.isNotBlank() } ?: return
                emit(AssistantEvents.message(
                    sessionId = sessionId,
                    role = AssistantRole.ASSISTANT.wireName,
                    stage = "final",
                    text = event.fullText ?: event.textDelta ?: "",
                    requestId = reqId,
                ))
            }
            "error" -> emit(AssistantEvents.error(
                sessionId = sessionId,
                code = event.errorCode ?: "llm.error",
                message = event.errorMessage ?: "llm error",
                role = AssistantRole.ASSISTANT.wireName,
            ))
        }
    }

    override fun onTtsEvent(event: TtsEventData) {
        // TTS 字节通过 ExternalAudioSink 拿，不走这里。事件里只关心 error。
        if (event.kind == "error") {
            emit(AssistantEvents.error(
                sessionId = sessionId,
                code = event.errorCode ?: "tts.error",
                message = event.errorMessage ?: "tts error",
                role = AssistantRole.ASSISTANT.wireName,
            ))
        }
    }

    override fun onStateChanged(sessionId: String, state: String, requestId: String?) {
        // agent 内部状态机：idle/listening/processing... 不向 UI 透传。
    }

    override fun onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        emit(AssistantEvents.error(
            sessionId = this.sessionId,
            code = errorCode,
            message = message,
        ))
    }

    override fun onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?) {
        emit(AssistantEvents.connectionState(
            sessionId = this.sessionId,
            state = state,
            errorMessage = errorMessage,
        ))
    }

    override fun onAgentReady(sessionId: String, ready: Boolean, errorCode: String?, errorMessage: String?) {
        if (ready) {
            if (!connected.isCompleted) connected.complete(Unit)
        } else {
            if (!connected.isCompleted) {
                connected.completeExceptionally(
                    IllegalStateException(
                        "assistant agent ready failed: ${errorCode ?: "unknown"} ${errorMessage ?: ""}"
                    )
                )
            }
            emit(AssistantEvents.error(
                sessionId = this.sessionId,
                code = errorCode ?: "agent.ready_failed",
                message = errorMessage ?: "agent ready failed",
                fatal = true,
            ))
        }
    }
}
