import Foundation
import ai_plugin_interface
import os.log

/// Text-mode chat-agent session.
///
/// This is the iOS counterpart of the Kotlin `ChatAgentSession`, but for now
/// only the **text input** path is implemented:
///   `sendText` → LLM streaming → events fan out through `AgentEventSink`.
///
/// Short-voice / call modes need iOS-side `NativeSttService` / `NativeTtsService`
/// implementations that don't exist yet (`stt_azure` / `tts_azure` only ship a
/// MethodChannel facade today). Those modes return `inputMode_not_supported`
/// for the time being; lifting that restriction is a follow-up.
public final class ChatAgentSession: NativeAgent {
    public let agentType = "chat"

    private static let log = OSLog(subsystem: "com.aiagent.agent_chat", category: "Session")

    private var config: NativeAgentConfig!
    private weak var eventSink: AgentEventSink?
    private var inputMode: String = "text"

    private var llmService: NativeLlmService?

    /// In-flight request — newest wins. `cancel()` aborts the old one.
    private let stateLock = NSLock()
    private var activeRequestId: String?
    private var activeTask: Task<Void, Never>?

    /// LLM tool-loop cap.
    private let maxToolIterations = 5

    public init() {}

    // ── NativeAgent lifecycle ─────────────────────────────────────

    public func initialize(config: NativeAgentConfig, eventSink: AgentEventSink) {
        self.config = config
        self.eventSink = eventSink
        self.inputMode = config.inputMode

        // Construct services lazily — only LLM is mandatory in text-mode.
        do {
            llmService = try NativeServiceRegistry.shared.createLlm(config.llmVendor ?? "openai")
            llmService?.initialize(configJson: config.llmConfigJson ?? "{}")
        } catch {
            os_log("createLlm failed: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            eventSink.onError(
                sessionId: config.agentId,
                errorCode: "llm_init_failed",
                message: error.localizedDescription,
                requestId: nil
            )
        }

        os_log("initialized agentId=%{public}@ llm=%{public}@ inputMode=%{public}@",
               log: Self.log, type: .debug,
               config.agentId, config.llmVendor ?? "openai", config.inputMode)
    }

    public func connectService() {
        // Three-stage chat agents have no remote handshake — services are ready
        // as soon as `initialize` returns.
        eventSink?.onAgentReady(
            sessionId: config.agentId,
            ready: llmService != nil,
            errorCode: llmService == nil ? "llm_init_failed" : nil,
            errorMessage: llmService == nil ? "LLM service not initialised" : nil
        )
    }

    public func sendText(requestId: String, text: String) {
        let previous = stateLock.withLock { activeRequestId }
        cancelActive(reason: "new_input")
        stateLock.withLock { activeRequestId = requestId }

        guard let llm = llmService else {
            eventSink?.onError(
                sessionId: config.agentId,
                errorCode: "llm_unavailable",
                message: "LLM service not initialised",
                requestId: requestId
            )
            return
        }
        if let previous = previous {
            _ = previous  // surface for future DB hookup parity with Android
        }

        eventSink?.onStateChanged(sessionId: config.agentId, state: "llm", requestId: requestId)

        let messages: [[String: Any]] = [
            ["role": "user", "content": text],
        ]
        let agentId = config.agentId
        let sink = eventSink

        let task = Task<Void, Never> { [weak self] in
            guard let self = self else { return }
            let callback = ChatLlmCallback(
                agentId: agentId,
                requestId: requestId,
                sink: sink
            )
            do {
                _ = try await llm.chat(
                    requestId: requestId,
                    messages: messages,
                    tools: [],
                    callback: callback
                )
            } catch is CancellationError {
                // Already surfaced as `cancelled` by the cancellation path.
            } catch {
                sink?.onLlmEvent(LlmEventData(
                    sessionId: agentId,
                    requestId: requestId,
                    kind: "error",
                    errorCode: "llm_error",
                    errorMessage: error.localizedDescription
                ))
            }
            self.stateLock.withLock {
                if self.activeRequestId == requestId {
                    self.activeRequestId = nil
                    self.activeTask = nil
                }
            }
            sink?.onStateChanged(sessionId: agentId, state: "idle", requestId: nil)
        }
        stateLock.withLock { activeTask = task }
    }

    public func startListening() {
        eventSink?.onError(
            sessionId: config.agentId,
            errorCode: "inputMode_not_supported",
            message: "Voice input on iOS is not implemented yet; use text mode.",
            requestId: nil
        )
    }

    public func stopListening() {
        // No mic on iOS yet — nothing to stop.
    }

    public func setInputMode(_ mode: String) {
        inputMode = mode
        if mode != "text" {
            os_log("setInputMode=%{public}@ requested but only text is supported on iOS",
                   log: Self.log, type: .info, mode)
        }
    }

    public func setOption(key: String, value: String) {
        os_log("setOption %{public}@=%{public}@ (ignored)", log: Self.log, type: .debug, key, value)
    }

    public func interrupt() {
        llmService?.cancel()
        cancelActive(reason: "manual_interrupt")
        eventSink?.onStateChanged(sessionId: config.agentId, state: "idle", requestId: nil)
    }

    public func release() {
        cancelActive(reason: "release")
        llmService?.cancel()
        llmService = nil
    }

    // ── helpers ───────────────────────────────────────────────────

    private func cancelActive(reason: String) {
        let task = stateLock.withLock {
            let t = activeTask
            activeTask = nil
            return t
        }
        task?.cancel()
        llmService?.cancel()
        os_log("cancelActive: %{public}@", log: Self.log, type: .debug, reason)
    }
}

// MARK: - LLM callback

/// Forwards LLM stream events into the agent event-sink wire format.
private final class ChatLlmCallback: LlmCallback {
    private let agentId: String
    private let requestId: String
    private weak var sink: AgentEventSink?

    init(agentId: String, requestId: String, sink: AgentEventSink?) {
        self.agentId = agentId
        self.requestId = requestId
        self.sink = sink
    }

    func onFirstToken(textDelta: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId, requestId: requestId, kind: "firstToken", textDelta: textDelta
        ))
    }

    func onTextDelta(_ textDelta: String) {
        // Kotlin parity: subsequent deltas reuse the `firstToken` kind so the
        // Flutter side can accumulate without a branch on first-vs-rest.
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId, requestId: requestId, kind: "firstToken", textDelta: textDelta
        ))
    }

    func onThinkingDelta(_ delta: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId, requestId: requestId, kind: "thinking", thinkingDelta: delta
        ))
    }

    func onToolCallStart(id: String, name: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId,
            requestId: requestId,
            kind: "toolCallStart",
            toolCallId: id,
            toolName: name
        ))
    }

    func onToolCallArguments(_ delta: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId,
            requestId: requestId,
            kind: "toolCallArguments",
            toolArgumentsDelta: delta
        ))
    }

    func onToolCallResult(_ result: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId,
            requestId: requestId,
            kind: "toolCallResult",
            toolResult: result
        ))
    }

    func onDone(fullText: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId,
            requestId: requestId,
            kind: "done",
            fullText: fullText
        ))
    }

    func onError(code: String, message: String) {
        sink?.onLlmEvent(LlmEventData(
            sessionId: agentId,
            requestId: requestId,
            kind: "error",
            errorCode: code,
            errorMessage: message
        ))
    }
}

// MARK: - NSLock convenience

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
