package com.aiagent.plugin_interface

/**
 * Agent 事件回调接口
 *
 * 由 agents_server 的 AgentsServerPlugin 实现，
 * 接收来自各 Agent 类型插件的事件，转发给 Flutter EventChannel。
 */
interface AgentEventSink {
    fun onSttEvent(event: SttEventData)
    fun onLlmEvent(event: LlmEventData)
    fun onTtsEvent(event: TtsEventData)
    fun onStateChanged(sessionId: String, state: String, requestId: String?)
    fun onError(sessionId: String, errorCode: String, message: String, requestId: String?)
}
