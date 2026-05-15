import Foundation
import JL_BLEKit

/// MODE_CALL_TRANSLATION_WITH_STEREO（mode=6）—— 立体声通话翻译。
///
/// 与 Android `StereoCallTranslationModeHandler` 对齐：
///   - 耳机一路推 SOURCE_E_SCO_MIX 立体声 OPUS：L=本端 uplink, R=对端 downlink
///   - 软件分声道后等价于 [CallTranslationModeHandler]
public final class StereoCallTranslationModeHandler: BaseTranslationModeHandler {

    private var decoder: OpusStreamDecoder?
    private var encoderUplink: OpusStreamEncoder?
    private var encoderDownlink: OpusStreamEncoder?
    private var sampleRate = 16000
    private var audioType: JL_SpeakDataType = .OPUS

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_CALL_TRANSLATION_WITH_STEREO,
            inputs: [TranslationStreams.IN_UPLINK, TranslationStreams.IN_DOWNLINK],
            outputs: [TranslationStreams.OUT_UPLINK, TranslationStreams.OUT_DOWNLINK]
        )
    }

    public override func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let server = server else { completion(false, "server uninitialized"); return }
        if working { completion(true, nil); return }
        let address = args["address"] as? String
        let session: TranslationSession? = address.flatMap { server.translationSession(for: $0) } ?? server.currentTranslationSession()
        guard let s = session else {
            emitError(-200, "no connected device")
            completion(false, "no connected device"); return
        }
        let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
        let aType = Self.parseAudioType(args["audioType"]) ?? .OPUS
        let recordType = Self.parseRecordType(args["strategy"], default: .byDevice)
        sampleRate = sr
        audioType = aType
        self.session = s

        if aType == .OPUS {
            decoder = OpusStreamDecoder(channels: 2, dataSize: 80, sampleRate: sr) { [weak self] stereoPcm in
                guard let self = self else { return }
                let (l, r) = PcmKit.splitStereo16(stereoPcm)
                let fmt = AudioFormat(sampleRate: sr, channels: 1, bitsPerSample: 16)
                self.pushFrame(streamId: TranslationStreams.IN_UPLINK, pcm: l, format: fmt)
                self.pushFrame(streamId: TranslationStreams.IN_DOWNLINK, pcm: r, format: fmt)
            } onError: { [weak self] code, msg in
                self?.emitError(code, "opus stereo decode: \(msg ?? "")")
            }
            encoderUplink = OpusStreamEncoder(channels: 1, sampleRate: sr) { [weak self] opus in
                self?.writeBack(opus, source: .typeESCOUp)
            }
            encoderDownlink = OpusStreamEncoder(channels: 1, sampleRate: sr) { [weak self] opus in
                self?.writeBack(opus, source: .typeESCODown)
            }
        }

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            tm.recordtype = recordType
            let mode = Self.buildMode(modeType: .callTranslateStereo, audioType: aType, channel: 2, sampleRate: sr)
            self.emitLog("StereoCallTranslation start audioType=\(aType.rawValue) sr=\(sr) recordType=\(recordType.rawValue)")
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                if status == .success || status == .sameMode {
                    self.working = true
                    completion(true, nil)
                } else {
                    self.emitError(Int(status.rawValue), err?.localizedDescription ?? "trStartTranslateMode failed")
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
        decoder?.release(); decoder = nil
        encoderUplink?.release(); encoderUplink = nil
        encoderDownlink?.release(); encoderDownlink = nil
        emitLog("StereoCallTranslation stop")
    }

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        guard working else { return }
        guard audio.sourceType == .typeESCOMax else { return }  // SOURCE_E_SCO_MIX
        switch audio.audioType {
        case .OPUS: decoder?.feed(audio.data)
        case .PCM:
            let (l, r) = PcmKit.splitStereo16(audio.data)
            let fmt = AudioFormat(sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
            pushFrame(streamId: TranslationStreams.IN_UPLINK, pcm: l, format: fmt)
            pushFrame(streamId: TranslationStreams.IN_DOWNLINK, pcm: r, format: fmt)
        default: break
        }
    }

    public override func onTranslatedAudio(streamId: String, pcm: Data, format: AudioFormat, isFinal: Bool) -> Bool {
        guard working else { return false }
        let encoder: OpusStreamEncoder?
        let source: JLTranslateAudioSourceType
        switch streamId {
        case TranslationStreams.OUT_UPLINK: encoder = encoderUplink; source = .typeESCOUp
        case TranslationStreams.OUT_DOWNLINK: encoder = encoderDownlink; source = .typeESCODown
        default: return false
        }
        if audioType == .OPUS {
            let frameBytes = 640
            var ofs = 0
            while ofs < pcm.count {
                let len = min(frameBytes, pcm.count - ofs)
                encoder?.feed(pcm.subdata(in: ofs..<(ofs + len)))
                ofs += len
            }
        } else {
            writeBack(pcm, source: source, audioType: .PCM)
        }
        return true
    }

    private func writeBack(_ data: Data, source: JLTranslateAudioSourceType, audioType: JL_SpeakDataType? = nil) {
        guard let tm = session?.currentManager() else { return }
        let audio = JLTranslateAudio()
        audio.sourceType = source
        audio.audioType = audioType ?? self.audioType
        audio.data = data
        audio.len = Int32(data.count)
        audio.count = 1
        tm.trWriteAudioV2(audio, translate: data)
    }
}
