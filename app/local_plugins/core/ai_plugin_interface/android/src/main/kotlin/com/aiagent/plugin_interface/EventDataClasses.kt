package com.aiagent.plugin_interface

/**
 * STT 事件数据（Native → AgentEventSink → EventChannel → Flutter）
 */
data class SttEventData(
    val sessionId: String,
    val requestId: String,
    val kind: String,           // listeningStarted, vadSpeechStart, vadSpeechEnd, partialResult, finalResult, listeningStopped, error
    val text: String? = null,
    val detectedLang: String? = null,  // BCP-47 语言码（厂商支持语言检测时填）
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

/**
 * LLM 事件数据
 */
data class LlmEventData(
    val sessionId: String,
    val requestId: String,
    val kind: String,           // thinking, firstToken, toolCallStart, toolCallArguments, toolCallResult, done, cancelled, error
    val textDelta: String? = null,
    val thinkingDelta: String? = null,
    val toolCallId: String? = null,
    val toolName: String? = null,
    val toolArgumentsDelta: String? = null,
    val toolResult: String? = null,
    val fullText: String? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

/**
 * TTS 事件数据
 */
data class TtsEventData(
    val sessionId: String,
    val requestId: String,
    val kind: String,           // synthesisStart, synthesisReady, playbackStart, playbackProgress, playbackDone, playbackInterrupted, error
    val progressMs: Int? = null,
    val durationMs: Int? = null,
    val errorCode: String? = null,
    val errorMessage: String? = null,
)

/**
 * 翻译结果
 */
data class NativeTranslationResult(
    val sourceText: String,
    val translatedText: String,
    val sourceLanguage: String,
    val targetLanguage: String,
)
