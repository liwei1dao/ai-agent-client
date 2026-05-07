package com.aiagent.assistant_server

/**
 * assistant_server → Flutter EventChannel 的事件 payload 工厂。
 *
 * 所有事件统一带 `type` 字段。Flutter 端按 `type` 分派：
 *  - `message`        : 对话消息，必带 `role` (user/assistant) + `stage` (partial/final) + `text`
 *  - `sessionState`   : `state` ∈ starting / active / stopping / stopped / error
 *  - `error`          : `code` + `message` + 可选 `role`
 *  - `connectionState`: agent 端到端服务连接状态
 */
internal object AssistantEvents {

    fun message(
        sessionId: String,
        role: String,
        stage: String,
        text: String,
        requestId: String? = null,
    ): Map<String, Any?> = mapOf(
        "type" to "message",
        "sessionId" to sessionId,
        "role" to role,
        "stage" to stage,
        "text" to text,
        "requestId" to requestId,
    )

    fun sessionState(sessionId: String, state: String, errorMessage: String? = null): Map<String, Any?> =
        mapOf(
            "type" to "sessionState",
            "sessionId" to sessionId,
            "state" to state,
            "errorMessage" to errorMessage,
        )

    fun error(
        sessionId: String,
        code: String,
        message: String,
        role: String? = null,
        fatal: Boolean = false,
    ): Map<String, Any?> = mapOf(
        "type" to "error",
        "sessionId" to sessionId,
        "code" to code,
        "message" to message,
        "role" to role,
        "fatal" to fatal,
    )

    fun connectionState(
        sessionId: String,
        state: String,
        errorMessage: String? = null,
    ): Map<String, Any?> = mapOf(
        "type" to "connectionState",
        "sessionId" to sessionId,
        "state" to state,
        "errorMessage" to errorMessage,
    )
}

/**
 * AI 助理的对话角色。user = 戴耳机的本机用户；assistant = AI 回复。
 */
internal enum class AssistantRole(val wireName: String) {
    USER("user"),
    ASSISTANT("assistant"),
}
