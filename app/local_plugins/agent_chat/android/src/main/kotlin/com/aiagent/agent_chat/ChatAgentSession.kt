package com.aiagent.agent_chat

import android.content.Context
import android.util.Log
import com.aiagent.local_db.AppDatabase
import com.aiagent.local_db.entity.MessageEntity
import com.aiagent.plugin_interface.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ChatAgentSession — Chat Agent 原生实现
 *
 * 编排 STT + LLM + TTS 管线，实现普通组合式聊天 Agent。
 *
 * 状态机：IDLE → LISTENING → STT → LLM → TTS → IDLE
 *
 * 打断机制（"latest wins"）：
 * - activeRequestId 保存当前请求 UUID
 * - 新输入到来时 cancel activeJob → 更新 activeRequestId → 启动新管线
 * - speechStartDetected → 打断当前 LLM/TTS → 回到 LISTENING
 *
 * 从 AgentSession.kt 提取 chat 类型的核心逻辑。
 */
class ChatAgentSession : NativeAgent {

    companion object {
        private const val TAG = "ChatAgentSession"

        // 句级切分：硬终结符立即切；逗号在累计 >= SOFT_THRESHOLD 字符后才切
        private val HARD_TERMINATORS = setOf('。', '！', '？', '.', '!', '?', '；', ';', '\n')
        private val SOFT_TERMINATORS = setOf('，', ',')
        private const val SOFT_THRESHOLD = 15

        /** 合成并发上限（按 §4.1，避免厂商 QPS 限流） */
        private const val MAX_CONCURRENT_SYNTHESIS = 2

        /** 在 [sb] 中找一个完整句的结束位置（含终结符），未命中返回 -1 */
        private fun findSentenceCut(sb: StringBuilder): Int {
            for (i in sb.indices) {
                val c = sb[i]
                if (c in HARD_TERMINATORS) return i + 1
                if (c in SOFT_TERMINATORS && (i + 1) >= SOFT_THRESHOLD) return i + 1
            }
            return -1
        }
    }

    /**
     * TTS 段：seq 决定播放顺序；audio 由合成池 worker 完成（可能乱序），
     * 播放消费者按 seq 顺序 await audio，因此短段先合成完也不会抢先播放。
     */
    private data class TtsSegment(
        val seq: Int,
        val text: String,
        val audio: CompletableDeferred<TtsAudio>,
    )

    override val agentType = "chat"

    private enum class State { IDLE, LISTENING, STT, LLM, TTS, PLAYING, ERROR }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(State.IDLE)

    @Volatile
    private var activeRequestId: String? = null
    private var activeJob: Job? = null

    private lateinit var sttService: NativeSttService
    private lateinit var llmService: NativeLlmService
    private lateinit var ttsService: NativeTtsService
    private lateinit var db: AppDatabase
    private lateinit var eventSink: AgentEventSink
    private lateinit var config: NativeAgentConfig

    private var inputMode: String = "text"

    // ─────────────────────────────────────────────────
    // NativeAgent 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(config: NativeAgentConfig, eventSink: AgentEventSink, context: Context) {
        this.config = config
        this.eventSink = eventSink
        this.inputMode = config.inputMode
        this.db = AppDatabase.getInstance(context)

        // Create service instances from NativeServiceRegistry
        sttService = NativeServiceRegistry.createStt(config.sttVendor ?: "azure")
        llmService = NativeServiceRegistry.createLlm(config.llmVendor ?: "openai")
        ttsService = NativeServiceRegistry.createTts(config.ttsVendor ?: "azure")

        // Initialize services with their configs
        sttService.initialize(config.sttConfigJson ?: "{}", context)
        llmService.initialize(config.llmConfigJson ?: "{}")
        ttsService.initialize(config.ttsConfigJson ?: "{}", context)

        Log.d(TAG, "initialized: agentId=${config.agentId} stt=${config.sttVendor} llm=${config.llmVendor} tts=${config.ttsVendor}")
    }

    override fun sendText(requestId: String, text: String) {
        onUserInput(requestId, text)
    }

    override fun startListening() {
        transitionTo(State.LISTENING)
        sttService.startListening(sttCallback)
    }

    override fun stopListening() {
        sttService.stopListening()
    }

    override fun setInputMode(mode: String) {
        Log.d(TAG, "setInputMode: $mode")
        inputMode = mode
        when (mode) {
            "call" -> {
                llmService.cancel()
                ttsService.stop()
                cancelActiveJob("mode_switch_call")
                startContinuousListening()
            }
            "short_voice" -> { /* UI controls startListening/stopListening */ }
            else -> {
                sttService.stopListening()
            }
        }
    }

    override fun interrupt() {
        llmService.cancel()
        ttsService.stop()
        cancelActiveJob("manual_interrupt")
        transitionTo(State.IDLE)
    }

    override fun release() {
        scope.cancel()
        sttService.release()
        ttsService.release()
    }

    // ─────────────────────────────────────────────────
    // 核心：用户输入触发 LLM→TTS 管线
    // ─────────────────────────────────────────────────

    private fun onUserInput(requestId: String, text: String) {
        val previousId = activeRequestId
        cancelActiveJob("new_input")
        activeRequestId = requestId

        activeJob = scope.launch {
            // Mark previous assistant message as cancelled
            if (previousId != null) {
                runCatching {
                    db.messageDao().updateStatus(previousId, "cancelled", System.currentTimeMillis())
                }
            }

            // Write user message to DB
            val now = System.currentTimeMillis()
            db.messageDao().insert(
                MessageEntity(
                    id = requestId,
                    agentId = config.agentId,
                    role = "user",
                    content = text,
                    status = "done",
                    createdAt = now,
                    updatedAt = now,
                )
            )

            // Write placeholder assistant message
            val assistantId = UUID.randomUUID().toString()
            db.messageDao().insert(
                MessageEntity(
                    id = assistantId,
                    agentId = config.agentId,
                    role = "assistant",
                    content = "",
                    status = "pending",
                    createdAt = now + 1,
                    updatedAt = now + 1,
                )
            )

            // ── LLM 推理（流式）+ 句级 TTS 队列 ──
            transitionTo(State.LLM)
            db.messageDao().updateStatus(assistantId, "streaming", System.currentTimeMillis())

            // Build history messages from DB
            val messages = buildMessageHistory()

            // 句缓冲 + 双流水线：
            //   合成队列 synthQueue → N 个 worker 并发合成（音频可能乱序就绪）
            //   播放队列 playQueue  → 单消费者按 seq 顺序 await audio 播放（顺序铁律）
            val sentenceBuffer = StringBuilder()
            val bufferLock = Any()
            val synthQueue = Channel<TtsSegment>(Channel.UNLIMITED)
            val playQueue = Channel<TtsSegment>(Channel.UNLIMITED)
            val firstSegmentEmitted = AtomicBoolean(false)
            var seqGen = 0

            // 合成池：MAX_CONCURRENT_SYNTHESIS 个 worker，并发合成
            val synthWorkers = List(MAX_CONCURRENT_SYNTHESIS) {
                launch {
                    for (seg in synthQueue) {
                        if (!isActive || activeRequestId != requestId) {
                            seg.audio.cancel(CancellationException("session_inactive"))
                            continue
                        }
                        try {
                            val audio = ttsService.synthesize(requestId, seg.text)
                            seg.audio.complete(audio)
                        } catch (e: CancellationException) {
                            seg.audio.cancel(e)
                            throw e
                        } catch (e: Throwable) {
                            Log.e(TAG, "synthesize seq=${seg.seq} failed: ${e.message}")
                            seg.audio.completeExceptionally(e)
                        }
                    }
                }
            }

            // 播放消费者：单协程，按 seq（即 playQueue 入队顺序）严格串行播放
            val ttsCallback = object : TtsCallback {
                override fun onSynthesisStart() { /* 由首段触发，已在 emitSegment 中派发 */ }
                override fun onSynthesisReady(durationMs: Int) {
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "synthesisReady", durationMs = durationMs))
                }
                override fun onPlaybackStart() { /* 由首段触发，已在 emitSegment 中派发 */ }
                override fun onPlaybackProgress(progressMs: Int) {
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "playbackProgress", progressMs = progressMs))
                }
                override fun onPlaybackDone() { /* 段完成不向上派发，整轮结束统一派 */ }
                override fun onPlaybackInterrupted() {
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "playbackInterrupted"))
                }
                override fun onError(code: String, message: String) {
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "error", errorCode = code, errorMessage = message))
                }
            }
            val ttsConsumer = launch {
                try {
                    for (seg in playQueue) {
                        if (!isActive || activeRequestId != requestId) break
                        try {
                            val audio = seg.audio.await() // 顺序铁律：未合成好就在此阻塞，不会跳序
                            eventSink.onTtsEvent(TtsEventData(
                                config.agentId, requestId,
                                kind = "synthesisReady",
                                durationMs = audio.durationMs ?: 0,
                            ))
                            ttsService.play(requestId, audio, ttsCallback)
                        } catch (e: CancellationException) {
                            throw e
                        } catch (e: Throwable) {
                            Log.e(TAG, "play seq=${seg.seq} failed: ${e.message}")
                            eventSink.onTtsEvent(TtsEventData(
                                config.agentId, requestId,
                                kind = "error",
                                errorCode = "tts_segment_failed",
                                errorMessage = e.message ?: "",
                            ))
                            // 单段失败不阻塞后续段
                        }
                    }
                    if (firstSegmentEmitted.get() && isActive && activeRequestId == requestId) {
                        eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "playbackDone"))
                    }
                } catch (e: CancellationException) {
                    throw e
                }
            }

            fun emitSegment(seg: String) {
                if (seg.isBlank()) return
                if (firstSegmentEmitted.compareAndSet(false, true)) {
                    transitionTo(State.TTS)
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "synthesisStart"))
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "playbackStart"))
                }
                val item = TtsSegment(seqGen++, seg, CompletableDeferred())
                // 顺序很关键：先入 playQueue 锁定播放顺序，再入 synthQueue 触发合成
                playQueue.trySend(item)
                synthQueue.trySend(item)
            }

            fun pushDelta(delta: String) {
                synchronized(bufferLock) {
                    sentenceBuffer.append(delta)
                    while (true) {
                        val cut = findSentenceCut(sentenceBuffer)
                        if (cut < 0) break
                        val seg = sentenceBuffer.substring(0, cut)
                        sentenceBuffer.delete(0, cut)
                        emitSegment(seg)
                    }
                }
            }

            try {
                llmService.chat(
                    requestId = requestId,
                    messages = messages,
                    tools = emptyList(),
                    callback = object : LlmCallback {
                        override fun onFirstToken(textDelta: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "firstToken", textDelta = textDelta))
                            scope.launch { db.messageDao().appendContent(assistantId, textDelta, System.currentTimeMillis()) }
                            pushDelta(textDelta)
                        }
                        override fun onTextDelta(textDelta: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "firstToken", textDelta = textDelta))
                            scope.launch { db.messageDao().appendContent(assistantId, textDelta, System.currentTimeMillis()) }
                            pushDelta(textDelta)
                        }
                        override fun onThinkingDelta(delta: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "thinking", thinkingDelta = delta))
                        }
                        override fun onToolCallStart(id: String, name: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "toolCallStart",
                                toolCallId = id, toolName = name))
                        }
                        override fun onToolCallArguments(delta: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "toolCallArguments",
                                toolArgumentsDelta = delta))
                        }
                        override fun onToolCallResult(result: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "toolCallResult",
                                toolResult = result))
                        }
                        override fun onDone(fullText: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "done", fullText = fullText))
                            scope.launch { db.messageDao().updateStatus(assistantId, "done", System.currentTimeMillis()) }
                        }
                        override fun onError(code: String, message: String) {
                            eventSink.onLlmEvent(LlmEventData(
                                config.agentId, requestId, kind = "error",
                                errorCode = code, errorMessage = message))
                            scope.launch { db.messageDao().updateStatus(assistantId, "error", System.currentTimeMillis()) }
                        }
                    }
                )

                // LLM 完毕：把残余尾巴当最后一段送播
                val tail = synchronized(bufferLock) {
                    val s = sentenceBuffer.toString()
                    sentenceBuffer.clear()
                    s
                }
                if (tail.isNotBlank()) emitSegment(tail)
            } finally {
                // 关合成入口 → 等合成池跑完剩余段 → 关播放入口 → 等播放消费者收尾
                synthQueue.close()
                synthWorkers.forEach { it.join() }
                playQueue.close()
            }

            ttsConsumer.join()

            if (isActive && activeRequestId == requestId) {
                transitionTo(State.IDLE)
                if (inputMode == "call") {
                    startContinuousListening()
                }
            }
        }
    }

    // ─────────────────────────────────────────────────
    // STT 回调
    // ─────────────────────────────────────────────────

    private val sttCallback = object : SttCallback {
        override fun onListeningStarted() {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "listeningStarted"))
        }
        override fun onPartialResult(text: String) {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "partialResult", text = text))
        }
        override fun onFinalResult(text: String) {
            val reqId = UUID.randomUUID().toString()
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = reqId, kind = "finalResult", text = text))
            // call 模式：自动触发 LLM 管线
            if (inputMode == "call") {
                onUserInput(reqId, text)
            }
        }
        override fun onVadSpeechStart() {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "vadSpeechStart"))
            interruptForVoiceInput()
        }
        override fun onVadSpeechEnd() {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "vadSpeechEnd"))
        }
        override fun onListeningStopped() {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "listeningStopped"))
        }
        override fun onError(code: String, message: String) {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "error", errorCode = code, errorMessage = message))
        }
    }

    // ─────────────────────────────────────────────────
    // 内部方法
    // ─────────────────────────────────────────────────

    /**
     * 用户开口说话 → 打断正在进行的 TTS/LLM，回到 LISTENING
     */
    private fun interruptForVoiceInput() {
        if (_state.value == State.IDLE || _state.value == State.LISTENING) return
        val prevId = activeRequestId
        llmService.cancel()
        ttsService.stop()
        cancelActiveJob("voice_interrupt")
        if (prevId != null) {
            scope.launch {
                runCatching { db.messageDao().updateStatus(prevId, "cancelled", System.currentTimeMillis()) }
            }
        }
        transitionTo(State.LISTENING)
        Log.d(TAG, "voice interrupt: cancelled requestId=$prevId, back to LISTENING")
    }

    private fun cancelActiveJob(reason: String) {
        activeJob?.cancel(CancellationException(reason))
        activeJob = null
    }

    private fun startContinuousListening() {
        Log.d(TAG, "startContinuousListening")
        transitionTo(State.LISTENING)
        sttService.startListening(sttCallback)
    }

    private fun transitionTo(newState: State) {
        _state.value = newState
        eventSink.onStateChanged(
            config.agentId,
            newState.name.lowercase(),
            activeRequestId,
        )
    }

    /**
     * 从 DB 读取消息历史，过滤 + 去重 + 截断
     */
    private suspend fun buildMessageHistory(): List<Map<String, Any>> {
        val rawMessages = db.messageDao().getMessages(config.agentId, 40).reversed()
        val validMessages = rawMessages.filter {
            it.content.isNotBlank() &&
            it.status !in listOf("error", "cancelled", "pending")
        }
        // Remove consecutive same-role messages (keep latest)
        val deduplicated = mutableListOf<MessageEntity>()
        for (msg in validMessages) {
            if (deduplicated.isNotEmpty() && deduplicated.last().role == msg.role) {
                deduplicated[deduplicated.lastIndex] = msg
            } else {
                deduplicated.add(msg)
            }
        }
        // Ensure last message is 'user'
        while (deduplicated.isNotEmpty() && deduplicated.last().role != "user") {
            deduplicated.removeAt(deduplicated.lastIndex)
        }
        return deduplicated.takeLast(20).map { msg ->
            mapOf<String, Any>("role" to msg.role, "content" to msg.content)
        }
    }
}
