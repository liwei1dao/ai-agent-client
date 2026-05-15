import Foundation
import JL_BLEKit

/// MODE_AUDIO_TRANSLATION（mode=4）—— 把外部音频文件 PCM 灌入翻译通路。
public final class AudioTranslationModeHandler: BaseTranslationModeHandler {

    private var sampleRate = 16000

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_AUDIO_TRANSLATION,
            inputs: [TranslationStreams.IN_AUDIO_FILE],
            outputs: [TranslationStreams.OUT_LOCAL_PLAYBACK]
        )
    }

    public override func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let server = server else { completion(false, "server uninitialized"); return }
        if working { completion(true, nil); return }
        let address = args["address"] as? String
        let session = address.flatMap { server.translationSession(for: $0) } ?? server.currentTranslationSession()
        guard let s = session else {
            emitError(-200, "no connected device")
            completion(false, "no connected device"); return
        }
        let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
        sampleRate = sr
        self.session = s

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            tm.recordtype = .byPhone
            let mode = Self.buildMode(modeType: .audioTranslate, audioType: .PCM, channel: 1, sampleRate: sr)
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                if status == .success || status == .sameMode {
                    self.working = true
                    completion(true, nil)
                } else {
                    self.emitError(Int(status.rawValue), err?.localizedDescription)
                    self.stop()
                    completion(false, "tm status=\(status.rawValue)")
                }
            }
        }
    }

    public override func stop() {
        guard let s = session, working else { working = false; return }
        working = false
        s.release(owner: self)
        emitLog("AudioTranslation stop")
    }

    /// 与 Android `AudioTranslationModeHandler.feedFilePcm` 对齐：通过 `trWriteAudio`+
    /// `sourceType = .typeFile` 把外部解出的 PCM 灌入翻译通路。
    public func feedFilePcm(_ pcm: Data, sampleRate: Int) -> Bool {
        guard working, let tm = session?.currentManager() else { return false }
        let audio = JLTranslateAudio()
        audio.sourceType = .typeFile
        audio.audioType = .PCM
        audio.data = pcm
        audio.len = Int32(pcm.count)
        audio.count = 1
        tm.trWriteAudioV2(audio, translate: pcm)
        return true
    }

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        guard working else { return }
        // 音频翻译模式 SDK 把译后 PCM 反推到本地播放：作为 `out.localPlayback` 输出
        if audio.audioType == .PCM {
            pushFrame(streamId: TranslationStreams.OUT_LOCAL_PLAYBACK, pcm: audio.data,
                      format: AudioFormat(sampleRate: sampleRate, channels: 1, bitsPerSample: 16))
        }
    }
}

/// MODE_FACE_TO_FACE_TRANSLATION（mode=5）—— 面对面翻译，双麦阵列。
public final class FaceToFaceTranslationModeHandler: BaseTranslationModeHandler {

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_FACE_TO_FACE_TRANSLATION,
            inputs: [TranslationStreams.IN_MIC],
            outputs: [TranslationStreams.OUT_LOCAL_PLAYBACK]
        )
    }

    public override func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let server = server else { completion(false, "server uninitialized"); return }
        if working { completion(true, nil); return }
        let address = args["address"] as? String
        let session = address.flatMap { server.translationSession(for: $0) } ?? server.currentTranslationSession()
        guard let s = session else {
            emitError(-200, "no connected device")
            completion(false, "no connected device"); return
        }
        let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
        self.session = s

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            tm.recordtype = .byDevice
            let mode = Self.buildMode(modeType: .faceToFaceTranslate, audioType: .OPUS, channel: 1, sampleRate: sr)
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                if status == .success || status == .sameMode {
                    self.working = true
                    completion(true, nil)
                } else {
                    self.emitError(Int(status.rawValue), err?.localizedDescription)
                    self.stop()
                    completion(false, "tm status=\(status.rawValue)")
                }
            }
        }
    }

    public override func stop() {
        guard let s = session, working else { working = false; return }
        working = false
        s.release(owner: self)
        emitLog("FaceToFaceTranslation stop")
    }

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        guard working else { return }
        let encoding: String
        switch audio.audioType {
        case .PCM: encoding = "pcm16"
        case .OPUS: encoding = "opus"
        case .SPEEX: encoding = "speex"
        case .JLA_V2: encoding = "jla_v2"
        case .MSBC: encoding = "msbc"
        default: encoding = "unknown"
        }
        pushFrame(streamId: TranslationStreams.IN_MIC, pcm: audio.data, encoding: encoding)
    }
}
