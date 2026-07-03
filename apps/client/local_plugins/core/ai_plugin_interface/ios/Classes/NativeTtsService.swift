import Foundation

/// One synthesised audio segment.
public struct TtsAudio {
    public let data: Data
    /// "mp3" | "pcm16" | "opus" | etc.
    public let format: String
    /// Real duration in ms. `nil` means unknown — do NOT substitute 0.
    public let durationMs: Int?

    public init(data: Data, format: String, durationMs: Int? = nil) {
        self.data = data
        self.format = format
        self.durationMs = durationMs
    }
}

/// TTS (speech synthesis + playback) service contract.
///
/// Two-stage pipeline:
///   - `synthesize(text)` → audio bytes (network call, can run concurrently).
///   - `play(audio)`      → speaker output (must be serialised by the caller).
///
/// The default `speak(text:callback:)` ties them together for one-shot tests.
public protocol NativeTtsService: AnyObject {
    func initialize(configJson: String)

    /// Synthesise text. The implementation **must** support concurrent calls —
    /// the agent layer keeps ≤2 in flight to absorb sentence-buffer throttling.
    /// Cancelling the parent task must abort the network request promptly.
    func synthesize(requestId: String, text: String) async throws -> TtsAudio

    /// Play an already-synthesised audio segment. Serialised by the caller.
    /// Returning early (cancellation) maps to `playbackInterrupted`.
    func play(requestId: String, audio: TtsAudio, callback: TtsCallback) async throws

    /// One-shot helper: synthesise + play with the §4.1 event ordering.
    func speak(requestId: String, text: String, callback: TtsCallback) async

    /// Interrupt the current playback and cancel pending synthesis requests.
    func stop()

    func release()

    // ── External audio sink mode (mutually exclusive with local playback). ──

    func externalAudioCapability() -> ExternalAudioCapability
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws
    func stopExternalAudio()
}

public extension NativeTtsService {
    func speak(requestId: String, text: String, callback: TtsCallback) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        callback.onSynthesisStart()
        do {
            let audio = try await synthesize(requestId: requestId, text: text)
            callback.onSynthesisReady(durationMs: audio.durationMs ?? 0)
            callback.onPlaybackStart()
            try await play(requestId: requestId, audio: audio, callback: callback)
            callback.onPlaybackDone()
        } catch is CancellationError {
            callback.onPlaybackInterrupted()
        } catch {
            callback.onError(code: "tts_error", message: error.localizedDescription)
        }
    }

    func externalAudioCapability() -> ExternalAudioCapability { .unsupported }
    func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        throw NativeServiceError.unsupported(
            "tts service \(type(of: self)) does not support external audio sink"
        )
    }
    func stopExternalAudio() {}
}

public protocol TtsCallback: AnyObject {
    func onSynthesisStart()
    func onSynthesisReady(durationMs: Int)
    func onPlaybackStart()
    func onPlaybackProgress(progressMs: Int)
    func onPlaybackDone()
    func onPlaybackInterrupted()
    func onError(code: String, message: String)
}
