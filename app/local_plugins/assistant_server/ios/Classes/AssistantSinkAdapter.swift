import Foundation
import ai_plugin_interface

/// 把单 chat agent 的 [AgentEventSink] 事件转译成 AI 助理统一的对话/状态/错误事件。
///
/// 事件映射（按 [requestId] 配对一行对话：用户问 + AI 答）：
///  - SttEventData(partialResult) → message(role=user, stage=partial, text, requestId=nil)
///  - SttEventData(finalResult)   → message(role=user, stage=final,   text, requestId)
///  - LlmEventData(firstToken)    → message(role=assistant, stage=partial, text=delta, requestId)
///  - LlmEventData(done)          → message(role=assistant, stage=final,   text=fullText, requestId)
final class AssistantSinkAdapter: AgentEventSink {

    private let sessionId: String
    private let emit: ([String: Any?]) -> Void

    /// onAgentReady 信号 —— 用 DispatchSemaphore 实现同步等待，避免 async/await 与
    /// agent 回调线程之间的复杂 race。
    private let readyLock = NSLock()
    private let readySem = DispatchSemaphore(value: 0)
    private var readyError: AssistantSessionError?
    private var readyArrived = false

    init(sessionId: String, emit: @escaping ([String: Any?]) -> Void) {
        self.sessionId = sessionId
        self.emit = emit
    }

    /// 阻塞等待 onAgentReady（最多 [timeout] 秒）。在 IO 线程调用。
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
            throw AssistantSessionError.connectTimeout
        }
        if let err = readyError { throw err }
    }

    // MARK: - AgentEventSink

    func onSttEvent(_ event: SttEventData) {
        switch event.kind {
        case "partialResult":
            emit(AssistantEvents.message(
                sessionId: sessionId,
                role: AssistantRole.user.rawValue,
                stage: "partial",
                text: event.text ?? "",
                requestId: nil
            ))
        case "finalResult":
            guard !event.requestId.isEmpty else { return }
            emit(AssistantEvents.message(
                sessionId: sessionId,
                role: AssistantRole.user.rawValue,
                stage: "final",
                text: event.text ?? "",
                requestId: event.requestId
            ))
        case "error":
            emit(AssistantEvents.error(
                sessionId: sessionId,
                code: event.errorCode ?? "stt.error",
                message: event.errorMessage ?? "stt error",
                role: AssistantRole.user.rawValue
            ))
        default: break
        }
    }

    func onLlmEvent(_ event: LlmEventData) {
        switch event.kind {
        case "firstToken":
            guard !event.requestId.isEmpty else { return }
            emit(AssistantEvents.message(
                sessionId: sessionId,
                role: AssistantRole.assistant.rawValue,
                stage: "partial",
                text: event.textDelta ?? "",
                requestId: event.requestId
            ))
        case "done":
            guard !event.requestId.isEmpty else { return }
            emit(AssistantEvents.message(
                sessionId: sessionId,
                role: AssistantRole.assistant.rawValue,
                stage: "final",
                text: event.fullText ?? event.textDelta ?? "",
                requestId: event.requestId
            ))
        case "error":
            emit(AssistantEvents.error(
                sessionId: sessionId,
                code: event.errorCode ?? "llm.error",
                message: event.errorMessage ?? "llm error",
                role: AssistantRole.assistant.rawValue
            ))
        default: break
        }
    }

    func onTtsEvent(_ event: TtsEventData) {
        if event.kind == "error" {
            emit(AssistantEvents.error(
                sessionId: sessionId,
                code: event.errorCode ?? "tts.error",
                message: event.errorMessage ?? "tts error",
                role: AssistantRole.assistant.rawValue
            ))
        }
    }

    func onStateChanged(sessionId: String, state: String, requestId: String?) {
        // agent 内部状态机：不向上透传
    }

    func onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        emit(AssistantEvents.error(
            sessionId: self.sessionId,
            code: errorCode,
            message: message
        ))
    }

    func onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?) {
        emit(AssistantEvents.connectionState(
            sessionId: self.sessionId,
            state: state,
            errorMessage: errorMessage
        ))
    }

    func onAgentReady(sessionId: String, ready: Bool, errorCode: String?, errorMessage: String?) {
        readyLock.lock()
        if !readyArrived {
            readyArrived = true
            if !ready {
                readyError = .agentReadyFailed(
                    code: errorCode ?? "agent.ready_failed",
                    message: errorMessage ?? "agent ready failed"
                )
            }
            readyLock.unlock()
            readySem.signal()
        } else {
            readyLock.unlock()
        }

        if !ready {
            emit(AssistantEvents.error(
                sessionId: self.sessionId,
                code: errorCode ?? "agent.ready_failed",
                message: errorMessage ?? "agent ready failed",
                fatal: true
            ))
        }
    }
}

/// AssistantSession 内部错误，方便上层按 code 分流。
enum AssistantSessionError: Error, CustomStringConvertible {
    case noDevice(message: String)
    case connectTimeout
    case agentUnsupported(message: String)
    case enterFailed(message: String)
    case agentReadyFailed(code: String, message: String)

    var code: String {
        switch self {
        case .noDevice: return "assistant.no_device"
        case .connectTimeout: return "assistant.connect_timeout"
        case .agentUnsupported: return "assistant.agent_unsupported"
        case .enterFailed: return "assistant.enter_failed"
        case .agentReadyFailed(let c, _): return c
        }
    }

    var description: String {
        switch self {
        case .noDevice(let m): return "assistant.no_device: \(m)"
        case .connectTimeout: return "assistant.connect_timeout: agent connect timeout"
        case .agentUnsupported(let m): return "assistant.agent_unsupported: \(m)"
        case .enterFailed(let m): return "assistant.enter_failed: \(m)"
        case .agentReadyFailed(let c, let m): return "\(c): \(m)"
        }
    }
}
