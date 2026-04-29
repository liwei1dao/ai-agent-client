package com.aiagent.translate_server

/**
 * translate_server → Flutter EventChannel 的事件 payload 工厂。
 *
 * 所有事件统一带 `type` 字段。Flutter 端按 `type` 分派：
 *  - `subtitle`       : 字幕，必带 `leg` (uplink/downlink/media) + `stage` (partial/final) + `sourceText`
 *  - `sessionState`   : `state` ∈ starting / active / stopping / stopped / error
 *  - `error`          : `code` + `message` + 可选 `leg`
 *  - `connectionState`: agent 端到端服务连接状态（uplink/downlink 各自）
 */
internal object TranslateEvents {

    fun subtitle(
        sessionId: String,
        leg: String,
        stage: String,
        sourceText: String,
        translatedText: String? = null,
        sourceLanguage: String? = null,
        destLanguage: String? = null,
        requestId: String? = null,
    ): Map<String, Any?> = mapOf(
        "type" to "subtitle",
        "sessionId" to sessionId,
        "leg" to leg,
        "stage" to stage,
        "sourceText" to sourceText,
        "translatedText" to translatedText,
        "sourceLanguage" to sourceLanguage,
        "destLanguage" to destLanguage,
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
        leg: String? = null,
        fatal: Boolean = false,
    ): Map<String, Any?> = mapOf(
        "type" to "error",
        "sessionId" to sessionId,
        "code" to code,
        "message" to message,
        "leg" to leg,
        "fatal" to fatal,
    )

    fun connectionState(
        sessionId: String,
        leg: String,
        state: String,
        errorMessage: String? = null,
    ): Map<String, Any?> = mapOf(
        "type" to "connectionState",
        "sessionId" to sessionId,
        "leg" to leg,
        "state" to state,
        "errorMessage" to errorMessage,
    )
}

/**
 * 通话翻译的两条 leg。uplink = 用户说→对方听；downlink = 对方说→用户听。
 */
internal enum class CallLeg(val wireName: String) {
    UPLINK("uplink"),
    DOWNLINK("downlink"),
}
