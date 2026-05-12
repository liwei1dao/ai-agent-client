import Foundation

/// AST (end-to-end speech translation) service contract.
///
/// Long-lived bidirectional audio stream — server handles ASR → translation → TTS.
public protocol NativeAstService: AnyObject {
    func initialize(configJson: String)
    func connect(callback: AstCallback)
    func startAudio()
    func stopAudio()
    func interrupt()
    func release()

    // ── External audio source (mutually exclusive with mic mode). ──
    func externalAudioCapability() -> ExternalAudioCapability
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws
    func pushExternalAudioFrame(_ frame: Data)
    func stopExternalAudio()
}

public extension NativeAstService {
    func externalAudioCapability() -> ExternalAudioCapability { .unsupported }
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        throw NativeServiceError.unsupported(
            "ast service \(type(of: self)) does not support external audio source"
        )
    }
    func pushExternalAudioFrame(_ frame: Data) {}
    func stopExternalAudio() {}
}

/// Which recognition track an AST event belongs to.
public enum AstRole {
    case source       // user-side ASR
    case translated   // server-translated text
}

/// AST recognition five-tuple aligned with the STS contract.
///
/// Per `requestId`: `recognitionStart → recognizing* → recognized* →
/// recognitionDone → recognitionEnd`. The orchestrator relies on the
/// closing-rule invariants.
public protocol AstCallback: AnyObject {
    func onConnected()
    func onDisconnected()

    func onRecognitionStart(role: AstRole, requestId: String)
    func onRecognizing(role: AstRole, requestId: String, text: String)
    func onRecognized(role: AstRole, requestId: String, text: String)
    func onRecognitionDone(role: AstRole, requestId: String)
    func onRecognitionEnd(requestId: String)

    func onRecognitionError(requestId: String?, role: AstRole?, code: String, message: String)
    func onError(code: String, message: String)
}
