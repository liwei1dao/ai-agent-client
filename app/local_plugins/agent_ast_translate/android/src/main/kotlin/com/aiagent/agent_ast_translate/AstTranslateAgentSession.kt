package com.aiagent.agent_ast_translate

import android.content.Context
import android.util.Log
import com.aiagent.local_db.AppDatabase
import com.aiagent.local_db.entity.MessageEntity
import com.aiagent.plugin_interface.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.UUID

/**
 * AstTranslateAgentSession — AST (端到端语音翻译) Agent 原生实现
 *
 * 使用 NativeAstService 通过 WebSocket 进行实时语音翻译。
 * 服务端完成 ASR → 翻译 → TTS 全流程，客户端只负责音频收发。
 *
 * 简化状态机：IDLE → CONNECTED → IDLE（与 StsChatAgentSession 相同模式）
 *
 * 生命周期：
 *   initialize → connect(WebSocket) → setInputMode("call") → startAudio
 *   → [实时双向音频流] → setInputMode("text") → stopAudio → release
 *
 * 从 AgentSession.kt 的 isAstAgent 分支提取。
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

    private var connectJob: Job? = null
    private var inputMode: String = "text"

    /** 暂存最新源语言字幕文本，等 onSpeechStart 时再作为 finalResult 发出 */
    @Volatile private var pendingSourceText: String = ""

    // ─────────────────────────────────────────────────
    // NativeAgent 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(config: NativeAgentConfig, eventSink: AgentEventSink, context: Context) {
        this.config = config
        this.eventSink = eventSink
        this.inputMode = config.inputMode
        this.db = AppDatabase.getInstance(context)

        // Create AST service from NativeServiceRegistry
        astService = NativeServiceRegistry.createAst(config.astVendor ?: "volcengine")

        // Initialize AST service with config
        astService.initialize(config.astConfigJson ?: "{}", context)

        Log.d(TAG, "initialized: agentId=${config.agentId} astVendor=${config.astVendor}")

        // 进入聊天界面时自动建立 WebSocket 连接，不启动麦克风
        connectJob = scope.launch {
            try {
                astService.connect(astCallback)
            } catch (e: CancellationException) {
                // normal cancellation
            } catch (e: Exception) {
                Log.e(TAG, "AST connect failed: ${e.message}")
                transitionTo(State.ERROR)
                eventSink.onError(config.agentId, "ast_connect_error", e.message ?: "Unknown error", null)
            }
        }
    }

    override fun sendText(requestId: String, text: String) {
        // AST 是纯语音翻译模式，不支持文本输入
        Log.w(TAG, "sendText called but AST is voice-only, ignoring: $text")
    }

    override fun startListening() {
        // AST 模式不使用独立的 STT 监听，音频通过 WebSocket 直接发送
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
            "call" -> {
                // 开始发送麦克风音频，WebSocket 已在 init 时建立
                astService.startAudio()
            }
            "short_voice" -> { /* 按住说话，由 UI 调用 startListening/stopListening */ }
            else -> {
                // 停止发送麦克风音频，WebSocket 保持连接
                astService.stopAudio()
            }
        }
    }

    override fun interrupt() {
        // AST 模式：仅清空 TTS 播放缓冲，WebSocket 保持连接
        astService.interrupt()
        transitionTo(State.CONNECTED)
    }

    override fun release() {
        connectJob?.cancel()
        scope.cancel()
        astService.release()
    }

    // ─────────────────────────────────────────────────
    // AST 回调 → AgentEventSink 事件转换
    // ─────────────────────────────────────────────────

    private val astCallback = object : AstCallback {
        override fun onConnected() {
            transitionTo(State.CONNECTED)
            Log.d(TAG, "WebSocket connected, inputMode=$inputMode")
            // 如果用户已切换到 call 模式但连接还没好，现在自动启动音频
            if (inputMode == "call") {
                astService.startAudio()
            }
        }

        override fun onSourceSubtitle(text: String) {
            // 源语言字幕（可能是部分识别）→ 暂存，发 partialResult 供 UI 实时预览
            pendingSourceText = text
            eventSink.onSttEvent(SttEventData(
                config.agentId, requestId = "", kind = "partialResult", text = text))
        }

        override fun onTranslatedSubtitle(text: String) {
            // 翻译后字幕 → 先发 firstToken 让 UI 创建气泡，再发 done 完成
            val reqId = UUID.randomUUID().toString()
            eventSink.onLlmEvent(LlmEventData(
                config.agentId, requestId = reqId, kind = "firstToken", textDelta = text))
            eventSink.onLlmEvent(LlmEventData(
                config.agentId, requestId = reqId, kind = "done", fullText = text))

            // 写入助手消息到 DB
            scope.launch {
                runCatching {
                    val now = System.currentTimeMillis()
                    db.messageDao().insert(MessageEntity(
                        id = reqId,
                        agentId = config.agentId,
                        role = "assistant",
                        content = text,
                        status = "done",
                        createdAt = now,
                        updatedAt = now,
                    ))
                }
            }
        }

        override fun onTtsAudioChunk(pcmData: ByteArray) {
            // TTS 音频数据由 AST 服务内部播放，此处不需要额外处理
        }

        override fun onDisconnected() {
            transitionTo(State.IDLE)
            Log.d(TAG, "WebSocket disconnected")
        }

        override fun onError(code: String, message: String) {
            transitionTo(State.ERROR)
            eventSink.onError(config.agentId, code, message, null)
        }

        override fun onSpeechStart() {
            // 用户一句话说完 → 将暂存的源语言文本作为 finalResult 发出
            val text = pendingSourceText
            pendingSourceText = ""
            if (text.isNotBlank()) {
                val reqId = UUID.randomUUID().toString()
                eventSink.onSttEvent(SttEventData(
                    config.agentId, requestId = reqId, kind = "finalResult", text = text))
                // 写入用户消息到 DB
                scope.launch {
                    runCatching {
                        val now = System.currentTimeMillis()
                        db.messageDao().insert(MessageEntity(
                            id = reqId,
                            agentId = config.agentId,
                            role = "user",
                            content = text,
                            status = "done",
                            createdAt = now,
                            updatedAt = now,
                        ))
                    }
                }
            }
        }

        override fun onStateChanged(state: String) {
            eventSink.onStateChanged(config.agentId, state, null)
        }
    }

    // ─────────────────────────────────────────────────
    // 内部方法
    // ─────────────────────────────────────────────────

    private fun transitionTo(newState: State) {
        _state.value = newState
        eventSink.onStateChanged(
            config.agentId,
            newState.name.lowercase(),
            null,
        )
    }
}
