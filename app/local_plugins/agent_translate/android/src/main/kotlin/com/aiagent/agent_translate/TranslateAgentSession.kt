package com.aiagent.agent_translate

import android.content.Context
import android.util.Log
import com.aiagent.local_db.AppDatabase
import com.aiagent.local_db.entity.MessageEntity
import com.aiagent.plugin_interface.*
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

/**
 * TranslateAgentSession — 组合式翻译 Agent 原生实现
 *
 * 编排 STT + Translation + TTS 管线，实现语音翻译 Agent。
 * 类似 ChatAgentSession，但用 Translation 替代 LLM。
 *
 * 状态机：IDLE → LISTENING → STT → TRANSLATING → TTS → IDLE
 *
 * 调度模型：**所有输入一律 FIFO 队列处理，互不打断**。
 * 翻译场景下"换一句话"应该排队顺序翻译/播报，而不是抢占——这与 chat agent
 * 的 latest-wins 是相反的取舍。无论 call / short_voice / text / PTT 路径，
 * 输入都进入 [callQueue] 由单消费者顺序跑 translate + TTS。
 * VAD speechStart 也不再触发打断；仅显式 [interrupt] / mode 切换 / release
 * 才会清空队列。
 *
 * 从 config.extraParams 获取 srcLang / dstLang。
 */
class TranslateAgentSession : NativeAgent {

    companion object {
        private const val TAG = "TranslateAgentSession"

        const val DIRECTION_SRC_TO_DST = "src_to_dst"
        const val DIRECTION_DST_TO_SRC = "dst_to_src"

        /** 合成并发上限（按 §4.1） */
        private const val MAX_CONCURRENT_SYNTHESIS = 2

        /** 句子终结符（覆盖中英文常见标点）*/
        private val SENTENCE_TERMINATORS = setOf(
            '。', '！', '？', '.', '!', '?', '；', ';', '\n',
        )

        /**
         * 把整段翻译文本切成多段（按句切）。
         * 终结符随段保留；末尾未带终结符的剩余文本作为最后一段。
         */
        private fun splitSentences(text: String): List<String> {
            val result = mutableListOf<String>()
            val buf = StringBuilder()
            for (c in text) {
                buf.append(c)
                if (c in SENTENCE_TERMINATORS) {
                    val s = buf.toString().trim()
                    if (s.isNotEmpty()) result.add(s)
                    buf.clear()
                }
            }
            val tail = buf.toString().trim()
            if (tail.isNotEmpty()) result.add(tail)
            return result
        }
    }

    /** 同 ChatAgentSession：seq 锁定播放顺序，audio 由合成池完成 */
    private data class TtsSegment(
        val seq: Int,
        val text: String,
        val audio: CompletableDeferred<TtsAudio>,
    )

    override val agentType = "translate"

    private enum class State { IDLE, LISTENING, STT, TRANSLATING, TTS, PLAYING, ERROR }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _state = MutableStateFlow(State.IDLE)

    @Volatile
    private var activeRequestId: String? = null

    /**
     * 全局 FIFO 翻译队列（所有 inputMode 共用）。
     *
     * 每条输入（finalResult / sendText）都作为独立 [QueuedRequest] 入队，由
     * 单消费者 [callQueueWorker] 顺序跑 translate + TTS，**互不打断**。
     * "换一句话"在翻译场景下意味着排队顺序翻译，不是抢占。
     */
    private data class QueuedRequest(val requestId: String, val text: String, val direction: String)

    private var callQueue: Channel<QueuedRequest>? = null
    private var callQueueWorker: Job? = null

    private lateinit var sttService: NativeSttService
    private lateinit var translationService: NativeTranslationService
    private lateinit var ttsService: NativeTtsService
    private lateinit var db: AppDatabase
    private lateinit var eventSink: AgentEventSink
    private lateinit var config: NativeAgentConfig

    private var inputMode: String = "text"
    private var srcLang: String? = null
    private var dstLang: String = "en"

    /**
     * 通话翻译等外部音频源场景下为 true：STT 已通过 [startExternalAudio] 进入
     * `externalMode`，由 [pushExternalAudioFrame] 持续灌入 PCM。此时**不得**走
     * self-mic 路径再调 `sttService.startListening` —— 否则会触发 `stt_busy`。
     */
    @Volatile
    private var externalAudioActive: Boolean = false

    /** 互译开关：开启后 STT finalResult 的 detectedLang 决定翻译方向。 */
    @Volatile
    private var bidirectional: Boolean = false

    /** 文本输入方向（语音输入在 bidirectional 开启时由 detectedLang 覆盖）。 */
    @Volatile
    private var direction: String = DIRECTION_SRC_TO_DST

    /**
     * 最近一次 STT finalResult 的 detectedLang。
     * push-to-talk 路径下，sendText 在 listeningStopped 之后被调用，
     * 这里保存的语种用于 sendText 的方向解算（一次性，消费后清空）。
     */
    @Volatile
    private var lastSttDetectedLang: String? = null

    // ─────────────────────────────────────────────────
    // NativeAgent 接口实现
    // ─────────────────────────────────────────────────

    override fun initialize(config: NativeAgentConfig, eventSink: AgentEventSink, context: Context) {
        this.config = config
        this.eventSink = eventSink
        this.inputMode = config.inputMode
        this.db = AppDatabase.getInstance(context)

        // 从 extraParams 获取翻译语言对
        this.srcLang = config.extraParams["srcLang"]  // null 表示自动检测
        this.dstLang = config.extraParams["dstLang"] ?: "en"
        this.bidirectional = config.extraParams["bidirectional"] == "true"
        this.direction = config.extraParams["direction"] ?: DIRECTION_SRC_TO_DST

        // Create service instances from NativeServiceRegistry
        sttService = NativeServiceRegistry.createStt(config.sttVendor ?: "azure")
        translationService = NativeServiceRegistry.createTranslation(config.translationVendor ?: "deepl")
        ttsService = NativeServiceRegistry.createTts(config.ttsVendor ?: "azure")

        // Initialize services with their configs
        sttService.initialize(config.sttConfigJson ?: "{}", context)
        translationService.initialize(config.translationConfigJson ?: "{}")
        ttsService.initialize(config.ttsConfigJson ?: "{}", context)

        Log.d(TAG, "initialized: agentId=${config.agentId} stt=${config.sttVendor} " +
                "translation=${config.translationVendor} tts=${config.ttsVendor} " +
                "srcLang=$srcLang dstLang=$dstLang")
    }

    override fun connectService() {
        // 三段式 agent 无远端长连接：服务在 initialize 阶段已就位，立即上报 ready。
        eventSink.onAgentReady(config.agentId, ready = true)
    }

    override fun sendText(requestId: String, text: String) {
        // push-to-talk 场景：finalResult 已先到达 native 并把 detectedLang 存入
        // [lastSttDetectedLang]，这里一次性消费用于方向解算；纯文本输入时为 null，
        // resolveDirection 会回退到 UI direction。
        // 所有路径走同一 FIFO 队列，互不打断。
        val det = lastSttDetectedLang
        lastSttDetectedLang = null
        enqueueTranslation(requestId, text, resolveDirection(det))
    }

    override fun setOption(key: String, value: String) {
        when (key) {
            "bidirectional" -> {
                bidirectional = value == "true"
                Log.d(TAG, "setOption bidirectional=$bidirectional")
            }
            "direction" -> {
                direction = if (value == DIRECTION_DST_TO_SRC) DIRECTION_DST_TO_SRC else DIRECTION_SRC_TO_DST
                Log.d(TAG, "setOption direction=$direction")
            }
            else -> Log.d(TAG, "setOption ignored: $key=$value")
        }
    }

    /**
     * 决定本次翻译的方向。
     * - 互译关闭：恒按 [direction]（来自 UI 显式切换）。
     * - 互译开启 + 有 detectedLang：按 detectedLang 与 srcLang/dstLang 的语言段比较选向。
     * - 互译开启 + 无 detectedLang：仍按 [direction]（兜底，例如文本输入）。
     */
    private fun resolveDirection(detectedLang: String?): String {
        if (!bidirectional || detectedLang.isNullOrBlank()) {
            Log.d(TAG, "resolveDirection: bidirectional=$bidirectional " +
                "detectedLang=$detectedLang → fallback direction=$direction")
            return direction
        }
        val src = srcLang ?: ""
        val dst = dstLang
        val det = detectedLang.langBase()
        val resolved = when {
            det == dst.langBase() && det != src.langBase() -> DIRECTION_DST_TO_SRC
            det == src.langBase() -> DIRECTION_SRC_TO_DST
            else -> direction
        }
        Log.d(TAG, "resolveDirection: detectedLang=$detectedLang " +
            "src=$srcLang dst=$dstLang → $resolved")
        return resolved
    }

    private fun String.langBase(): String =
        substringBefore('-').substringBefore('_').lowercase()

    override fun startListening() {
        if (externalAudioActive) {
            Log.d(TAG, "startListening skipped: external audio active")
            return
        }
        transitionTo(State.LISTENING)
        sttService.startListening(sttCallback)
    }

    override fun stopListening() {
        sttService.stopListening()
    }

    override fun setInputMode(mode: String) {
        Log.d(TAG, "setInputMode: $mode")
        inputMode = mode
        // 模式切换是显式动作，清空在途队列重新开始。
        shutdownCallQueue("mode_switch_$mode")
        when (mode) {
            "call" -> {
                // 外部音频源场景下：STT 已在 externalMode，识别由 push 帧驱动，
                // 切勿再走 self-mic 路径 —— 否则触发 stt_busy。
                if (externalAudioActive) return
                ttsService.stop()
                startContinuousListening()
            }
            "short_voice" -> { /* UI controls startListening/stopListening */ }
            else -> {
                sttService.stopListening()
            }
        }
    }

    override fun interrupt() {
        ttsService.stop()
        shutdownCallQueue("manual_interrupt")
        transitionTo(State.IDLE)
    }

    override fun release() {
        shutdownCallQueue("release")
        scope.cancel()
        sttService.release()
        translationService.release()
        ttsService.release()
    }

    // ─────────────────────────────────────────────────
    // 外部音频源（通话翻译等场景）—— 转发给 sttService + ttsService
    //
    // 协议：上行 PCM 由调用方推进 STT；TTS 不再走本地扬声器，而是把合成 PCM
    // 切帧回灌 sink，由调用方（编排器）灌回耳机。识别 finalResult 在
    // inputMode=="call" 路径下自动驱动翻译 + TTS 管线。
    // ─────────────────────────────────────────────────

    override fun externalAudioCapability(): ExternalAudioCapability {
        val s = sttService.externalAudioCapability()
        val t = ttsService.externalAudioCapability()
        return ExternalAudioCapability(
            acceptsOpus = s.acceptsOpus && t.acceptsOpus,
            acceptsPcm = s.acceptsPcm && t.acceptsPcm,
            preferredSampleRate = s.preferredSampleRate,
            preferredChannels = s.preferredChannels,
            preferredFrameMs = s.preferredFrameMs,
        )
    }

    override fun startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) {
        // 进入 call 模式：finalResult 自动触发 translate→TTS（与 self-mic call 路径相同）
        inputMode = "call"
        externalAudioActive = true
        ttsService.startExternalAudio(format, sink)
        sttService.startExternalAudio(format, sttCallback)
    }

    override fun pushExternalAudioFrame(frame: ByteArray) {
        sttService.pushExternalAudioFrame(frame)
    }

    override fun stopExternalAudio() {
        externalAudioActive = false
        sttService.stopExternalAudio()
        ttsService.stop()
        ttsService.stopExternalAudio()
        shutdownCallQueue("external_audio_stop")
        transitionTo(State.IDLE)
    }

    // ─────────────────────────────────────────────────
    // 核心：用户输入触发 Translation→TTS 管线
    // ─────────────────────────────────────────────────

    /**
     * 把一次输入入队。第一次入队时懒启动消费者协程；消费者顺序执行
     * [runTranslationPipeline]，**互不打断**。所有 inputMode 共用同一队列。
     */
    private fun enqueueTranslation(requestId: String, text: String, dir: String) {
        if (callQueue == null) {
            val ch = Channel<QueuedRequest>(Channel.UNLIMITED)
            callQueue = ch
            callQueueWorker = scope.launch {
                try {
                    for (req in ch) {
                        if (!isActive) break
                        activeRequestId = req.requestId
                        runCatching { runTranslationPipeline(req.requestId, req.text, req.direction) }
                            .onFailure { e ->
                                if (e is CancellationException) throw e
                                Log.e(TAG, "queued translation failed: ${e.message}")
                            }
                        // 单条管线跑完根据 inputMode 回到 LISTENING / IDLE；
                        // 下一条若已在队列里，它自己 transitionTo(TRANSLATING) 会立即覆盖。
                        if (isActive) {
                            if (inputMode == "call") {
                                transitionTo(State.LISTENING)
                            } else {
                                activeRequestId = null
                                transitionTo(State.IDLE)
                            }
                        }
                    }
                } catch (e: CancellationException) {
                    // 队列被显式取消（interrupt / stopExternalAudio / mode_switch / release）
                }
            }
        }
        callQueue?.trySend(QueuedRequest(requestId, text, dir))
    }

    /**
     * 清空翻译队列。仅显式动作（打断 / 停止 / 换模式 / release）调用。
     */
    private fun shutdownCallQueue(reason: String) {
        callQueue?.close()
        callQueue = null
        callQueueWorker?.cancel(CancellationException(reason))
        callQueueWorker = null
        activeRequestId = null
    }

    /**
     * 翻译 + TTS 纯管线。
     *
     * 取消语义只看协程的 [isActive]：worker 协程未被取消时一路跑完，互不打断；
     * 只有 [shutdownCallQueue]（显式打断 / 停止 / 换模式 / release）会取消 worker。
     */
    private suspend fun runTranslationPipeline(requestId: String, text: String, dir: String) = coroutineScope {
        val (sourceForCall, targetForCall) = if (dir == DIRECTION_DST_TO_SRC) {
            dstLang to (srcLang ?: dstLang)
        } else {
            (srcLang) to dstLang
        }

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

        transitionTo(State.TRANSLATING)
        db.messageDao().updateStatus(assistantId, "streaming", System.currentTimeMillis())
        eventSink.onLlmEvent(LlmEventData(
            config.agentId, requestId, kind = "firstToken", textDelta = ""))

        val translationResult = try {
            translationService.translate(
                text = text,
                targetLang = targetForCall,
                sourceLang = sourceForCall,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Translation failed: ${e.message}")
            eventSink.onLlmEvent(LlmEventData(
                config.agentId, requestId, kind = "error",
                errorCode = "translation_error", errorMessage = e.message ?: "Unknown error"))
            db.messageDao().updateStatus(assistantId, "error", System.currentTimeMillis())
            transitionTo(State.ERROR)
            return@coroutineScope
        }

        if (!isActive) return@coroutineScope

        val translatedText = translationResult.translatedText
        db.messageDao().appendContent(assistantId, translatedText, System.currentTimeMillis())
        db.messageDao().updateStatus(assistantId, "done", System.currentTimeMillis())
        eventSink.onLlmEvent(LlmEventData(
            config.agentId, requestId, kind = "done", fullText = translatedText))

        if (!isActive) return@coroutineScope

        if (translatedText.isNotBlank()) {
            transitionTo(State.TTS)
            runTtsPipeline(requestId, translatedText)
        }
    }

    /**
     * TTS 流水线：把整段翻译切成多句，N 个 worker 并发合成，单消费者按 seq 顺序播放。
     *
     * 顺序铁律：playQueue 入队顺序 = 文本顺序；播放消费者按 seq await 各段 audio，
     * 因此短段先合成完也不会抢先播放。
     *
     * 例外：通话翻译（inputMode=="call"）下**禁用句切**——把整段译文当作 1 个子句一次合成、
     * 一次 play。原因：call 模式下 TTS 走 [ExternalAudioSink] → device runtime → RCSP
     * writeAudioData，每次 play 的末帧 isFinal=true 会触发 runtime 整段编码 + 一个
     * AudioData 下发。多子句意味着多 AudioData 串行下发（每段 encode + 蓝牙 write），
     * 延迟随子句数线性累加。整段一次 play 让 runtime 的 3s 阈值真正生效——长译文按 3s
     * 滚动 flush，短译文一次到达；不会再有"说完后多个子句串行下发"的尾延迟。
     * 本地播报（外放/听筒）路径保留分句以获得首句快速到达的体验。
     */
    private suspend fun runTtsPipeline(requestId: String, text: String) = coroutineScope {
        val sentences = if (inputMode == "call") listOf(text.trim()).filter { it.isNotEmpty() }
                        else splitSentences(text)
        if (sentences.isEmpty()) return@coroutineScope

        val synthQueue = Channel<TtsSegment>(Channel.UNLIMITED)
        val playQueue = Channel<TtsSegment>(Channel.UNLIMITED)
        val firstSegmentEmitted = AtomicBoolean(false)

        // 合成池
        val synthWorkers = List(MAX_CONCURRENT_SYNTHESIS) {
            launch {
                for (seg in synthQueue) {
                    if (!isActive) {
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

        // 播放消费者
        val ttsCallback = object : TtsCallback {
            override fun onSynthesisStart() { /* 由首段触发 */ }
            override fun onSynthesisReady(durationMs: Int) {
                eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "synthesisReady", durationMs = durationMs))
            }
            override fun onPlaybackStart() { /* 由首段触发 */ }
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
                    if (!isActive) break
                    try {
                        val audio = seg.audio.await()
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
                    }
                }
                if (firstSegmentEmitted.get() && isActive) {
                    eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "playbackDone"))
                }
            } catch (e: CancellationException) {
                throw e
            }
        }

        // 入队所有段（先 playQueue 后 synthQueue，锁定播放顺序）
        sentences.forEachIndexed { i, sentence ->
            if (firstSegmentEmitted.compareAndSet(false, true)) {
                eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "synthesisStart"))
                eventSink.onTtsEvent(TtsEventData(config.agentId, requestId, kind = "playbackStart"))
            }
            val item = TtsSegment(i, sentence, CompletableDeferred())
            playQueue.trySend(item)
            synthQueue.trySend(item)
        }

        synthQueue.close()
        synthWorkers.forEach { it.join() }
        playQueue.close()
        ttsConsumer.join()
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
        override fun onPartialResult(text: String, detectedLang: String?) {
            eventSink.onSttEvent(SttEventData(
                config.agentId, requestId = "", kind = "partialResult",
                text = text, detectedLang = detectedLang,
            ))
        }
        override fun onFinalResult(text: String) {
            // 厂商未提供 detectedLang 时进入此路径
            handleFinal(text, detectedLang = null)
        }
        override fun onFinalResult(text: String, detectedLang: String?) {
            handleFinal(text, detectedLang)
        }

        private fun handleFinal(text: String, detectedLang: String?) {
            // 暂存供 push-to-talk 路径下的 sendText 消费（call 模式直接走下面分支也用到）
            lastSttDetectedLang = detectedLang
            val reqId = UUID.randomUUID().toString()
            eventSink.onSttEvent(SttEventData(
                config.agentId, requestId = reqId, kind = "finalResult",
                text = text, detectedLang = detectedLang,
            ))
            // call 模式：自动触发翻译管线，方向按 bidirectional + detectedLang 解算。
            // 进 FIFO 队列，连续多个 finalResult 顺序处理，互不打断。
            if (inputMode == "call") {
                lastSttDetectedLang = null  // 由队列消费者直接消费 detectedLang
                enqueueTranslation(reqId, text, resolveDirection(detectedLang))
            }
        }
        override fun onVadSpeechStart() {
            eventSink.onSttEvent(SttEventData(config.agentId, requestId = "", kind = "vadSpeechStart"))
            // 翻译 agent 永不因 VAD 抢占：所有路径都进 FIFO 队列顺序处理，
            // "换一句话"意味着排队，不是打断。
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

    private fun startContinuousListening() {
        if (externalAudioActive) {
            Log.d(TAG, "startContinuousListening skipped: external audio active")
            transitionTo(State.LISTENING)
            return
        }
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
}
