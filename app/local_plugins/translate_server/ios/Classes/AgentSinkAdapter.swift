import Foundation
import ai_plugin_interface

/// 把翻译型 agent 的 [AgentEventSink] 事件转译成通话翻译统一字幕/状态/错误事件。
final class AgentSinkAdapter: AgentEventSink {

    private let sessionId: String
    private let leg: CallLeg
    private let emit: ([String: Any?]) -> Void

    private let readyLock = NSLock()
    private let readySem = DispatchSemaphore(value: 0)
    private var readyError: TranslateSessionError?
    private var readyArrived = false

    init(sessionId: String, leg: CallLeg, emit: @escaping ([String: Any?]) -> Void) {
        self.sessionId = sessionId
        self.leg = leg
        self.emit = emit
    }

    func awaitReady(timeout: TimeInterval) throws {
        readyLock.lock()
        if readyArrived {
            let err = readyError
            readyLock.unlock()
            if let err = err { throw err }
            return
        }
        readyLock.unlock()

        let result = readySem.wait(timeout: .now() + timeout)
        readyLock.lock()
        defer { readyLock.unlock() }
        if result == .timedOut && !readyArrived {
            readyArrived = true
            readyError = .connectTimeout
            throw TranslateSessionError.connectTimeout
        }
        if let err = readyError { throw err }
    }

    func onSttEvent(_ event: SttEventData) {
        switch event.kind {
        case "partialResult":
            emit(TranslateEvents.subtitle(
                sessionId: sessionId, leg: leg.rawValue, stage: "partial",
                sourceText: event.text ?? "", translatedText: nil, requestId: nil
            ))
        case "finalResult":
            guard !event.requestId.isEmpty else { return }
            emit(TranslateEvents.subtitle(
                sessionId: sessionId, leg: leg.rawValue, stage: "final",
                sourceText: event.text ?? "", translatedText: nil, requestId: event.requestId
            ))
        case "error":
            emit(TranslateEvents.error(
                sessionId: sessionId,
                code: event.errorCode ?? "stt.error",
                message: event.errorMessage ?? "stt error",
                leg: leg.rawValue
            ))
        default: break
        }
    }

    func onLlmEvent(_ event: LlmEventData) {
        switch event.kind {
        case "firstToken":
            guard !event.requestId.isEmpty else { return }
            emit(TranslateEvents.subtitle(
                sessionId: sessionId, leg: leg.rawValue, stage: "partial",
                sourceText: "", translatedText: event.textDelta ?? "", requestId: event.requestId
            ))
        case "done":
            guard !event.requestId.isEmpty else { return }
            emit(TranslateEvents.subtitle(
                sessionId: sessionId, leg: leg.rawValue, stage: "final",
                sourceText: "", translatedText: event.fullText ?? event.textDelta ?? "",
                requestId: event.requestId
            ))
        case "error":
            emit(TranslateEvents.error(
                sessionId: sessionId,
                code: event.errorCode ?? "llm.error",
                message: event.errorMessage ?? "llm error",
                leg: leg.rawValue
            ))
        default: break
        }
    }

    func onTtsEvent(_ event: TtsEventData) {
        if event.kind == "error" {
            emit(TranslateEvents.error(
                sessionId: sessionId,
                code: event.errorCode ?? "tts.error",
                message: event.errorMessage ?? "tts error",
                leg: leg.rawValue
            ))
        }
    }

    func onStateChanged(sessionId: String, state: String, requestId: String?) {}

    func onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        emit(TranslateEvents.error(
            sessionId: self.sessionId, code: errorCode, message: message,
            leg: leg.rawValue
        ))
    }

    func onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?) {
        emit(TranslateEvents.connectionState(
            sessionId: self.sessionId, leg: leg.rawValue,
            state: state, errorMessage: errorMessage
        ))
    }

    func onAgentReady(sessionId: String, ready: Bool, errorCode: String?, errorMessage: String?) {
        readyLock.lock()
        if !readyArrived {
            readyArrived = true
            if !ready {
                readyError = .agentReadyFailed(
                    code: errorCode ?? "agent.ready_failed",
                    message: errorMessage ?? "agent ready failed",
                    leg: leg.rawValue
                )
            }
            readyLock.unlock()
            readySem.signal()
        } else {
            readyLock.unlock()
        }

        if !ready {
            emit(TranslateEvents.error(
                sessionId: self.sessionId,
                code: errorCode ?? "agent.ready_failed",
                message: errorMessage ?? "agent ready failed",
                leg: leg.rawValue, fatal: true
            ))
        }
    }
}

enum TranslateSessionError: Error, CustomStringConvertible {
    case noDevice(message: String)
    case connectTimeout
    case agentUnsupported(message: String)
    case enterFailed(message: String)
    case agentReadyFailed(code: String, message: String, leg: String)

    var code: String {
        switch self {
        case .noDevice: return "translate.no_device"
        case .connectTimeout: return "translate.connect_timeout"
        case .agentUnsupported: return "translate.agent_unsupported"
        case .enterFailed: return "translate.enter_mode_failed"
        case .agentReadyFailed(let c, _, _): return c
        }
    }

    var description: String {
        switch self {
        case .noDevice(let m): return "translate.no_device: \(m)"
        case .connectTimeout: return "translate.connect_timeout: agent connect timeout"
        case .agentUnsupported(let m): return "translate.agent_unsupported: \(m)"
        case .enterFailed(let m): return "translate.enter_mode_failed: \(m)"
        case .agentReadyFailed(let c, let m, let leg): return "\(c) [\(leg)]: \(m)"
        }
    }
}
