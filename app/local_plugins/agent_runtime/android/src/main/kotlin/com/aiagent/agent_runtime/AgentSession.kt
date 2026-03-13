package com.aiagent.agent_runtime

import com.aiagent.local_db.AppDatabase
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID

/**
 * AgentSession — 单个 Agent 会话状态机
 *
 * 状态流转：
 *   IDLE → LISTENING → STT → LLM → TTS/PLAYING → IDLE
 *
 * 打断机制（"latest wins"）：
 *   - activeRequestId 保存当前正在处理的请求 UUID
 *   - 新输入到来时：cancel activeJob → 更新 activeRequestId → 开始新管线
 *   - LlmPipelineNode 每次写入 DB / 推送事件前检查 requestId 是否仍匹配
 */
class AgentSession(
    val sessionId: String,
    private val config: AgentSessionConfig,
    private val db: AppDatabase,
    private val eventSink: AgentEventSink,
) {
    enum class State { IDLE, LISTENING, STT, LLM, TTS, PLAYING, ERROR }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _state = MutableStateFlow(State.IDLE)
    val state: StateFlow<State> = _state

    /** 当前活跃 requestId；新输入覆盖旧值实现打断 */
    @Volatile
    var activeRequestId: String? = null
        private set

    private var activeJob: Job? = null

    // Pipeline 节点（懒加载，依赖插件注册）
    private val vadEngine = VadEngine(sessionId, eventSink)
    private val sttNode = SttPipelineNode(sessionId, config, db, eventSink) { reqId ->
        // STT 产出 finalResult 时回调，触发 LLM 管线
        onUserInput(reqId, it)
    }
    private val llmNode = LlmPipelineNode(sessionId, config, db, eventSink)
    private val ttsNode = TtsPipelineNode(sessionId, config, eventSink)

    // ─────────────────────────────────────────────────
    // 公开命令
    // ─────────────────────────────────────────────────

    /** 文本模式：Flutter 已生成 requestId */
    fun sendText(requestId: String, text: String) {
        onUserInput(requestId, text)
    }

    /** 打断当前处理，恢复 IDLE */
    fun interrupt() {
        cancelActiveJob(reason = "manual_interrupt")
        transitionTo(State.IDLE)
    }

    /** 切换输入模式 */
    fun setInputMode(mode: String) {
        when (mode) {
            "call" -> startContinuousListening()
            "short_voice" -> { /* 按住说话，由 UI 调用 startListening/stopListening */ }
            else -> stopListening()
        }
    }

    /** 开始监听（短语音模式，用户按住按钮时调用） */
    fun startListening() {
        transitionTo(State.LISTENING)
        scope.launch { sttNode.startListening() }
    }

    /** 停止监听（用户松手时调用） */
    fun stopListening() {
        scope.launch { sttNode.stopListening() }
    }

    fun release() {
        scope.cancel()
        vadEngine.release()
        sttNode.release()
        ttsNode.release()
    }

    // ─────────────────────────────────────────────────
    // 内部：用户输入触发 LLM 管线
    // ─────────────────────────────────────────────────

    /**
     * 核心：新用户输入到来
     * 1. 取消旧 Job（打断旧 LLM/TTS）
     * 2. 更新 activeRequestId
     * 3. 将旧消息标记为 cancelled（DB）
     * 4. 写入用户消息到 DB
     * 5. 启动新 LLM→TTS 管线
     */
    internal fun onUserInput(requestId: String, text: String) {
        val previousId = activeRequestId
        cancelActiveJob(reason = "new_input")

        activeRequestId = requestId

        activeJob = scope.launch {
            // 标记上一个未完成的 assistant 消息为 cancelled
            if (previousId != null) {
                db.messageDao().updateStatus(previousId, "cancelled", System.currentTimeMillis())
            }

            // 写入用户消息
            val now = System.currentTimeMillis()
            db.messageDao().insert(
                com.aiagent.local_db.entity.MessageEntity(
                    id = requestId,
                    agentId = config.agentId,
                    role = "user",
                    content = text,
                    status = "done",
                    createdAt = now,
                    updatedAt = now,
                )
            )

            // 写入占位 assistant 消息
            val assistantId = UUID.randomUUID().toString()
            db.messageDao().insert(
                com.aiagent.local_db.entity.MessageEntity(
                    id = assistantId,
                    agentId = config.agentId,
                    role = "assistant",
                    content = "",
                    status = "pending",
                    createdAt = now + 1,
                    updatedAt = now + 1,
                )
            )

            // LLM 推理
            transitionTo(State.LLM)
            val llmText = llmNode.run(requestId, assistantId, text)

            if (!isActive || activeRequestId != requestId) return@launch

            // TTS 播报
            transitionTo(State.TTS)
            ttsNode.speak(requestId, llmText)

            if (isActive && activeRequestId == requestId) {
                transitionTo(State.IDLE)
                if (config.inputMode == "call") {
                    startContinuousListening()
                }
            }
        }
    }

    private fun cancelActiveJob(reason: String) {
        activeJob?.cancel(CancellationException(reason))
        activeJob = null
    }

    private fun startContinuousListening() {
        transitionTo(State.LISTENING)
        scope.launch { sttNode.startListening() }
    }

    private fun transitionTo(newState: State) {
        _state.value = newState
        eventSink.onStateChanged(
            sessionId,
            newState.name.lowercase(),
            activeRequestId,
        )
    }
}

/** Agent 事件回调接口（由 AgentRuntimePlugin 实现，转发给 Flutter） */
interface AgentEventSink {
    fun onSttEvent(event: SttEventData)
    fun onLlmEvent(event: LlmEventData)
    fun onTtsEvent(event: TtsEventData)
    fun onStateChanged(sessionId: String, state: String, requestId: String?)
    fun onError(sessionId: String, errorCode: String, message: String, requestId: String?)
}

/** Agent 会话配置（从 Pigeon AgentSessionConfig 转换） */
data class AgentSessionConfig(
    val sessionId: String,
    val agentId: String,
    val inputMode: String,
    val sttPluginName: String,
    val ttsPluginName: String,
    val llmPluginName: String,
    val stsPluginName: String?,
    val sttConfigJson: String,
    val ttsConfigJson: String,
    val llmConfigJson: String,
    val stsConfigJson: String?,
)

// 事件数据类（对应 Pigeon 生成类，在 codegen 前手写）
data class SttEventData(
    val sessionId: String, val requestId: String,
    val kind: String, val text: String? = null,
    val errorCode: String? = null, val errorMessage: String? = null,
)

data class LlmEventData(
    val sessionId: String, val requestId: String,
    val kind: String,
    val textDelta: String? = null, val thinkingDelta: String? = null,
    val toolCallId: String? = null, val toolName: String? = null,
    val toolArgumentsDelta: String? = null, val toolResult: String? = null,
    val fullText: String? = null,
    val errorCode: String? = null, val errorMessage: String? = null,
)

data class TtsEventData(
    val sessionId: String, val requestId: String,
    val kind: String,
    val progressMs: Int? = null, val durationMs: Int? = null,
    val errorCode: String? = null, val errorMessage: String? = null,
)
