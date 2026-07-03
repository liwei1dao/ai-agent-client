import Foundation

/// Agent → AgentsServer fan-out for all per-session events.
///
/// Implemented by `AgentsServerPlugin` (which forwards to a Flutter
/// EventChannel). Each registered `NativeAgent` is handed an instance and
/// pushes STT / LLM / TTS / state / error / connection events through it.
public protocol AgentEventSink: AnyObject {
    func onSttEvent(_ event: SttEventData)
    func onLlmEvent(_ event: LlmEventData)
    func onTtsEvent(_ event: TtsEventData)
    func onStateChanged(sessionId: String, state: String, requestId: String?)
    func onError(sessionId: String, errorCode: String, message: String, requestId: String?)
    func onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?)

    /// Agent-ready callback (replaces the older "wait for connected" pattern).
    /// Exactly one ready-event must fire per `connectService` call, with
    /// `ready=true` on success or `ready=false` plus error info on failure.
    func onAgentReady(sessionId: String, ready: Bool, errorCode: String?, errorMessage: String?)
}

public extension AgentEventSink {
    func onConnectionStateChanged(sessionId: String, state: String, errorMessage: String? = nil) {
        onConnectionStateChanged(sessionId: sessionId, state: state, errorMessage: errorMessage)
    }
    func onAgentReady(sessionId: String, ready: Bool) {
        onAgentReady(sessionId: sessionId, ready: ready, errorCode: nil, errorMessage: nil)
    }
}

/// Service-test event fan-out (mirrors `AgentEventSink` but for service_manager).
public protocol ServiceTestEventSink: AnyObject {
    func onSttTestEvent(testId: String, kind: String, text: String?, errorCode: String?, errorMessage: String?)
    func onTtsTestEvent(testId: String, kind: String, progressMs: Int?, durationMs: Int?, errorCode: String?, errorMessage: String?)
    func onLlmTestEvent(
        testId: String,
        kind: String,
        textDelta: String?,
        thinkingDelta: String?,
        toolCallId: String?,
        toolName: String?,
        toolArgumentsDelta: String?,
        toolResult: String?,
        fullText: String?,
        errorCode: String?,
        errorMessage: String?
    )
    func onTranslationTestEvent(
        testId: String,
        kind: String,
        sourceText: String?,
        translatedText: String?,
        sourceLanguage: String?,
        targetLanguage: String?,
        errorCode: String?,
        errorMessage: String?
    )
    func onStsTestEvent(testId: String, kind: String, text: String?, state: String?, errorCode: String?, errorMessage: String?)
    func onAstTestEvent(testId: String, kind: String, text: String?, state: String?, errorCode: String?, errorMessage: String?)
    func onTestDone(testId: String, success: Bool, message: String?)
}
