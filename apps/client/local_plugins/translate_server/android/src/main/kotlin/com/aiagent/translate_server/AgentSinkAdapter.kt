package com.aiagent.translate_server

import com.aiagent.plugin_interface.AgentEventSink
import com.aiagent.plugin_interface.LlmEventData
import com.aiagent.plugin_interface.SttEventData
import com.aiagent.plugin_interface.TtsEventData
import kotlinx.coroutines.CompletableDeferred

/**
 * 把翻译型 agent 的 [AgentEventSink] 事件转译成通话翻译统一的字幕/状态/错误事件。
 *
 * 配对策略（按 [requestId]）：
 *  - 每条 STT finalResult / LLM done 事件携带 `requestId`，UI 端按 `requestId`
 *    把 source 和 translated 配对到同一行字幕，**不依赖到达顺序**。
 *  - SttEventData(partialResult) → stage=partial, sourceText, requestId=null（未定稿）
 *  - SttEventData(finalResult)   → stage=final,   sourceText, translatedText=null
 *  - LlmEventData(firstToken)    → stage=partial, translatedText, requestId（更新对应行的译文 partial）
 *  - LlmEventData(done)          → stage=final,   translatedText（更新对应行的译文 final）
 *
 * 这样：连续多句翻译时，UI 不会把旧句的译文错位到新句的源文下。
 */
internal class AgentSinkAdapter(
    private val sessionId: String,
    private val leg: CallLeg,
    private val emit: (Map<String, Any?>) -> Unit,
    /** 第一次 onAgentReady 时 complete（成功）或 completeExceptionally（失败），编排器据此等待就绪。 */
    val connected: CompletableDeferred<Unit> = CompletableDeferred(),
) : AgentEventSink {

    override fun onSttEvent(event: SttEventData) {
        when (event.kind) {
            "partialResult" -> {
                // 进行中的源文（无 requestId），UI 显示 in-progress 当前句的源文。
                emit(TranslateEvents.subtitle(
                    sessionId = sessionId,
                    leg = leg.wireName,
                    stage = "partial",
                    sourceText = event.text ?: "",
                    translatedText = null,
                    requestId = null,
                ))
            }
            "finalResult" -> {
                // 一句源文定稿，按 requestId 钉到 UI 端。译文留 null，由后续 LLM done 补。
                val reqId = event.requestId.takeIf { it.isNotBlank() } ?: return
                emit(TranslateEvents.subtitle(
                    sessionId = sessionId,
                    leg = leg.wireName,
                    stage = "final",
                    sourceText = event.text ?: "",
                    translatedText = null,
                    requestId = reqId,
                ))
            }
            "error" -> emit(TranslateEvents.error(
                sessionId = sessionId,
                code = event.errorCode ?: "stt.error",
                message = event.errorMessage ?: "stt error",
                leg = leg.wireName,
            ))
            // listeningStarted / listeningStopped / vadSpeechStart/end 此处不用透传
        }
    }

    override fun onLlmEvent(event: LlmEventData) {
        when (event.kind) {
            "firstToken" -> {
                val reqId = event.requestId.takeIf { it.isNotBlank() } ?: return
                emit(TranslateEvents.subtitle(
                    sessionId = sessionId,
                    leg = leg.wireName,
                    stage = "partial",
                    sourceText = "",            // 源文已在 STT final 时定稿；这里不复发
                    translatedText = event.textDelta ?: "",
                    requestId = reqId,
                ))
            }
            "done" -> {
                val reqId = event.requestId.takeIf { it.isNotBlank() } ?: return
                emit(TranslateEvents.subtitle(
                    sessionId = sessionId,
                    leg = leg.wireName,
                    stage = "final",
                    sourceText = "",
                    translatedText = event.fullText ?: event.textDelta ?: "",
                    requestId = reqId,
                ))
            }
            "error" -> emit(TranslateEvents.error(
                sessionId = sessionId,
                code = event.errorCode ?: "llm.error",
                message = event.errorMessage ?: "llm error",
                leg = leg.wireName,
            ))
        }
    }

    override fun onTtsEvent(event: TtsEventData) {
        // TTS 字节通过 ExternalAudioSink 拿，不走这里。事件里只关心 error。
        if (event.kind == "error") {
            emit(TranslateEvents.error(
                sessionId = sessionId,
                code = event.errorCode ?: "tts.error",
                message = event.errorMessage ?: "tts error",
                leg = leg.wireName,
            ))
        }
    }

    override fun onStateChanged(sessionId: String, state: String, requestId: String?) {
        // agent 内部状态机：idle/connected/listening/processing... 通话翻译不消费。
    }

    override fun onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        emit(TranslateEvents.error(
            sessionId = this.sessionId,
            code = errorCode,
            message = message,
            leg = leg.wireName,
        ))
    }

    override fun onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?) {
        emit(TranslateEvents.connectionState(
            sessionId = this.sessionId,
            leg = leg.wireName,
            state = state,
            errorMessage = errorMessage,
        ))
        // 注意：就绪/失败信号统一走 onAgentReady；这里只负责把状态向上 emit 给 Flutter。
    }

    override fun onAgentReady(sessionId: String, ready: Boolean, errorCode: String?, errorMessage: String?) {
        if (ready) {
            if (!connected.isCompleted) connected.complete(Unit)
        } else {
            if (!connected.isCompleted) {
                connected.completeExceptionally(
                    IllegalStateException(
                        "agent ${leg.wireName} ready failed: ${errorCode ?: "unknown"} ${errorMessage ?: ""}"
                    )
                )
            }
            emit(TranslateEvents.error(
                sessionId = this.sessionId,
                code = errorCode ?: "agent.ready_failed",
                message = errorMessage ?: "agent ready failed",
                leg = leg.wireName,
                fatal = true,
            ))
        }
    }

}
