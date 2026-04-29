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

    /** 端到端连接状态变化（disconnected / connecting / connected / error） */
    fun onConnectionStateChanged(sessionId: String, state: String, errorMessage: String? = null)

    /**
     * Agent 就绪回调（统一替代"等 connected"的协议）。
     *
     * 每次 [NativeAgent.connectService] 调用后，agent 必须最终派发恰好一次：
     *  - ready=true  : 三段式 = 服务初始化完成；端到端 = 链路 connected
     *  - ready=false : errorCode/errorMessage 必填，编排器据此终止流程
     *
     * disconnect/release 后再次 connect 才会重新派发。
     */
    fun onAgentReady(
        sessionId: String,
        ready: Boolean,
        errorCode: String? = null,
        errorMessage: String? = null,
    )
}
