package com.aiagent.agent_ast_translate

import android.content.Context
import android.util.Log
import com.aiagent.local_db.AppDatabase
import com.aiagent.local_db.entity.MessageEntity
import com.aiagent.plugin_interface.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * AstTranslateAgentSession — AST (端到端语音翻译) Agent 原生实现
 *
 * 使用 NativeAstService 通过 WebSocket / WebRTC 进行实时语音翻译。
 * 服务端完成 ASR → 翻译 → TTS 全流程，客户端只负责音频收发。
 *
 * 简化状态机：IDLE → CONNECTED → IDLE（与 StsChatAgentSession 相同模式）
 *
 * 桥接策略（AST 五件套 → STT/LLM 事件）：
 *   - recognizing(SOURCE)     → SttEventData(partialResult)
 *   - recognized(SOURCE)      → SttEventData(finalResult, requestId) + DB.user
 *   - recognizing(TRANSLATED) → LlmEventData(firstToken, textDelta, requestId)
 *   - recognized(TRANSLATED)  → LlmEventData(firstToken, textDelta, requestId)
 *   - recognitionEnd          → LlmEventData(done, fullText) + DB.assistant
 */
class AstTranslateAgentSession : NativeAgent {

    companion object {
        private const val TAG = "AstTranslateSession"
    }

    override val agentType = "ast"

    private enum class State { IDLE, CONNECTED, ERROR }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(State.IDLE)

    private lateinit var astService: NativeAstService
    private lateinit var db: AppDatabase
    private lateinit var eventSink: AgentEventSink
    private lateinit var config: NativeAgentConfig
    private lateinit var appContext: Context

    private var connectJob: Job? = null
    private var inputMode: String = "text"

    /** 当前轮次最后一段 translated 定稿文本 — recognitionEnd 时写入 done.fullText */
    @Volatile private var lastTranslatedText: String = ""
    @Volatile private var activeTranslationRequestId: String? = null

    // ─────────────────────────────────────────────────
    // NativeAgent 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(config: NativeAgentConfig, eventSink: AgentEventSink, context: Context) {
        this.config = config
        this.eventSink = eventSink
        this.inputMode = config.inputMode
        this.appContext = context.applicationContext
        this.db = AppDatabase.getInstance(context)

        astService = NativeServiceRegistry.createAst(config.astVendor ?: "volcengine")
        astService.initialize(config.astConfigJson ?: "{}", context)

        Log.d(TAG, "initialized: agentId=${config.agentId} astVendor=${config.astVendor}")
    }

    override fun connectService() {
        Log.d(TAG, "connectService: agentId=${config.agentId}")
        connectJob?.cancel()

        astService = NativeServiceRegistry.createAst(config.astVendor ?: "volcengine")
        astService.initialize(config.astConfigJson ?: "{}", appContext)

        connectJob = scope.launch {
            try {
                astService.connect(astCallback)
            } catch (e: CancellationException) {
                // normal cancellation
            } catch (e: Exception) {
                Log.e(TAG, "AST connect failed: ${e.message}")
                transitionTo(State.ERROR)
                eventSink.onError(config.agentId, "ast_connect_error", e.message ?: "Unknown error", null)
                eventSink.onAgentReady(
                    config.agentId, ready = false,
                    errorCode = "ast_connect_error",
                    errorMessage = e.message ?: "Unknown error",
                )
            }
        }
    }

    override fun disconnectService() {
        Log.d(TAG, "disconnectService: agentId=${config.agentId}")
        connectJob?.cancel()
        astService.release()
        transitionTo(State.IDLE)
        eventSink.onConnectionStateChanged(config.agentId, "disconnected")
    }

    override fun sendText(requestId: String, text: String) {
        Log.w(TAG, "sendText called but AST is voice-only, ignoring: $text")
    }

    override fun startListening() {
        Log.d(TAG, "startListening: delegating to startAudio")
        astService.startAudio()
    }

    override fun stopListening() {
        Log.d(TAG, "stopListening: delegating to stopAudio")
        astService.stopAudio()
    }

    override fun setInputMode(mode: String) {
        Log.d(TAG, "setInputMode: $mode")
        inputMode = mode
        when (mode) {
            // call 模式 = external audio：PCM 由 CallTranslationSession 通过
            // startExternalAudio + pushExternalAudioFrame 喂进来，**绝不能**在这里
            // 调 startAudio()，否则会进入 self-mic 模式与 external audio 互斥，
            // 后续 startExternalAudio 抛 "external audio cannot mix with self-mic"。
            "call" -> { /* no-op: 等 CallTranslationSession 调 startExternalAudio */ }
            "short_voice" -> { /* 按住说话，由 UI 调用 startListening/stopListening */ }
            else -> astService.stopAudio()
        }
    }

    override fun interrupt() {
        astService.interrupt()
        transitionTo(State.CONNECTED)
    }

    override fun release() {
        connectJob?.cancel()
        scope.cancel()
        astService.release()
    }

    // ─────────────────────────────────────────────────
    // 外部音频源（通话翻译等场景）—— 透传到底层 NativeAstService
    // ─────────────────────────────────────────────────

    override fun externalAudioCapability(): ExternalAudioCapability =
        astService.externalAudioCapability()

    override fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        astService.startExternalAudio(format, sink)
    }

    override fun pushExternalAudioFrame(frame: ByteArray) {
        astService.pushExternalAudioFrame(frame)
    }

    override fun stopExternalAudio() {
        astService.stopExternalAudio()
    }

    // ─────────────────────────────────────────────────
    // AST 回调 → AgentEventSink 事件转换
    // ─────────────────────────────────────────────────

    private val astCallback = object : AstCallback {
        override fun onConnected() {
            transitionTo(State.CONNECTED)
            eventSink.onConnectionStateChanged(config.agentId, "connected")
            eventSink.onAgentReady(config.agentId, ready = true)
            Log.d(TAG, "AST connected, inputMode=$inputMode")
            // call 模式下 CallTranslationSession 会随后调 startExternalAudio 把
            // 耳机解码出来的 PCM 喂进来，这里不要触发 self-mic 路径。
        }

        override fun onDisconnected() {
            transitionTo(State.IDLE)
            eventSink.onConnectionStateChanged(config.agentId, "disconnected")
            Log.d(TAG, "AST disconnected")
        }

        override fun onRecognitionStart(role: AstRole, requestId: String) {
            // No-op — chat provider lazily creates the message on the first
            // partial / firstToken event.
        }

        override fun onRecognizing(role: AstRole, requestId: String, text: String) {
            when (role) {
                AstRole.SOURCE -> {
                    eventSink.onSttEvent(SttEventData(
                        config.agentId,
                        requestId = "",
                        kind = "partialResult",
                        text = text,
                    ))
                }
                AstRole.TRANSLATED -> {
                    activeTranslationRequestId = requestId
                    lastTranslatedText = text
                    eventSink.onLlmEvent(LlmEventData(
                        config.agentId,
                        requestId = requestId,
                        kind = "firstToken",
                        textDelta = text,
                    ))
                }
            }
        }

        override fun onRecognized(role: AstRole, requestId: String, text: String) {
            when (role) {
                AstRole.SOURCE -> {
                    eventSink.onSttEvent(SttEventData(
                        config.agentId,
                        requestId = requestId,
                        kind = "finalResult",
                        text = text,
                    ))
                    persistMessage(requestId, role = "user", content = text)
                }
                AstRole.TRANSLATED -> {
                    activeTranslationRequestId = requestId
                    lastTranslatedText = text
                    eventSink.onLlmEvent(LlmEventData(
                        config.agentId,
                        requestId = requestId,
                        kind = "firstToken",
                        textDelta = text,
                    ))
                }
            }
        }

        override fun onRecognitionDone(role: AstRole, requestId: String) {
            // No-op — round-level closure is signalled by recognitionEnd.
        }

        override fun onRecognitionEnd(requestId: String) {
            val transId = activeTranslationRequestId
            val transText = lastTranslatedText
            if (transId != null && transText.isNotBlank()) {
                eventSink.onLlmEvent(LlmEventData(
                    config.agentId,
                    requestId = transId,
                    kind = "done",
                    fullText = transText,
                ))
                persistMessage(transId, role = "assistant", content = transText)
            }
            activeTranslationRequestId = null
            lastTranslatedText = ""
        }

        override fun onRecognitionError(requestId: String?, role: AstRole?, code: String, message: String) {
            eventSink.onError(config.agentId, code, message, requestId)
        }

        override fun onError(code: String, message: String) {
            transitionTo(State.ERROR)
            eventSink.onConnectionStateChanged(config.agentId, "error", message)
            eventSink.onError(config.agentId, code, message, null)
            eventSink.onAgentReady(config.agentId, ready = false, errorCode = code, errorMessage = message)
        }
    }

    // ─────────────────────────────────────────────────
    // 内部方法
    // ─────────────────────────────────────────────────

    private fun persistMessage(id: String, role: String, content: String) {
        scope.launch {
            runCatching {
                val now = System.currentTimeMillis()
                db.messageDao().insert(MessageEntity(
                    id = id,
                    agentId = config.agentId,
                    role = role,
                    content = content,
                    status = "done",
                    createdAt = now,
                    updatedAt = now,
                ))
            }
        }
    }

    private fun transitionTo(newState: State) {
        _state.value = newState
        eventSink.onStateChanged(
            config.agentId,
            newState.name.lowercase(),
            null,
        )
    }
}
