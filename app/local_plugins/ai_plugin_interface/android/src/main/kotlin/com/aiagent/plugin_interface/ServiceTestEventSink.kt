package com.aiagent.plugin_interface

/**
 * 服务测试事件回调接口
 *
 * 由 services_mgr 的 ServicesMgrPlugin 实现，
 * 接收来自 ServiceTestRunner 的测试事件，转发给 Flutter EventChannel。
 *
 * 对应 AgentEventSink 在 agents_server 中的角色。
 */
interface ServiceTestEventSink {
    fun onSttTestEvent(testId: String, kind: String, text: String? = null, errorCode: String? = null, errorMessage: String? = null)
    fun onTtsTestEvent(testId: String, kind: String, progressMs: Int? = null, durationMs: Int? = null, errorCode: String? = null, errorMessage: String? = null)
    fun onLlmTestEvent(testId: String, kind: String, textDelta: String? = null, thinkingDelta: String? = null, toolCallId: String? = null, toolName: String? = null, toolArgumentsDelta: String? = null, toolResult: String? = null, fullText: String? = null, errorCode: String? = null, errorMessage: String? = null)
    fun onTranslationTestEvent(testId: String, kind: String, sourceText: String? = null, translatedText: String? = null, sourceLanguage: String? = null, targetLanguage: String? = null, errorCode: String? = null, errorMessage: String? = null)
    fun onStsTestEvent(testId: String, kind: String, text: String? = null, state: String? = null, errorCode: String? = null, errorMessage: String? = null)
    fun onAstTestEvent(testId: String, kind: String, text: String? = null, state: String? = null, errorCode: String? = null, errorMessage: String? = null)
    fun onTestDone(testId: String, success: Boolean, message: String? = null)
}
