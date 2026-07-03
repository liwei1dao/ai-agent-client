import Foundation

/// translate_server → Flutter EventChannel 的事件 payload 工厂。
enum TranslateEvents {

    static func subtitle(
        sessionId: String, leg: String, stage: String,
        sourceText: String, translatedText: String? = nil,
        sourceLanguage: String? = nil, destLanguage: String? = nil,
        requestId: String? = nil
    ) -> [String: Any?] {
        return [
            "type": "subtitle",
            "sessionId": sessionId,
            "leg": leg,
            "stage": stage,
            "sourceText": sourceText,
            "translatedText": translatedText,
            "sourceLanguage": sourceLanguage,
            "destLanguage": destLanguage,
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
        leg: String? = nil, fatal: Bool = false
    ) -> [String: Any?] {
        return [
            "type": "error",
            "sessionId": sessionId,
            "code": code,
            "message": message,
            "leg": leg,
            "fatal": fatal,
        ]
    }

    static func connectionState(
        sessionId: String, leg: String, state: String,
        errorMessage: String? = nil
    ) -> [String: Any?] {
        return [
            "type": "connectionState",
            "sessionId": sessionId,
            "leg": leg,
            "state": state,
            "errorMessage": errorMessage,
        ]
    }
}

/// uplink = 用户说→对方听；downlink = 对方说→用户听。
enum CallLeg: String {
    case uplink = "uplink"
    case downlink = "downlink"
}
