import Foundation

/// STS (end-to-end speech-to-speech) service contract.
///
/// Implementations open a long-lived WebSocket (vendor-specific), pump mic
/// audio in, and surface ASR/LLM/TTS events through `StsCallback`.
public protocol NativeStsService: AnyObject {
    func initialize(configJson: String)
    func connect(callback: StsCallback)
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

public extension NativeStsService {
    func externalAudioCapability() -> ExternalAudioCapability { .unsupported }
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        throw NativeServiceError.unsupported(
            "sts service \(type(of: self)) does not support external audio source"
        )
    }
    func pushExternalAudioFrame(_ frame: Data) {}
    func stopExternalAudio() {}
}

public protocol StsCallback: AnyObject {
    func onConnected()
    func onSttPartialResult(text: String)
    func onSttFinalResult(text: String)
    func onTtsAudioChunk(pcmData: Data)
    func onChatPartialResult(cumulativeText: String)
    func onSentenceDone(text: String)
    func onDisconnected()
    func onError(code: String, message: String)
    func onSpeechStart()
    func onStateChanged(state: String)
}

public extension StsCallback {
    func onChatPartialResult(cumulativeText: String) {}
}
