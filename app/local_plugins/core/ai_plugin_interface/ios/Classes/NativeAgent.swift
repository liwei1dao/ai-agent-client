import Foundation

/// Native agent contract.
///
/// One concrete implementation per agent type (chat / sts / translate / ast).
/// `agents_server` creates instances via `NativeAgentRegistry.create(_:)`.
///
/// Lifecycle:
///   create → initialize → [connectService → sendText / startListening / …
///   → disconnectService] → release
public protocol NativeAgent: AnyObject {
    /// "chat" | "sts-chat" | "translate" | "ast-translate"
    var agentType: String { get }

    /// One-time setup. `eventSink` is owned by the caller; the agent must not
    /// retain it past `release()`.
    func initialize(config: NativeAgentConfig, eventSink: AgentEventSink)

    /// Open vendor-side connections (WebSocket / handshake).
    /// Three-stage pipelines may default this to a no-op.
    func connectService()

    /// Tear down vendor-side connections; agent stays initialised.
    func disconnectService()

    /// Free-text input (text-mode chat, or fallback for voice agents).
    func sendText(requestId: String, text: String)

    /// Start short-voice listening (mic on).
    func startListening()

    /// Stop short-voice listening (mic off).
    func stopListening()

    /// Switch the active input mode: "text" | "short_voice" | "call".
    func setInputMode(_ mode: String)

    /// Generic key/value option setter. Agents must ignore unknown keys.
    ///
    /// Conventional keys (translate agent):
    ///   - "bidirectional" = "true" | "false"
    ///   - "direction"     = "src_to_dst" | "dst_to_src"
    func setOption(key: String, value: String)

    /// Stop the active turn (cancel LLM, stop TTS, return to idle).
    func interrupt()

    /// Release every resource held by the agent.
    func release()

    // ── External audio source (call translation / face-to-face). ──
    func externalAudioCapability() -> ExternalAudioCapability
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws
    func pushExternalAudioFrame(_ frame: Data)
    func stopExternalAudio()
}

public extension NativeAgent {
    func connectService() {}
    func disconnectService() {}
    func setOption(key: String, value: String) {}

    func externalAudioCapability() -> ExternalAudioCapability { .unsupported }
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        throw NativeServiceError.unsupported(
            "agent \(type(of: self)) does not support external audio source"
        )
    }
    func pushExternalAudioFrame(_ frame: Data) {}
    func stopExternalAudio() {}
}
