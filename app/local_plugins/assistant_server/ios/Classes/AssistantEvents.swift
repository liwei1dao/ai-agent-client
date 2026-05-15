import Foundation

/// assistant_server → Flutter EventChannel 的事件 payload 工厂。
///
/// 所有事件统一带 `type` 字段。Flutter 端按 `type` 分派：
///  - `message`        : 对话消息，必带 `role` (user/assistant) + `stage` (partial/final) + `text`
///  - `sessionState`   : `state` ∈ starting / active / stopping / stopped / error
///  - `error`          : `code` + `message` + 可选 `role`
///  - `connectionState`: agent 端到端服务连接状态
enum AssistantEvents {

    static func message(
        sessionId: String, role: String, stage: String,
        text: String, requestId: String? = nil
    ) -> [String: Any?] {
        return [
            "type": "message",
            "sessionId": sessionId,
            "role": role,
            "stage": stage,
            "text": text,
            "requestId": requestId,
        ]
    }

    static func sessionState(
        sessionId: String, state: String, errorMessage: String? = nil
    ) -> [String: Any?] {
        return [
            "type": "sessionState",
            "sessionId": sessionId,
            "state": state,
            "errorMessage": errorMessage,
        ]
    }

    static func error(
        sessionId: String, code: String, message: String,
        role: String? = nil, fatal: Bool = false
    ) -> [String: Any?] {
        return [
            "type": "error",
            "sessionId": sessionId,
            "code": code,
            "message": message,
            "role": role,
            "fatal": fatal,
        ]
    }

    static func connectionState(
        sessionId: String, state: String, errorMessage: String? = nil
    ) -> [String: Any?] {
        return [
            "type": "connectionState",
            "sessionId": sessionId,
            "state": state,
            "errorMessage": errorMessage,
        ]
    }
}

/// AI 助理的对话角色。user = 戴耳机的本机用户；assistant = AI 回复。
enum AssistantRole: String {
    case user = "user"
    case assistant = "assistant"
}
