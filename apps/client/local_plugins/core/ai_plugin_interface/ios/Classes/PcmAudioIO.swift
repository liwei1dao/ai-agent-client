import Foundation
import AVFoundation
import os.log

/// Pull-based PCM mic capture + push-based PCM playback for the volcengine
/// realtime services.
///
/// Both `sts_volcengine` and `ast_volcengine` need:
///   - 16 kHz mono 16-bit LE microphone frames pumped to the WebSocket;
///   - 24 kHz mono 16-bit LE TTS frames received from the WebSocket and
///     played out (with 3× software gain to match the Android implementation
///     which applies the same boost — VOICE_CHAT mode tends to come out
///     quiet).
///
/// `start`/`stop` toggle the mic tap; `enqueueTts(_:)` schedules a PCM
/// payload for playback; `flushTts` drops anything still queued. The class
/// owns a single `AVAudioEngine`, so callers must `release()` it before
/// dropping the reference.
public final class PcmAudioIO {

    public static let micSampleRate = 16_000
    public static let ttsSampleRate = 24_000

    private static let log = OSLog(subsystem: "com.aiagent.plugin_interface", category: "PcmAudioIO")

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let mixerNode = AVAudioMixerNode()
    private var ttsConverter: AVAudioConverter?
    private var micConverter: AVAudioConverter?

    private let stateLock = NSLock()
    private var micActive = false
    private var engineStarted = false
    private var micFrameHandler: ((Data) -> Void)?

    /// Software gain applied to TTS output. Mirrors the Android implementation
    /// (VOICE_COMMUNICATION mode tends to be quiet; 3× boost keeps parity).
    public var ttsGain: Float = 3.0

    public init() {
        engine.attach(playerNode)
        engine.attach(mixerNode)

        let ttsFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.ttsSampleRate),
            channels: 1,
            interleaved: false
        )!
        engine.connect(playerNode, to: mixerNode, format: ttsFormat)
        engine.connect(mixerNode, to: engine.mainMixerNode, format: nil)
    }

    deinit {
        release()
    }

    // ── Microphone ─────────────────────────────────────────────────

    /// Start capturing the mic and forwarding 16 kHz mono S16LE frames to
    /// `onFrame`. No-op if already capturing.
    public func startMic(onFrame: @escaping (Data) -> Void) {
        stateLock.lock()
        if micActive {
            stateLock.unlock()
            return
        }
        micActive = true
        micFrameHandler = onFrame
        stateLock.unlock()

        AudioOutputManager.shared.applyMode()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        let micTarget = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Self.micSampleRate),
            channels: 1,
            interleaved: true
        )!
        micConverter = AVAudioConverter(from: inputFormat, to: micTarget)
        if micConverter == nil {
            os_log("startMic: AVAudioConverter init failed (input=%{public}@ → 16kHz mono S16LE)",
                   log: Self.log, type: .error, String(describing: inputFormat))
        }

        // 100 ms tap @ input rate; the converter sizes the output buffer for us.
        let bufferSize = AVAudioFrameCount(inputFormat.sampleRate / 10)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.handleMicTap(buffer)
        }

        do {
            if !engineStarted {
                try engine.start()
                engineStarted = true
                os_log("startMic: engine started", log: Self.log, type: .debug)
            }
        } catch {
            os_log("startMic: engine.start failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
        }
    }

    public func stopMic() {
        stateLock.lock()
        if !micActive {
            stateLock.unlock()
            return
        }
        micActive = false
        micFrameHandler = nil
        stateLock.unlock()

        engine.inputNode.removeTap(onBus: 0)
        micConverter = nil
        os_log("stopMic", log: Self.log, type: .debug)
    }

    private func handleMicTap(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let active = micActive
        let handler = micFrameHandler
        let converter = micConverter
        stateLock.unlock()
        guard active, let handler = handler, let converter = converter else { return }

        let outputCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * Double(Self.micSampleRate) / buffer.format.sampleRate + 16
        )
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputCapacity
        ) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error || error != nil {
            os_log("mic convert failed: %{public}@", log: Self.log, type: .error,
                   error?.localizedDescription ?? "unknown")
            return
        }
        guard let int16Data = outBuffer.int16ChannelData else { return }
        let frameCount = Int(outBuffer.frameLength)
        guard frameCount > 0 else { return }
        let byteCount = frameCount * MemoryLayout<Int16>.size
        let data = Data(bytes: int16Data[0], count: byteCount)
        handler(data)
    }

    // ── TTS playback ───────────────────────────────────────────────

    /// Queue a 24 kHz mono S16LE payload for playback. Caller-thread safe.
    public func enqueueTts(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        let sampleCount = pcm.count / 2
        guard sampleCount > 0 else { return }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.ttsSampleRate),
            channels: 1,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)
        guard let channel = buffer.floatChannelData?[0] else { return }
        let gain = ttsGain
        pcm.withUnsafeBytes { raw in
            let src = raw.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let scaled = Float(src[i]) * gain / 32768.0
                channel[i] = max(-1.0, min(1.0, scaled))
            }
        }

        ensurePlayerEngineStarted()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        if !playerNode.isPlaying { playerNode.play() }
    }

    /// Drop all queued TTS audio. Used on barge-in.
    public func flushTts() {
        playerNode.stop()
        // Re-arm so the next `enqueueTts` can resume cleanly.
        playerNode.reset()
    }

    private func ensurePlayerEngineStarted() {
        do {
            if !engineStarted {
                AudioOutputManager.shared.applyMode()
                try engine.start()
                engineStarted = true
                os_log("ensurePlayerEngineStarted: engine started", log: Self.log, type: .debug)
            }
        } catch {
            os_log("engine.start failed: %{public}@", log: Self.log, type: .error,
                   error.localizedDescription)
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────

    /// Tear down both mic and playback. Idempotent.
    public func release() {
        stopMic()
        playerNode.stop()
        playerNode.reset()
        if engineStarted {
            engine.stop()
            engineStarted = false
        }
    }

    // ── Utilities ──────────────────────────────────────────────────

    /// 24 kHz mono S16LE → 16 kHz mono S16LE linear-interpolation downsample
    /// (3:2). Used by external-audio mode to push headset-ready PCM back to
    /// the orchestrator. Mirrors the Kotlin implementation in
    /// `StsVolcengineService` / `AstVolcengineService`.
    public static func downsample24kTo16k(_ input: Data) -> Data {
        guard input.count >= 2 else { return input }
        let inSamples = input.count / 2
        let outSamples = (inSamples * 2) / 3
        guard outSamples > 0 else { return Data() }
        var out = Data(count: outSamples * 2)
        input.withUnsafeBytes { srcRaw in
            let src = srcRaw.bindMemory(to: Int16.self)
            out.withUnsafeMutableBytes { dstRaw in
                let dst = dstRaw.bindMemory(to: Int16.self)
                for i in 0..<outSamples {
                    let srcIdx2 = i * 3
                    let baseIdx = srcIdx2 / 2
                    let frac = srcIdx2 % 2
                    let s0 = Int(src[baseIdx])
                    let s1 = baseIdx + 1 < inSamples ? Int(src[baseIdx + 1]) : s0
                    let interp = frac == 0 ? s0 : (s0 + s1) / 2
                    dst[i] = Int16(truncatingIfNeeded: interp)
                }
            }
        }
        return out
    }
}
