import Foundation
import ai_plugin_interface
import os.log

/// STS (end-to-end speech-to-speech) agent session — iOS port of the Kotlin
/// `StsChatAgentSession`. Persistence (message DB) stays on the Dart side, so
/// this class is a thin event-translation layer over `NativeStsService`.
///
/// Lifecycle:
///   initialize → connectService (open WebSocket) → setInputMode("call")
///   → [bidirectional audio] → setInputMode("text") → disconnectService → release
public final class StsChatAgentSession: NativeAgent {

    public let agentType = "sts-chat"

    private static let log = OSLog(subsystem: "com.aiagent.agent_sts_chat", category: "Session")

    fileprivate enum State: String { case idle, connected, error }

    private let stateLock = NSLock()
    private var state: State = .idle

    private var config: NativeAgentConfig!
    private weak var eventSink: AgentEventSink?
    private var inputMode: String = "text"

    private var stsService: NativeStsService?

    /// Current assistant-message id; same id is reused across stream tokens
    /// of one reply, then cleared on `onSentenceDone` / `onSpeechStart`.
    private var currentAssistantId: String?
    /// Length of the cumulative chat text already pushed to UI — used to
    /// derive `firstToken.textDelta` from vendor snapshots.
    private var lastSentLength: Int = 0

    public init() {}

    // ── NativeAgent lifecycle ─────────────────────────────────────────────

    public func initialize(config: NativeAgentConfig, eventSink: AgentEventSink) {
        self.config = config
        self.eventSink = eventSink
        self.inputMode = config.inputMode

        do {
            let svc = try NativeServiceRegistry.shared.createSts(config.stsVendor ?? "volcengine")
            svc.initialize(configJson: config.stsConfigJson ?? "{}")
            self.stsService = svc
            os_log("initialized agentId=%{public}@ stsVendor=%{public}@ inputMode=%{public}@",
                   log: Self.log, type: .debug,
                   config.agentId, config.stsVendor ?? "volcengine", config.inputMode)
        } catch {
            os_log("createSts failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
            eventSink.onError(
                sessionId: config.agentId,
                errorCode: "sts_init_failed",
                message: error.localizedDescription,
                requestId: nil
            )
        }
    }

    public func connectService() {
        os_log("connectService: agentId=%{public}@", log: Self.log, type: .debug, config.agentId)

        // Recreate STS service in case the previous disconnectService released it.
        do {
            let svc = try NativeServiceRegistry.shared.createSts(config.stsVendor ?? "volcengine")
            svc.initialize(configJson: config.stsConfigJson ?? "{}")
            self.stsService = svc
        } catch {
            os_log("connectService createSts failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
            transitionTo(.error)
            eventSink?.onError(
                sessionId: config.agentId,
                errorCode: "sts_init_failed",
                message: error.localizedDescription,
                requestId: nil
            )
            eventSink?.onAgentReady(
                sessionId: config.agentId,
                ready: false,
                errorCode: "sts_init_failed",
                errorMessage: error.localizedDescription
            )
            return
        }

        stsService?.connect(callback: StsCallbackAdapter(owner: self))
    }

    public func disconnectService() {
        os_log("disconnectService: agentId=%{public}@", log: Self.log, type: .debug, config.agentId)
        stsService?.release()
        transitionTo(.idle)
        eventSink?.onConnectionStateChanged(
            sessionId: config.agentId,
            state: "disconnected",
            errorMessage: nil
        )
    }

    public func sendText(requestId: String, text: String) {
        os_log("sendText ignored — STS is voice-only (text=%{public}@)",
               log: Self.log, type: .info, String(text.prefix(60)))
    }

    public func startListening() {
        os_log("startListening → stsService.startAudio", log: Self.log, type: .debug)
        stsService?.startAudio()
    }

    public func stopListening() {
        os_log("stopListening → stsService.stopAudio", log: Self.log, type: .debug)
        stsService?.stopAudio()
    }

    public func setInputMode(_ mode: String) {
        os_log("setInputMode: %{public}@", log: Self.log, type: .debug, mode)
        inputMode = mode
        switch mode {
        case "call":
            stsService?.startAudio()
        case "short_voice":
            break  // UI drives startListening/stopListening
        default:
            stsService?.stopAudio()
        }
    }

    public func interrupt() {
        stsService?.interrupt()
        transitionTo(.connected)
    }

    public func release() {
        stsService?.release()
        stsService = nil
    }

    // ── External audio source (call translation / face-to-face) ───────────

    public func externalAudioCapability() -> ExternalAudioCapability {
        stsService?.externalAudioCapability() ?? .unsupported
    }

    public func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        guard let svc = stsService else {
            throw NativeServiceError.invalidConfig("sts service not initialised")
        }
        try svc.startExternalAudio(format: format, sink: sink)
    }

    public func pushExternalAudioFrame(_ frame: Data) {
        stsService?.pushExternalAudioFrame(frame)
    }

    public func stopExternalAudio() {
        stsService?.stopExternalAudio()
    }

    // ── Internal helpers ──────────────────────────────────────────────────

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
    fileprivate func currentService() -> NativeStsService? { stsService }

    // Bridges callback-only mutations from the adapter back into the session.
    fileprivate func setCurrentAssistantId(_ id: String?) { currentAssistantId = id }
    fileprivate func getCurrentAssistantId() -> String? { currentAssistantId }
    fileprivate func setLastSentLength(_ n: Int) { lastSentLength = n }
    fileprivate func getLastSentLength() -> Int { lastSentLength }
}

// MARK: - StsCallback adapter

/// Translates `StsCallback` (vendor-side) into `AgentEventSink` events.
/// Kept as a separate class so the session can hand a strong reference to the
/// vendor service without creating a retain cycle.
private final class StsCallbackAdapter: StsCallback {
    private weak var owner: StsChatAgentSession?

    init(owner: StsChatAgentSession) { self.owner = owner }

    func onConnected() {
        guard let owner = owner else { return }
        owner.transitionTo(.connected)
        owner.sink()?.onConnectionStateChanged(
            sessionId: owner.agentId(),
            state: "connected",
            errorMessage: nil
        )
        owner.sink()?.onAgentReady(sessionId: owner.agentId(), ready: true)
        // If UI already requested call mode before connect completed, start now.
        if owner.currentInputMode() == "call" {
            owner.currentService()?.startAudio()
        }
    }

    func onSttPartialResult(text: String) {
        guard let owner = owner else { return }
        owner.sink()?.onSttEvent(SttEventData(
            sessionId: owner.agentId(),
            requestId: "",
            kind: "partialResult",
            text: text
        ))
    }

    func onSttFinalResult(text: String) {
        guard let owner = owner else { return }
        owner.setCurrentAssistantId(nil)
        let reqId = UUID().uuidString
        owner.sink()?.onSttEvent(SttEventData(
            sessionId: owner.agentId(),
            requestId: reqId,
            kind: "finalResult",
            text: text
        ))
    }

    func onTtsAudioChunk(pcmData: Data) {
        // TTS audio is played by the vendor service; no agent-level fan-out.
    }

    func onChatPartialResult(cumulativeText: String) {
        guard let owner = owner else { return }
        var last = owner.getLastSentLength()
        // Defensive: some vendors rewrite the snapshot shorter mid-stream.
        if last > cumulativeText.count { last = 0 }
        let startIdx = cumulativeText.index(cumulativeText.startIndex, offsetBy: last)
        let delta = String(cumulativeText[startIdx...])
        if delta.isEmpty { return }

        let isNew = owner.getCurrentAssistantId() == nil
        let msgId: String
        if let existing = owner.getCurrentAssistantId() {
            msgId = existing
        } else {
            msgId = UUID().uuidString
            owner.setCurrentAssistantId(msgId)
        }
        _ = isNew  // parity with Android (Dart side derives "first chunk" from requestId state)

        owner.setLastSentLength(cumulativeText.count)
        owner.sink()?.onLlmEvent(LlmEventData(
            sessionId: owner.agentId(),
            requestId: msgId,
            kind: "firstToken",
            textDelta: delta
        ))
    }

    func onSentenceDone(text: String) {
        guard let owner = owner else { return }
        owner.setLastSentLength(0)
        if let msgId = owner.getCurrentAssistantId() {
            owner.setCurrentAssistantId(nil)
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: msgId,
                kind: "done",
                fullText: text
            ))
        } else {
            // No streaming bubble yet — emit a single-shot reply.
            let id = UUID().uuidString
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: id,
                kind: "firstToken",
                textDelta: text
            ))
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: id,
                kind: "done",
                fullText: text
            ))
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

    func onSpeechStart() {
        guard let owner = owner else { return }
        if let prevId = owner.getCurrentAssistantId() {
            owner.setLastSentLength(0)
            owner.sink()?.onLlmEvent(LlmEventData(
                sessionId: owner.agentId(),
                requestId: prevId,
                kind: "done"
            ))
            owner.setCurrentAssistantId(nil)
        }
        owner.sink()?.onSttEvent(SttEventData(
            sessionId: owner.agentId(),
            requestId: "",
            kind: "vadSpeechStart"
        ))
    }

    func onStateChanged(state: String) {
        guard let owner = owner else { return }
        owner.sink()?.onStateChanged(
            sessionId: owner.agentId(),
            state: state,
            requestId: nil
        )
    }
}
