package com.aiagent.service_manager

import android.content.Context
import android.util.Log
import com.aiagent.local_db.AppDatabase
import com.aiagent.plugin_interface.*
import kotlinx.coroutines.*

/**
 * ServiceTestRunner — 服务测试执行器
 *
 * 职责：
 * 1. 根据 serviceId 从 DB 加载配置
 * 2. 通过 NativeServiceRegistry 创建对应的服务实例
 * 3. 执行测试逻辑，通过 ServiceTestEventSink 推送标准化事件
 * 4. 管理测试会话的生命周期（启动/停止/释放）
 */
class ServiceTestRunner(
    private val context: Context,
    private val eventSink: ServiceTestEventSink,
) {
    companion object {
        private const val TAG = "ServiceTestRunner"

        // ── 自动化测试参数 ──
        private const val AUTO_TEST_STT_DURATION_MS = 5000L       // STT 录音时长
        private const val AUTO_TEST_TTS_TEXT = "你好，这是一条语音合成测试。"
        private const val AUTO_TEST_LLM_PROMPT = "你好，请用一句话介绍你自己。"
        private const val AUTO_TEST_TRANSLATION_TEXT = "你好，世界"
        private const val AUTO_TEST_TRANSLATION_TARGET = "en"     // 翻译目标语言
        private const val AUTO_TEST_STS_DURATION_MS = 5000L       // STS 通话测试时长
        private const val AUTO_TEST_AST_DURATION_MS = 5000L       // AST 通话测试时长
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val db = AppDatabase.getInstance(context)

    // 活跃的测试会话: testId → TestSession
    private val sessions = mutableMapOf<String, TestSession>()

    private sealed class TestSession {
        abstract fun release()

        class SttSession(val service: NativeSttService) : TestSession() {
            override fun release() { service.stopListening(); service.release() }
        }

        class TtsSession(val service: NativeTtsService, val job: Job?) : TestSession() {
            override fun release() { job?.cancel(); service.stop(); service.release() }
        }

        class LlmSession(val service: NativeLlmService, val job: Job?) : TestSession() {
            override fun release() { job?.cancel(); service.cancel() }
        }

        class TranslationSession(val service: NativeTranslationService, val job: Job?) : TestSession() {
            override fun release() { job?.cancel(); service.release() }
        }

        class StsSession(val service: NativeStsService) : TestSession() {
            override fun release() { service.release() }
        }

        class AstSession(val service: NativeAstService) : TestSession() {
            override fun release() { service.release() }
        }
    }

    // ─────────────────────────────────────────────────
    // STT 测试
    // ─────────────────────────────────────────────────

    fun testSttStart(testId: String, serviceId: String) {
        scope.launch {
            try {
                val config = loadServiceConfig(serviceId) ?: return@launch
                val service = NativeServiceRegistry.createStt(config.vendor)
                service.initialize(config.configJson, context)

                releaseSession(testId)
                sessions[testId] = TestSession.SttSession(service)

                service.startListening(object : SttCallback {
                    override fun onListeningStarted() =
                        eventSink.onSttTestEvent(testId, "listeningStarted")
                    override fun onPartialResult(text: String) =
                        eventSink.onSttTestEvent(testId, "partialResult", text = text)
                    override fun onFinalResult(text: String) =
                        eventSink.onSttTestEvent(testId, "finalResult", text = text)
                    override fun onVadSpeechStart() =
                        eventSink.onSttTestEvent(testId, "vadSpeechStart")
                    override fun onVadSpeechEnd() =
                        eventSink.onSttTestEvent(testId, "vadSpeechEnd")
                    override fun onListeningStopped() =
                        eventSink.onSttTestEvent(testId, "listeningStopped")
                    override fun onError(code: String, message: String) =
                        eventSink.onSttTestEvent(testId, "error", errorCode = code, errorMessage = message)
                })
            } catch (e: Exception) {
                Log.e(TAG, "testSttStart error: ${e.message}", e)
                eventSink.onSttTestEvent(testId, "error", errorCode = "init_error", errorMessage = e.message)
            }
        }
    }

    fun testSttStop(testId: String) {
        (sessions[testId] as? TestSession.SttSession)?.service?.stopListening()
    }

    // ─────────────────────────────────────────────────
    // TTS 测试
    // ─────────────────────────────────────────────────

    fun testTtsSpeak(testId: String, serviceId: String, text: String, voiceName: String?, speed: Double, pitch: Double) {
        scope.launch {
            try {
                val config = loadServiceConfig(serviceId) ?: return@launch
                // 合并额外参数到 configJson
                val mergedConfig = mergeConfig(config.configJson, mapOfNotNull(
                    "voiceName" to voiceName,
                    "speed" to speed.toString(),
                    "pitch" to pitch.toString(),
                ))
                val service = NativeServiceRegistry.createTts(config.vendor)
                service.initialize(mergedConfig, context)

                releaseSession(testId)
                val job = scope.launch {
                    service.speak("tts_$testId", text, object : TtsCallback {
                        override fun onSynthesisStart() =
                            eventSink.onTtsTestEvent(testId, "synthesisStart")
                        override fun onSynthesisReady(durationMs: Int) =
                            eventSink.onTtsTestEvent(testId, "synthesisReady", durationMs = durationMs)
                        override fun onPlaybackStart() =
                            eventSink.onTtsTestEvent(testId, "playbackStart")
                        override fun onPlaybackProgress(progressMs: Int) =
                            eventSink.onTtsTestEvent(testId, "playbackProgress", progressMs = progressMs)
                        override fun onPlaybackDone() {
                            eventSink.onTtsTestEvent(testId, "playbackDone")
                            eventSink.onTestDone(testId, success = true)
                        }
                        override fun onPlaybackInterrupted() =
                            eventSink.onTtsTestEvent(testId, "playbackInterrupted")
                        override fun onError(code: String, message: String) =
                            eventSink.onTtsTestEvent(testId, "error", errorCode = code, errorMessage = message)
                    })
                }
                sessions[testId] = TestSession.TtsSession(service, job)
            } catch (e: Exception) {
                Log.e(TAG, "testTtsSpeak error: ${e.message}", e)
                eventSink.onTtsTestEvent(testId, "error", errorCode = "init_error", errorMessage = e.message)
            }
        }
    }

    fun testTtsStop(testId: String) {
        (sessions[testId] as? TestSession.TtsSession)?.let {
            it.service.stop()
            it.job?.cancel()
        }
    }

    // ─────────────────────────────────────────────────
    // LLM 测试
    // ─────────────────────────────────────────────────

    fun testLlmChat(testId: String, serviceId: String, text: String) {
        scope.launch {
            try {
                val config = loadServiceConfig(serviceId) ?: return@launch
                val service = NativeServiceRegistry.createLlm(config.vendor)
                service.initialize(config.configJson)

                releaseSession(testId)
                val job = scope.launch {
                    try {
                        service.chat(
                            requestId = "llm_$testId",
                            messages = listOf(mapOf("role" to "user", "content" to text)),
                            tools = emptyList(),
                            callback = object : LlmCallback {
                                override fun onFirstToken(textDelta: String) =
                                    eventSink.onLlmTestEvent(testId, "firstToken", textDelta = textDelta)
                                override fun onTextDelta(textDelta: String) =
                                    eventSink.onLlmTestEvent(testId, "textDelta", textDelta = textDelta)
                                override fun onThinkingDelta(delta: String) =
                                    eventSink.onLlmTestEvent(testId, "thinking", thinkingDelta = delta)
                                override fun onToolCallStart(id: String, name: String) =
                                    eventSink.onLlmTestEvent(testId, "toolCallStart", toolCallId = id, toolName = name)
                                override fun onToolCallArguments(delta: String) =
                                    eventSink.onLlmTestEvent(testId, "toolCallArguments", toolArgumentsDelta = delta)
                                override fun onToolCallResult(result: String) =
                                    eventSink.onLlmTestEvent(testId, "toolCallResult", toolResult = result)
                                override fun onDone(fullText: String) {
                                    eventSink.onLlmTestEvent(testId, "done", fullText = fullText)
                                    eventSink.onTestDone(testId, success = true)
                                }
                                override fun onError(code: String, message: String) =
                                    eventSink.onLlmTestEvent(testId, "error", errorCode = code, errorMessage = message)
                            },
                        )
                    } catch (e: CancellationException) {
                        eventSink.onLlmTestEvent(testId, "cancelled")
                    }
                }
                sessions[testId] = TestSession.LlmSession(service, job)
            } catch (e: Exception) {
                Log.e(TAG, "testLlmChat error: ${e.message}", e)
                eventSink.onLlmTestEvent(testId, "error", errorCode = "init_error", errorMessage = e.message)
            }
        }
    }

    fun testLlmCancel(testId: String) {
        (sessions[testId] as? TestSession.LlmSession)?.let {
            it.service.cancel()
            it.job?.cancel()
        }
    }

    // ─────────────────────────────────────────────────
    // Translation 测试
    // ─────────────────────────────────────────────────

    fun testTranslate(testId: String, serviceId: String, text: String, targetLang: String, sourceLang: String?) {
        scope.launch {
            try {
                val config = loadServiceConfig(serviceId) ?: return@launch
                val service = NativeServiceRegistry.createTranslation(config.vendor)
                service.initialize(config.configJson)

                releaseSession(testId)
                val job = scope.launch {
                    try {
                        val result = service.translate(text, targetLang, sourceLang)
                        eventSink.onTranslationTestEvent(
                            testId, "result",
                            sourceText = result.sourceText,
                            translatedText = result.translatedText,
                            sourceLanguage = result.sourceLanguage,
                            targetLanguage = result.targetLanguage,
                        )
                        eventSink.onTestDone(testId, success = true)
                    } catch (e: Exception) {
                        eventSink.onTranslationTestEvent(testId, "error",
                            errorCode = "translate_error", errorMessage = e.message)
                    }
                }
                sessions[testId] = TestSession.TranslationSession(service, job)
            } catch (e: Exception) {
                Log.e(TAG, "testTranslate error: ${e.message}", e)
                eventSink.onTranslationTestEvent(testId, "error",
                    errorCode = "init_error", errorMessage = e.message)
            }
        }
    }

    // ─────────────────────────────────────────────────
    // STS 测试
    // ─────────────────────────────────────────────────

    fun testStsConnect(testId: String, serviceId: String) {
        scope.launch {
            try {
                val config = loadServiceConfig(serviceId) ?: return@launch
                val service = NativeServiceRegistry.createSts(config.vendor)
                service.initialize(config.configJson, context)

                releaseSession(testId)
                sessions[testId] = TestSession.StsSession(service)

                service.connect(object : StsCallback {
                    override fun onConnected() =
                        eventSink.onStsTestEvent(testId, "connected")
                    override fun onSttPartialResult(text: String) =
                        eventSink.onStsTestEvent(testId, "sttPartialResult", text = text)
                    override fun onSttFinalResult(text: String) =
                        eventSink.onStsTestEvent(testId, "sttFinalResult", text = text)
                    override fun onTtsAudioChunk(pcmData: ByteArray) { /* 底层自行播放 */ }
                    override fun onSentenceDone(text: String) =
                        eventSink.onStsTestEvent(testId, "sentenceDone", text = text)
                    override fun onDisconnected() =
                        eventSink.onStsTestEvent(testId, "disconnected")
                    override fun onError(code: String, message: String) =
                        eventSink.onStsTestEvent(testId, "error", errorCode = code, errorMessage = message)
                    override fun onSpeechStart() =
                        eventSink.onStsTestEvent(testId, "speechStart")
                    override fun onStateChanged(state: String) =
                        eventSink.onStsTestEvent(testId, "stateChanged", state = state)
                })
            } catch (e: Exception) {
                Log.e(TAG, "testStsConnect error: ${e.message}", e)
                eventSink.onStsTestEvent(testId, "error", errorCode = "init_error", errorMessage = e.message)
            }
        }
    }

    fun testStsStartAudio(testId: String) {
        (sessions[testId] as? TestSession.StsSession)?.service?.startAudio()
    }

    fun testStsStopAudio(testId: String) {
        (sessions[testId] as? TestSession.StsSession)?.service?.stopAudio()
    }

    fun testStsDisconnect(testId: String) {
        releaseSession(testId)
    }

    // ─────────────────────────────────────────────────
    // AST 测试
    // ─────────────────────────────────────────────────

    fun testAstConnect(testId: String, serviceId: String, extraConfigJson: String? = null) {
        scope.launch {
            try {
                val config = loadServiceConfig(serviceId) ?: return@launch
                val mergedJson = mergeConfigOverride(config.configJson, extraConfigJson)
                val service = NativeServiceRegistry.createAst(config.vendor)
                service.initialize(mergedJson, context)

                releaseSession(testId)
                sessions[testId] = TestSession.AstSession(service)

                service.connect(buildAstTestCallback(testId))
            } catch (e: Exception) {
                Log.e(TAG, "testAstConnect error: ${e.message}", e)
                eventSink.onAstTestEvent(testId, "error", errorCode = "init_error", errorMessage = e.message)
            }
        }
    }

    /** 与 [mergeConfig] 不同：本方法**覆盖**已有键，专供测试面板临时改 srcLang/dstLang/agentId。 */
    private fun mergeConfigOverride(configJson: String, extraJson: String?): String {
        if (extraJson.isNullOrBlank()) return configJson
        return try {
            val base = org.json.JSONObject(configJson)
            val extra = org.json.JSONObject(extraJson)
            val keys = extra.keys()
            while (keys.hasNext()) {
                val k = keys.next()
                base.put(k, extra.get(k))
            }
            base.toString()
        } catch (_: Exception) {
            configJson
        }
    }

    fun testAstStartAudio(testId: String) {
        (sessions[testId] as? TestSession.AstSession)?.service?.startAudio()
    }

    fun testAstStopAudio(testId: String) {
        (sessions[testId] as? TestSession.AstSession)?.service?.stopAudio()
    }

    fun testAstDisconnect(testId: String) {
        releaseSession(testId)
    }

    /**
     * Helper that maps the AST recognition five-piece lifecycle back onto the
     * legacy test event vocabulary (sourceSubtitle / translatedSubtitle) so the
     * test panel keeps working without change.
     */
    private fun buildAstTestCallback(
        testId: String,
        onConnectedExtra: (() -> Unit)? = null,
        onErrorExtra: ((String, String) -> Unit)? = null,
    ): AstCallback = object : AstCallback {
        override fun onConnected() {
            eventSink.onAstTestEvent(testId, "connected")
            onConnectedExtra?.invoke()
        }

        override fun onDisconnected() {
            eventSink.onAstTestEvent(testId, "disconnected")
        }

        override fun onRecognitionStart(role: AstRole, requestId: String) { /* no-op */ }

        override fun onRecognizing(role: AstRole, requestId: String, text: String) {
            val kind = if (role == AstRole.TRANSLATED) "translatedSubtitle" else "sourceSubtitle"
            eventSink.onAstTestEvent(testId, kind, text = text)
        }

        override fun onRecognized(role: AstRole, requestId: String, text: String) {
            val kind = if (role == AstRole.TRANSLATED) "translatedSubtitle" else "sourceSubtitle"
            eventSink.onAstTestEvent(testId, kind, text = text)
        }

        override fun onRecognitionDone(role: AstRole, requestId: String) { /* no-op */ }

        override fun onRecognitionEnd(requestId: String) { /* no-op */ }

        override fun onRecognitionError(requestId: String?, role: AstRole?, code: String, message: String) {
            eventSink.onAstTestEvent(testId, "error", errorCode = code, errorMessage = message)
        }

        override fun onError(code: String, message: String) {
            eventSink.onAstTestEvent(testId, "error", errorCode = code, errorMessage = message)
            onErrorExtra?.invoke(code, message)
        }
    }

    // ─────────────────────────────────────────────────
    // 自动化测试（一键完成完整流程）
    // ─────────────────────────────────────────────────

    /**
     * 自动化测试入口：根据服务类型自动执行完整测试流程。
     *
     * - STT:  打开麦克风 → 录 [sttDurationSec] 秒 → 停止 → 检查是否有识别结果
     * - TTS:  合成预设文本 → 等待播放完成
     * - LLM:  发送预设问题 → 等待回复完成
     * - Translation: 翻译预设文本 → 等待结果
     * - STS:  连接 → 开始音频 → 等 [stsDurationSec] 秒 → 停止 → 断开
     * - AST:  连接 → 开始音频 → 等 [astDurationSec] 秒 → 停止 → 断开
     *
     * 测试过程中会正常推送中间事件，最后通过 onTestDone 报告结果。
     */
    fun autoTest(testId: String, serviceId: String) {
        scope.launch {
            val config = loadServiceConfig(serviceId)
            if (config == null) {
                eventSink.onTestDone(testId, success = false, message = "找不到服务配置: $serviceId")
                return@launch
            }
            try {
                when (config.type) {
                    "stt" -> autoTestStt(testId, config)
                    "tts" -> autoTestTts(testId, config)
                    "llm" -> autoTestLlm(testId, config)
                    "translation" -> autoTestTranslation(testId, config)
                    "sts" -> autoTestSts(testId, config)
                    "ast" -> autoTestAst(testId, config)
                    else -> eventSink.onTestDone(testId, success = false, message = "不支持的服务类型: ${config.type}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "autoTest error: ${e.message}", e)
                eventSink.onTestDone(testId, success = false, message = e.message)
            }
        }
    }

    private suspend fun autoTestStt(testId: String, config: ServiceConfig) {
        val service = NativeServiceRegistry.createStt(config.vendor)
        service.initialize(config.configJson, context)

        releaseSession(testId)
        sessions[testId] = TestSession.SttSession(service)

        val startTime = System.currentTimeMillis()
        var gotResult = false
        var resultText = ""
        var errorMsg: String? = null
        val latch = CompletableDeferred<Unit>()

        service.startListening(object : SttCallback {
            override fun onListeningStarted() =
                eventSink.onSttTestEvent(testId, "listeningStarted")
            override fun onPartialResult(text: String) =
                eventSink.onSttTestEvent(testId, "partialResult", text = text)
            override fun onFinalResult(text: String) {
                eventSink.onSttTestEvent(testId, "finalResult", text = text)
                gotResult = true
                resultText = text
            }
            override fun onVadSpeechStart() =
                eventSink.onSttTestEvent(testId, "vadSpeechStart")
            override fun onVadSpeechEnd() =
                eventSink.onSttTestEvent(testId, "vadSpeechEnd")
            override fun onListeningStopped() {
                eventSink.onSttTestEvent(testId, "listeningStopped")
                latch.complete(Unit)
            }
            override fun onError(code: String, message: String) {
                eventSink.onSttTestEvent(testId, "error", errorCode = code, errorMessage = message)
                errorMsg = message
                latch.complete(Unit)
            }
        })

        // 等待最多 5 秒录音
        delay(AUTO_TEST_STT_DURATION_MS)
        service.stopListening()

        // 等待 listeningStopped 或 error 回调
        withTimeoutOrNull(3000) { latch.await() }

        val latency = System.currentTimeMillis() - startTime
        releaseSession(testId)

        if (errorMsg != null) {
            eventSink.onTestDone(testId, success = false, message = "STT 错误: $errorMsg (${latency}ms)")
        } else {
            val msg = if (gotResult) "识别结果: $resultText" else "未检测到语音"
            eventSink.onTestDone(testId, success = true, message = "$msg (${latency}ms)")
        }
    }

    private suspend fun autoTestTts(testId: String, config: ServiceConfig) {
        val service = NativeServiceRegistry.createTts(config.vendor)
        service.initialize(config.configJson, context)

        releaseSession(testId)
        val startTime = System.currentTimeMillis()
        var errorMsg: String? = null
        val latch = CompletableDeferred<Boolean>()

        val job = scope.launch {
            try {
                service.speak("auto_tts_$testId", AUTO_TEST_TTS_TEXT, object : TtsCallback {
                    override fun onSynthesisStart() =
                        eventSink.onTtsTestEvent(testId, "synthesisStart")
                    override fun onSynthesisReady(durationMs: Int) =
                        eventSink.onTtsTestEvent(testId, "synthesisReady", durationMs = durationMs)
                    override fun onPlaybackStart() =
                        eventSink.onTtsTestEvent(testId, "playbackStart")
                    override fun onPlaybackProgress(progressMs: Int) =
                        eventSink.onTtsTestEvent(testId, "playbackProgress", progressMs = progressMs)
                    override fun onPlaybackDone() {
                        eventSink.onTtsTestEvent(testId, "playbackDone")
                        latch.complete(true)
                    }
                    override fun onPlaybackInterrupted() {
                        eventSink.onTtsTestEvent(testId, "playbackInterrupted")
                        latch.complete(true)
                    }
                    override fun onError(code: String, message: String) {
                        eventSink.onTtsTestEvent(testId, "error", errorCode = code, errorMessage = message)
                        errorMsg = message
                        latch.complete(false)
                    }
                })
            } catch (e: CancellationException) {
                latch.complete(false)
            }
        }
        sessions[testId] = TestSession.TtsSession(service, job)

        // 等待播放完成，最多 30 秒
        val ok = withTimeoutOrNull(30_000) { latch.await() } ?: false
        val latency = System.currentTimeMillis() - startTime
        releaseSession(testId)

        if (errorMsg != null) {
            eventSink.onTestDone(testId, success = false, message = "TTS 错误: $errorMsg (${latency}ms)")
        } else {
            eventSink.onTestDone(testId, success = ok, message = "合成+播放完成 (${latency}ms)")
        }
    }

    private suspend fun autoTestLlm(testId: String, config: ServiceConfig) {
        val service = NativeServiceRegistry.createLlm(config.vendor)
        service.initialize(config.configJson)

        releaseSession(testId)
        val startTime = System.currentTimeMillis()
        var firstTokenTime: Long? = null

        val job = scope.launch {
            try {
                val fullText = service.chat(
                    requestId = "auto_llm_$testId",
                    messages = listOf(mapOf("role" to "user", "content" to AUTO_TEST_LLM_PROMPT)),
                    tools = emptyList(),
                    callback = object : LlmCallback {
                        override fun onFirstToken(textDelta: String) {
                            firstTokenTime = System.currentTimeMillis() - startTime
                            eventSink.onLlmTestEvent(testId, "firstToken", textDelta = textDelta)
                        }
                        override fun onTextDelta(textDelta: String) =
                            eventSink.onLlmTestEvent(testId, "textDelta", textDelta = textDelta)
                        override fun onThinkingDelta(delta: String) =
                            eventSink.onLlmTestEvent(testId, "thinking", thinkingDelta = delta)
                        override fun onToolCallStart(id: String, name: String) =
                            eventSink.onLlmTestEvent(testId, "toolCallStart", toolCallId = id, toolName = name)
                        override fun onToolCallArguments(delta: String) =
                            eventSink.onLlmTestEvent(testId, "toolCallArguments", toolArgumentsDelta = delta)
                        override fun onToolCallResult(result: String) =
                            eventSink.onLlmTestEvent(testId, "toolCallResult", toolResult = result)
                        override fun onDone(fullText: String) =
                            eventSink.onLlmTestEvent(testId, "done", fullText = fullText)
                        override fun onError(code: String, message: String) =
                            eventSink.onLlmTestEvent(testId, "error", errorCode = code, errorMessage = message)
                    },
                )
                val latency = System.currentTimeMillis() - startTime
                val ttft = firstTokenTime?.let { "${it}ms" } ?: "N/A"
                releaseSession(testId)
                eventSink.onTestDone(testId, success = true,
                    message = "回复 ${fullText.length} 字 | 首token $ttft | 总耗时 ${latency}ms")
            } catch (e: CancellationException) {
                releaseSession(testId)
                eventSink.onTestDone(testId, success = false, message = "已取消")
            } catch (e: Exception) {
                val latency = System.currentTimeMillis() - startTime
                releaseSession(testId)
                eventSink.onTestDone(testId, success = false, message = "LLM 错误: ${e.message} (${latency}ms)")
            }
        }
        sessions[testId] = TestSession.LlmSession(service, job)
    }

    private suspend fun autoTestTranslation(testId: String, config: ServiceConfig) {
        val service = NativeServiceRegistry.createTranslation(config.vendor)
        service.initialize(config.configJson)

        releaseSession(testId)
        val startTime = System.currentTimeMillis()

        try {
            val result = service.translate(AUTO_TEST_TRANSLATION_TEXT, AUTO_TEST_TRANSLATION_TARGET)
            val latency = System.currentTimeMillis() - startTime
            eventSink.onTranslationTestEvent(
                testId, "result",
                sourceText = result.sourceText,
                translatedText = result.translatedText,
                sourceLanguage = result.sourceLanguage,
                targetLanguage = result.targetLanguage,
            )
            service.release()
            eventSink.onTestDone(testId, success = true,
                message = "\"${result.translatedText}\" (${latency}ms)")
        } catch (e: Exception) {
            val latency = System.currentTimeMillis() - startTime
            service.release()
            eventSink.onTranslationTestEvent(testId, "error",
                errorCode = "translate_error", errorMessage = e.message)
            eventSink.onTestDone(testId, success = false, message = "翻译错误: ${e.message} (${latency}ms)")
        }
    }

    private suspend fun autoTestSts(testId: String, config: ServiceConfig) {
        val service = NativeServiceRegistry.createSts(config.vendor)
        service.initialize(config.configJson, context)

        releaseSession(testId)
        sessions[testId] = TestSession.StsSession(service)

        val startTime = System.currentTimeMillis()
        var connected = false
        var errorMsg: String? = null
        val connectLatch = CompletableDeferred<Boolean>()

        service.connect(object : StsCallback {
            override fun onConnected() {
                eventSink.onStsTestEvent(testId, "connected")
                connected = true
                connectLatch.complete(true)
            }
            override fun onSttPartialResult(text: String) =
                eventSink.onStsTestEvent(testId, "sttPartialResult", text = text)
            override fun onSttFinalResult(text: String) =
                eventSink.onStsTestEvent(testId, "sttFinalResult", text = text)
            override fun onTtsAudioChunk(pcmData: ByteArray) {}
            override fun onSentenceDone(text: String) =
                eventSink.onStsTestEvent(testId, "sentenceDone", text = text)
            override fun onDisconnected() =
                eventSink.onStsTestEvent(testId, "disconnected")
            override fun onError(code: String, message: String) {
                eventSink.onStsTestEvent(testId, "error", errorCode = code, errorMessage = message)
                errorMsg = message
                connectLatch.complete(false)
            }
            override fun onSpeechStart() =
                eventSink.onStsTestEvent(testId, "speechStart")
            override fun onStateChanged(state: String) =
                eventSink.onStsTestEvent(testId, "stateChanged", state = state)
        })

        // 等待连接建立
        val didConnect = withTimeoutOrNull(10_000) { connectLatch.await() } ?: false

        if (!didConnect) {
            val latency = System.currentTimeMillis() - startTime
            releaseSession(testId)
            eventSink.onTestDone(testId, success = false,
                message = "STS 连接失败: ${errorMsg ?: "超时"} (${latency}ms)")
            return
        }

        // 开始音频 → 等待一段时间 → 停止
        service.startAudio()
        delay(AUTO_TEST_STS_DURATION_MS)
        service.stopAudio()
        delay(500) // 等待最后的事件
        val latency = System.currentTimeMillis() - startTime
        releaseSession(testId)

        eventSink.onTestDone(testId, success = true,
            message = "STS 连接+通话测试完成 (${latency}ms)")
    }

    private suspend fun autoTestAst(testId: String, config: ServiceConfig) {
        val service = NativeServiceRegistry.createAst(config.vendor)
        service.initialize(config.configJson, context)

        releaseSession(testId)
        sessions[testId] = TestSession.AstSession(service)

        val startTime = System.currentTimeMillis()
        var connected = false
        var errorMsg: String? = null
        val connectLatch = CompletableDeferred<Boolean>()

        service.connect(buildAstTestCallback(
            testId,
            onConnectedExtra = {
                connected = true
                connectLatch.complete(true)
            },
            onErrorExtra = { _, message ->
                errorMsg = message
                connectLatch.complete(false)
            },
        ))

        // 等待连接建立
        val didConnect = withTimeoutOrNull(10_000) { connectLatch.await() } ?: false

        if (!didConnect) {
            val latency = System.currentTimeMillis() - startTime
            releaseSession(testId)
            eventSink.onTestDone(testId, success = false,
                message = "AST 连接失败: ${errorMsg ?: "超时"} (${latency}ms)")
            return
        }

        // 开始音频 → 等待一段时间 → 停止
        service.startAudio()
        delay(AUTO_TEST_AST_DURATION_MS)
        service.stopAudio()
        delay(500)
        val latency = System.currentTimeMillis() - startTime
        releaseSession(testId)

        eventSink.onTestDone(testId, success = true,
            message = "AST 连接+通话测试完成 (${latency}ms)")
    }

    // ─────────────────────────────────────────────────
    // 生命周期
    // ─────────────────────────────────────────────────

    fun releaseSession(testId: String) {
        sessions.remove(testId)?.release()
    }

    fun releaseAll() {
        sessions.values.forEach { it.release() }
        sessions.clear()
        scope.cancel()
    }

    // ─────────────────────────────────────────────────
    // 内部工具
    // ─────────────────────────────────────────────────

    private data class ServiceConfig(
        val id: String,
        val type: String,
        val vendor: String,
        val configJson: String,
    )

    private suspend fun loadServiceConfig(serviceId: String): ServiceConfig? {
        val entity = db.serviceConfigDao().getById(serviceId)
        if (entity == null) {
            Log.e(TAG, "Service config not found: $serviceId")
            return null
        }
        return ServiceConfig(entity.id, entity.type, entity.vendor, entity.configJson)
    }

    /** 将额外参数合并到 configJson（不覆盖已有值） */
    private fun mergeConfig(configJson: String, extra: Map<String, String>): String {
        return try {
            val json = org.json.JSONObject(configJson)
            for ((k, v) in extra) {
                if (v.isNotEmpty() && !json.has(k)) {
                    json.put(k, v)
                }
            }
            json.toString()
        } catch (_: Exception) {
            configJson
        }
    }

    private fun mapOfNotNull(vararg pairs: Pair<String, String?>): Map<String, String> {
        return pairs.filter { it.second != null }.associate { it.first to it.second!! }
    }
}
