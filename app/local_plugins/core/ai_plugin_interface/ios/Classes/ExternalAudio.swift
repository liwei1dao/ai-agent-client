import Foundation

/// External audio source/sink format.
///
/// Used when an agent does not open its own microphone — translate_server
/// pumps frames in via `NativeAgent.pushExternalAudioFrame(_:)` (call
/// translation is the canonical case).
public struct ExternalAudioFormat {
    public enum Codec {
        case opus
        case pcmS16LE
    }

    public let codec: Codec
    public let sampleRate: Int
    public let channels: Int
    public let frameMs: Int

    public init(codec: Codec, sampleRate: Int, channels: Int, frameMs: Int) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.frameMs = frameMs
    }

    /// 16 kHz / mono / 20 ms Opus (the headset's native frame size).
    public static let opus16kMono20ms = ExternalAudioFormat(
        codec: .opus, sampleRate: 16000, channels: 1, frameMs: 20
    )

    /// 16 kHz / mono / 20 ms PCM_S16LE = 640 bytes per frame.
    public static let pcmS16LE16kMono20ms = ExternalAudioFormat(
        codec: .pcmS16LE, sampleRate: 16000, channels: 1, frameMs: 20
    )
}

/// What kinds of external audio a service can ingest.
public struct ExternalAudioCapability {
    public let acceptsOpus: Bool
    public let acceptsPcm: Bool
    public let preferredSampleRate: Int
    public let preferredChannels: Int
    public let preferredFrameMs: Int

    public init(
        acceptsOpus: Bool,
        acceptsPcm: Bool,
        preferredSampleRate: Int = 16000,
        preferredChannels: Int = 1,
        preferredFrameMs: Int = 20
    ) {
        self.acceptsOpus = acceptsOpus
        self.acceptsPcm = acceptsPcm
        self.preferredSampleRate = preferredSampleRate
        self.preferredChannels = preferredChannels
        self.preferredFrameMs = preferredFrameMs
    }

    public var supportsExternalAudio: Bool { acceptsOpus || acceptsPcm }

    public static let unsupported = ExternalAudioCapability(acceptsOpus: false, acceptsPcm: false)
}

/// Single frame of external audio (used on the downlink — service → caller).
public struct ExternalAudioFrame {
    public let codec: ExternalAudioFormat.Codec
    public let sampleRate: Int
    public let channels: Int
    public let bytes: Data
    public let timestampUs: Int64
    /// Marks the last frame of the current TTS utterance.
    public let isFinal: Bool

    public init(
        codec: ExternalAudioFormat.Codec,
        sampleRate: Int,
        channels: Int,
        bytes: Data,
        timestampUs: Int64 = 0,
        isFinal: Bool = false
    ) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bytes = bytes
        self.timestampUs = timestampUs
        self.isFinal = isFinal
    }
}

/// Downlink callback from a service/agent back to the orchestrator.
public protocol ExternalAudioSink: AnyObject {
    func onTtsFrame(_ frame: ExternalAudioFrame)
    func onError(code: String, message: String)
}

public extension ExternalAudioSink {
    func onError(code: String, message: String) {}
}
