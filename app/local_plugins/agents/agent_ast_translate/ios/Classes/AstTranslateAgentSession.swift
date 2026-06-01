import Foundation
import ai_plugin_interface
import os.log

/// AST (end-to-end speech translation) agent session — iOS port of the Kotlin
/// `AstTranslateAgentSession`. Persistence stays on the Dart side; this class
/// only bridges `AstCallback` five-tuple events to `AgentEventSink` STT/LLM
/// events (same mapping as Android).
///
/// Bridging rules:
///   - recognizing(.source)     → SttEventData(partialResult)
///   - recognized(.source)      → SttEventData(finalResult, requestId)
///   - recognizing(.translated) → LlmEventData(firstToken, textDelta, requestId)
///   - recognized(.translated)  → LlmEventData(firstToken, textDelta, requestId)
///   - recognitionEnd           → LlmEventData(done, fullText)
public final class AstTranslateAgentSession: NativeAgent {

    public let agentType = "ast-translate"

    private static let log = OSLog(subsystem: "com.aiagent.agent_ast_translate", category: "Session")

    fileprivate enum State: String { case idle, connected, error }

    private let stateLock = NSLock()
    private var state: State = .idle

    private var config: NativeAgentConfig!
    private weak var eventSink: AgentEventSink?
    private var inputMode: String = "text"

    private var astService: NativeAstService?

    /// Last translated-track snapshot for the current round. Emitted as
    /// `done.fullText` on `recognitionEnd`.
    private var lastTranslatedText: String = ""
    private var activeTranslationRequestId: String?

    public init() {}

    // ── NativeAgent lifecycle ─────────────────────────────────────────────

    public func initialize(config: NativeAgentConfig, eventSink: AgentEventSink) {
        self.config = config
        self.eventSink = eventSink
        self.inputMode = config.inputMode

        do {
            let svc = try NativeServiceRegistry.shared.createAst(config.astVendor ?? "volcengine")
            svc.initialize(configJson: config.astConfigJson ?? "{}")
            self.astService = svc
            os_log("initialized agentId=%{public}@ astVendor=%{public}@ inputMode=%{public}@",
                   log: Self.log, type: .debug,
                   config.agentId, config.astVendor ?? "volcengine", config.inputMode)
        } catch {
            os_log("createAst failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
            eventSink.onError(
                sessionId: config.agentId,
                errorCode: "ast_init_failed",
                message: error.localizedDescription,
                requestId: nil
            )
        }
    }

    public func connectService() {
        os_log("connectService: agentId=%{public}@", log: Self.log, type: .debug, config.agentId)

        do {
            let svc = try NativeServiceRegistry.shared.createAst(config.astVendor ?? "volcengine")
            svc.initialize(configJson: config.astConfigJson ?? "{}")
            self.astService = svc
        } catch {
            os_log("connectService createAst failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
            transitionTo(.error)
            eventSink?.onError(
                sessionId: config.agentId,
                errorCode: "ast_init_failed",
                message: error.localizedDescription,
                requestId: nil
            )
            eventSink?.onAgentReady(
                sessionId: config.agentId,
                ready: false,
                errorCode: "ast_init_failed",
                errorMessage: error.localizedDescription
            )
            return
        }

        astService?.connect(callback: AstCallbackAdapter(owner: self))
    }

    public func disconnectService() {
        os_log("disconnectService: agentId=%{public}@", log: Self.log, type: .debug, config.agentId)
        astService?.release()
        transitionTo(.idle)
        eventSink?.onConnectionStateChanged(
            sessionId: config.agentId,
            state: "disconnected",
            errorMessage: nil
        )
    }

    public func sendText(requestId: String, text: String) {
        os_log("sendText ignored — AST is voice-only", log: Self.log, type: .info)
    }

    public func startListening() {
        astService?.startAudio()
    }

    public func stopListening() {
        astService?.stopAudio()
    }

    public func setInputMode(_ mode: String) {
        os_log("setInputMode: %{public}@", log: Self.log, type: .debug, mode)
        inputMode = mode
        switch mode {
        case "call":
            astService?.startAudio()
        case "short_voice":
            break
        default:
            astService?.stopAudio()
        }
    }

    public func interrupt() {
        astService?.interrupt()
        transitionTo(.connected)
    }

    public func release() {
        astService?.release()
        astService = nil
    }

    // ── External audio (call translation) ─────────────────────────────────

    public func externalAudioCapability() -> ExternalAudioCapability {
        astService?.externalAudioCapability() ?? .unsupported
    }

    public func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        guard let svc = astService else {
            throw NativeServiceError.invalidConfig("ast service not initialised")
        }
        try svc.startExternalAudio(format: format, sink: sink)
    }

    public func pushExternalAudioFrame(_ frame: Data) {
        astService?.pushExternalAudioFrame(frame)
    }

    public func stopExternalAudio() {
        astService?.stopExternalAudio()
    }

    // ── Internal ──────────────────────────────────────────────────────────

    fileprivate func transitionTo(_ newState: State) {
        stateLock.lock()
        state = newState
        stateLock.unlock()
        eventSink?.onStateChanged(
            sessionId: config.agentId,
            state: newState.rawValue,
            requestId: nil
        )
    }

    fileprivate func sink() -> AgentEventSink? { eventSink }
    fileprivate func agentId() -> String { config.agentId }
    fileprivate func currentInputMode() -> String { inputMode }
    fileprivate func currentService() -> NativeAstService? { astService }

    fileprivate func setActiveTranslationRequestId(_ id: String?) { activeTranslationRequestId = id }
    fileprivate func getActiveTranslationRequestId() -> String? { activeTranslationRequestId }
    fileprivate func setLastTranslatedText(_ text: String) { lastTranslatedText = text }
    fileprivate func getLastTranslatedText() -> String { lastTranslatedText }
}

// MARK: - AstCallback adapter

private final class AstCallbackAdapter: AstCallback {
    private weak var owner: AstTranslateAgentSession?

    init(owner: AstTranslateAgentSession) { self.owner = owner }

    func onConnected() {
        guard let owner = owner else { return }
        owner.transitionTo(.connected)
        owner.sink()?.onConnectionStateChanged(
            sessionId: owner.agentId(),
            state: "connected",
            errorMessage: nil
        )
        owner.sink()?.onAgentReady(sessionId: owner.agentId(), ready: true)
        if owner.currentInputMode() == "call" {
            owner.currentService()?.startAudio()
        }
    }

    func onDisconnected() {
        guard let owner = owner else { return }
        owner.transitionTo(.idle)
        owner.sink()?.onConnectionStateChanged(
            sessionId: owner.agentId(),
            state: "disconnected",
            errorMessage: nil
        )
    }

    func onRecognitionStart(role: AstRole, requestId: String) {
        // No-op — first partial/firstToken event lazily creates the bubble.
    }

    func onRecognizing(role: AstRole, requestId: String, text: String) {
        guard let owner = owner else { return }
        switch role {
        case .source:
            owner.sink()?.onSttEvent(SttEventData(
                sessionId: owner.agentId(),
                requestId: "",
                kind: "partialResult",
                text: text
            ))
        case .translated:
            owner.setActiveTranslationRequestId(requestId)
            owner.setLastTranslatedText(text)
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: requestId,
                kind: "firstToken",
                textDelta: text
            ))
        }
    }

    func onRecognized(role: AstRole, requestId: String, text: String) {
        guard let owner = owner else { return }
        switch role {
        case .source:
            owner.sink()?.onSttEvent(SttEventData(
                sessionId: owner.agentId(),
                requestId: requestId,
                kind: "finalResult",
                text: text
            ))
        case .translated:
            owner.setActiveTranslationRequestId(requestId)
            owner.setLastTranslatedText(text)
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: requestId,
                kind: "firstToken",
                textDelta: text
            ))
        }
    }

    func onRecognitionDone(role: AstRole, requestId: String) {
        // No-op — round-level closure handled by recognitionEnd.
    }

    func onRecognitionEnd(requestId: String) {
        guard let owner = owner else { return }
        let transId = owner.getActiveTranslationRequestId()
        let transText = owner.getLastTranslatedText()
        if let id = transId, !transText.trimmingCharacters(in: .whitespaces).isEmpty {
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: id,
                kind: "done",
                fullText: transText
            ))
        }
        owner.setActiveTranslationRequestId(nil)
        owner.setLastTranslatedText("")
    }

    func onRecognitionError(requestId: String?, role: AstRole?, code: String, message: String) {
        guard let owner = owner else { return }
        owner.sink()?.onError(
            sessionId: owner.agentId(),
            errorCode: code,
            message: message,
            requestId: requestId
        )
    }

    func onError(code: String, message: String) {
        guard let owner = owner else { return }
        owner.transitionTo(.error)
        owner.sink()?.onConnectionStateChanged(
            sessionId: owner.agentId(),
            state: "error",
            errorMessage: message
        )
        owner.sink()?.onError(
            sessionId: owner.agentId(),
            errorCode: code,
            message: message,
            requestId: nil
        )
        owner.sink()?.onAgentReady(
            sessionId: owner.agentId(),
            ready: false,
            errorCode: code,
            errorMessage: message
        )
    }
}
