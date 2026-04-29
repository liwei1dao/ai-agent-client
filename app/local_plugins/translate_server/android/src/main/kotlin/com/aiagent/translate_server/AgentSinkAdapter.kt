package com.aiagent.translate_server

import com.aiagent.plugin_interface.AgentEventSink
import com.aiagent.plugin_interface.LlmEventData
import com.aiagent.plugin_interface.SttEventData
import com.aiagent.plugin_interface.TtsEventData
import kotlinx.coroutines.CompletableDeferred

/**
 * 把翻译型 agent 的 [AgentEventSink] 事件转译成通话翻译统一的字幕/状态/错误事件。
 *
 * AST agent 的桥接策略（与 [AstTranslateAgentSession] 一致）：
 *  - SttEventData(partialResult)  → SubtitleStage.partial , sourceText 覆盖
 *  - SttEventData(finalResult)    → SubtitleStage.final   , sourceText 定稿
 *  - LlmEventData(firstToken)     → translatedText 覆盖（partial 阶段）
 *  - LlmEventData(done)           → translatedText 定稿（final 阶段）
 *
 * 三段式 translate agent 走同样语义。
 */
internal class AgentSinkAdapter(
    private val sessionId: String,
    private val leg: CallLeg,
    private val emit: (Map<String, Any?>) -> Unit,
    /** 第一次 onAgentReady 时 complete（成功）或 completeExceptionally（失败），编排器据此等待就绪。 */
    val connected: CompletableDeferred<Unit> = CompletableDeferred(),
) : AgentEventSink {

    /** 当前一句的源文 / 译文累积（partial 阶段覆盖；final 阶段提交后清空）。 */
    @Volatile private var currentSource: String = ""
    @Volatile private var currentTranslated: String? = null

    override fun onSttEvent(event: SttEventData) {
        when (event.kind) {
            "partialResult" -> {
                currentSource = event.text ?: ""
                emitSubtitle(stage = "partial", requestId = event.requestId.takeIf { it.isNotBlank() })
            }
            "finalResult" -> {
                currentSource = event.text ?: currentSource
                emitSubtitle(stage = "final", requestId = event.requestId.takeIf { it.isNotBlank() })
                currentSource = ""
                currentTranslated = null
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
                currentTranslated = event.textDelta ?: currentTranslated
                emitSubtitle(stage = "partial", requestId = event.requestId.takeIf { it.isNotBlank() })
            }
            "done" -> {
                currentTranslated = event.fullText ?: event.textDelta ?: currentTranslated
                emitSubtitle(stage = "final", requestId = event.requestId.takeIf { it.isNotBlank() })
                // final 后清场由 onSttEvent.finalResult 触发——这里不动，避免和 STT 端 race。
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

    private fun emitSubtitle(stage: String, requestId: String?) {
        emit(TranslateEvents.subtitle(
            sessionId = sessionId,
            leg = leg.wireName,
            stage = stage,
            sourceText = currentSource,
            translatedText = currentTranslated,
            requestId = requestId,
        ))
    }
}
