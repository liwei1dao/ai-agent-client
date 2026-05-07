package com.aiagent.agent_sts_chat

import android.content.Context
import android.util.Log
import com.aiagent.local_db.AppDatabase
import com.aiagent.local_db.entity.MessageEntity
import com.aiagent.plugin_interface.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.UUID

/**
 * StsChatAgentSession — STS (端到端语音对话) Agent 原生实现
 *
 * 使用 NativeStsService 通过 WebSocket 进行实时语音对话。
 * 服务端完成 ASR → LLM → TTS 全流程，客户端只负责音频收发。
 *
 * 简化状态机：IDLE → CONNECTED → IDLE
 *
 * 生命周期：
 *   initialize → connect(WebSocket) → setInputMode("call") → startAudio
 *   → [实时双向音频流] → setInputMode("text") → stopAudio → release
 *
 * 从 AgentSession.kt 的 isStsAgent 分支提取。
 */
class StsChatAgentSession : NativeAgent {

    companion object {
        private const val TAG = "StsChatAgentSession"
    }

    override val agentType = "sts"

    private enum class State { IDLE, CONNECTED, ERROR }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(State.IDLE)

    private lateinit var stsService: NativeStsService
    private lateinit var db: AppDatabase
    private lateinit var eventSink: AgentEventSink
    private lateinit var config: NativeAgentConfig
    private lateinit var appContext: Context

    private var connectJob: Job? = null
    private var inputMode: String = "text"

    /** 当前 AI 回复的消息 ID（同一轮回复累加到同一条消息） */
    @Volatile private var currentAssistantId: String? = null
    /** 暂存部分识别的用户文本 */
    @Volatile private var pendingUserText: String = ""
    /** 上次已向 UI 发送的累积文本长度，用于计算 delta */
    @Volatile private var lastSentLength: Int = 0

    // ─────────────────────────────────────────────────
    // NativeAgent 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(config: NativeAgentConfig, eventSink: AgentEventSink, context: Context) {
        this.config = config
        this.eventSink = eventSink
        this.inputMode = config.inputMode
        this.appContext = context.applicationContext
        this.db = AppDatabase.getInstance(context)

        // Create STS service from NativeServiceRegistry
        stsService = NativeServiceRegistry.createSts(config.stsVendor ?: "volcengine")

        // Initialize STS service with config
        stsService.initialize(config.stsConfigJson ?: "{}", context)

        Log.d(TAG, "initialized: agentId=${config.agentId} stsVendor=${config.stsVendor}")
    }

    override fun connectService() {
        Log.d(TAG, "connectService: agentId=${config.agentId}")
        connectJob?.cancel()

        // 重建 STS service（上一次 disconnectService 调用了 release）
        stsService = NativeServiceRegistry.createSts(config.stsVendor ?: "volcengine")
        stsService.initialize(config.stsConfigJson ?: "{}", appContext)

        connectJob = scope.launch {
            try {
                stsService.connect(stsCallback)
            } catch (e: CancellationException) {
                // normal cancellation
            } catch (e: Exception) {
                Log.e(TAG, "STS connect failed: ${e.message}")
                transitionTo(State.ERROR)
                eventSink.onError(config.agentId, "sts_connect_error", e.message ?: "Unknown error", null)
                eventSink.onAgentReady(
                    config.agentId, ready = false,
                    errorCode = "sts_connect_error",
                    errorMessage = e.message ?: "Unknown error",
                )
            }
        }
    }

    override fun disconnectService() {
        Log.d(TAG, "disconnectService: agentId=${config.agentId}")
        connectJob?.cancel()
        stsService.release()
        transitionTo(State.IDLE)
        eventSink.onConnectionStateChanged(config.agentId, "disconnected")
    }

    override fun sendText(requestId: String, text: String) {
        // STS 是纯语音模式，不支持文本输入
        Log.w(TAG, "sendText called but STS is voice-only, ignoring: $text")
    }

    override fun startListening() {
        // STS 模式不使用独立的 STT 监听，音频通过 WebSocket 直接发送
        Log.d(TAG, "startListening: delegating to startAudio")
        stsService.startAudio()
    }

    override fun stopListening() {
        Log.d(TAG, "stopListening: delegating to stopAudio")
        stsService.stopAudio()
    }

    override fun setInputMode(mode: String) {
        Log.d(TAG, "setInputMode: $mode")
        inputMode = mode
        when (mode) {
            "call" -> {
                // 开始发送麦克风音频（需先调用 connectService 建立 WebSocket）
                stsService.startAudio()
            }
            "short_voice" -> { /* 按住说话，由 UI 调用 startListening/stopListening */ }
            else -> {
                // 停止发送麦克风音频，WebSocket 保持连接
                stsService.stopAudio()
            }
        }
    }

    override fun interrupt() {
        // STS 模式：仅清空 TTS 播放缓冲，WebSocket 保持连接
        stsService.interrupt()
        transitionTo(State.CONNECTED)
    }

    override fun release() {
        connectJob?.cancel()
        scope.cancel()
        stsService.release()
    }

    // ─────────────────────────────────────────────────
    // 外部音频源（AI 助理 / 通话翻译等场景）—— 透传到底层 NativeStsService
    //
    // 与 setInputMode("call") 触发的 self-mic 路径互斥；编排器在 AI 助理场景
    // 显式以 inputMode='external' 初始化，并在 connect 完成后调
    // startExternalAudio 接管音源，绝不能再走 self-mic（会抢 RECORD_AUDIO 与 SCO）。
    // ─────────────────────────────────────────────────

    override fun externalAudioCapability(): ExternalAudioCapability =
        stsService.externalAudioCapability()

    override fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        stsService.startExternalAudio(format, sink)
    }

    override fun pushExternalAudioFrame(frame: ByteArray) {
        stsService.pushExternalAudioFrame(frame)
    }

    override fun stopExternalAudio() {
        stsService.stopExternalAudio()
    }

    // ─────────────────────────────────────────────────
    // STS 回调 → AgentEventSink 事件转换
    // ─────────────────────────────────────────────────

    private val stsCallback = object : StsCallback {
        override fun onConnected() {
            transitionTo(State.CONNECTED)
            eventSink.onConnectionStateChanged(config.agentId, "connected")
            eventSink.onAgentReady(config.agentId, ready = true)
            Log.d(TAG, "WebSocket connected, inputMode=$inputMode")
            // 如果用户已切换到 call 模式但连接还没好，现在自动启动音频
            if (inputMode == "call") {
                stsService.startAudio()
            }
        }

        override fun onSttPartialResult(text: String) {
            // 部分识别 → 覆盖暂存，发 partialResult 供 UI 实时预览
            pendingUserText = text
            eventSink.onSttEvent(SttEventData(
                config.agentId, requestId = "", kind = "partialResult", text = text))
        }

        override fun onSttFinalResult(text: String) {
            // 最终识别 → 定稿用户消息，重置 AI 回复 ID（下次 sentenceDone 开新消息）
            pendingUserText = ""
            currentAssistantId = null

            val reqId = UUID.randomUUID().toString()
            eventSink.onSttEvent(SttEventData(
                config.agentId, requestId = reqId, kind = "finalResult", text = text))

            scope.launch {
                runCatching {
                    val now = System.currentTimeMillis()
                    db.messageDao().insert(MessageEntity(
                        id = reqId, agentId = config.agentId,
                        role = "user", content = text, status = "done",
                        createdAt = now, updatedAt = now,
                    ))
                }
            }
        }

        override fun onTtsAudioChunk(pcmData: ByteArray) {
            // TTS 音频由 STS 服务内部播放
        }

        override fun onChatPartialResult(cumulativeText: String) {
            // 流式 token 到来：计算增量并推送到 UI
            val delta = cumulativeText.substring(lastSentLength)
            if (delta.isEmpty()) return

            val isNew = currentAssistantId == null
            val msgId = currentAssistantId ?: UUID.randomUUID().toString().also { currentAssistantId = it }

            if (isNew) {
                // 首个 token：在 DB 插入 streaming 消息
                scope.launch {
                    runCatching {
                        val now = System.currentTimeMillis()
                        db.messageDao().insert(MessageEntity(
                            id = msgId, agentId = config.agentId,
                            role = "assistant", content = cumulativeText, status = "streaming",
                            createdAt = now, updatedAt = now,
                        ))
                    }
                }
            } else {
                // 后续 token：追加内容到 DB
                scope.launch {
                    runCatching {
                        db.messageDao().appendContent(msgId, delta, System.currentTimeMillis())
                    }
                }
            }

            lastSentLength = cumulativeText.length
            eventSink.onLlmEvent(LlmEventData(
                config.agentId, requestId = msgId, kind = "firstToken", textDelta = delta))
        }

        override fun onSentenceDone(text: String) {
            // AI 回复完成：若没有经过流式路径则兜底发完整文本；最终发 done 关闭气泡
            val msgId = currentAssistantId
            lastSentLength = 0

            if (msgId == null) {
                // 无流式更新（兜底）：整句一次性发出
                val id = UUID.randomUUID().toString()
                currentAssistantId = id
                eventSink.onLlmEvent(LlmEventData(
                    config.agentId, requestId = id, kind = "firstToken", textDelta = text))
                scope.launch {
                    runCatching {
                        val now = System.currentTimeMillis()
                        db.messageDao().insert(MessageEntity(
                            id = id, agentId = config.agentId,
                            role = "assistant", content = text, status = "done",
                            createdAt = now, updatedAt = now,
                        ))
                    }
                }
                eventSink.onLlmEvent(LlmEventData(
                    config.agentId, requestId = id, kind = "done", fullText = text))
                currentAssistantId = null
            } else {
                // 已有流式气泡：直接 done
                currentAssistantId = null
                eventSink.onLlmEvent(LlmEventData(
                    config.agentId, requestId = msgId, kind = "done", fullText = text))
                scope.launch {
                    runCatching {
                        db.messageDao().updateStatus(msgId, "done", System.currentTimeMillis())
                    }
                }
            }
        }

        override fun onDisconnected() {
            transitionTo(State.IDLE)
            eventSink.onConnectionStateChanged(config.agentId, "disconnected")
            Log.d(TAG, "WebSocket disconnected")
        }

        override fun onError(code: String, message: String) {
            transitionTo(State.ERROR)
            eventSink.onConnectionStateChanged(config.agentId, "error", message)
            eventSink.onError(config.agentId, code, message, null)
            eventSink.onAgentReady(config.agentId, ready = false, errorCode = code, errorMessage = message)
        }

        override fun onSpeechStart() {
            // 用户开口 → 当前 AI 回复被打断，标记 done，重置 ID
            val prevId = currentAssistantId
            lastSentLength = 0
            if (prevId != null) {
                eventSink.onLlmEvent(LlmEventData(
                    config.agentId, requestId = prevId, kind = "done"))
                scope.launch { runCatching { db.messageDao().updateStatus(prevId, "done", System.currentTimeMillis()) } }
                currentAssistantId = null
            }
            eventSink.onSttEvent(SttEventData(
                config.agentId, requestId = "", kind = "vadSpeechStart"))
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
