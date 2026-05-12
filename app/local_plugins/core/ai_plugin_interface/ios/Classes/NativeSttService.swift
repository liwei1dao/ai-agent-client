import Foundation

/// STT (speech-to-text) service contract.
///
/// Implemented by `stt_azure` and friends. Used by chat / translate agents.
public protocol NativeSttService: AnyObject {
    /// `configJson` carries apiKey / region / language / etc.
    func initialize(configJson: String)

    /// Does the underlying engine return BCP-47 `detectedLang` on each result?
    func supportsLanguageDetection() -> Bool

    /// Start mic + recognition; results flow through `callback`.
    func startListening(callback: SttCallback)

    /// Stop the mic and finalise any in-flight buffers.
    func stopListening()

    /// Release engine resources.
    func release()

    // ── External audio source mode (mutually exclusive with startListening). ──

    func externalAudioCapability() -> ExternalAudioCapability

    /// Start consuming externally-provided audio frames; `format` must be
    /// within `externalAudioCapability()`.
    func startExternalAudio(format: ExternalAudioFormat, callback: SttCallback) throws

    /// Push one frame of external audio; format must match the one negotiated
    /// in `startExternalAudio`.
    func pushExternalAudioFrame(_ frame: Data)

    func stopExternalAudio()
}

public extension NativeSttService {
    func supportsLanguageDetection() -> Bool { false }
    func externalAudioCapability() -> ExternalAudioCapability { .unsupported }
    func startExternalAudio(format: ExternalAudioFormat, callback: SttCallback) throws {
        throw NativeServiceError.unsupported(
            "stt service \(type(of: self)) does not support external audio source"
        )
    }
    func pushExternalAudioFrame(_ frame: Data) {}
    func stopExternalAudio() {}
}

/// STT streaming callback.
public protocol SttCallback: AnyObject {
    /// Mic is open and recognition has started.
    func onListeningStarted()

    /// Streaming intermediate result.
    func onPartialResult(text: String, detectedLang: String?)

    /// Final (committed) result for the current utterance.
    func onFinalResult(text: String, detectedLang: String?)

    /// VAD detected speech.
    func onVadSpeechStart()
    /// VAD detected silence/end-of-speech.
    func onVadSpeechEnd()

    /// Mic closed.
    func onListeningStopped()

    /// Recoverable error (the stream may continue if the engine recovers).
    func onError(code: String, message: String)
}

public extension SttCallback {
    /// Convenience overload for vendors without language detection.
    func onPartialResult(text: String) { onPartialResult(text: text, detectedLang: nil) }
    func onFinalResult(text: String)  { onFinalResult(text: text, detectedLang: nil) }
}

/// Common error type for service contracts.
public enum NativeServiceError: Error {
    case unsupported(String)
    case invalidConfig(String)
    case runtime(String)
}
