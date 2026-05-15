import Foundation
import JL_BLEKit

/// MODE_RECORD（mode=1）—— 单向录音翻译。
/// 与 Android `RecordModeHandler` 对齐：
///   - 通过 SDK 进入 RECORD 状态机；耳机 LED / 提示音随之切换
///   - 走 `recordtype=.byPhone` 语义（STRATEGY_CUSTOM_RECORDING）：APP 端自己采手机麦
///   - iOS 端 APP 录音用 AVAudioEngine 由宿主自定（Dart 侧已经在管音频采集）；本 handler 只做
///     翻译模式的状态机切换 + 接耳机上推帧（如果固件配成 byDevice 也支持）
public final class RecordModeHandler: BaseTranslationModeHandler {

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_RECORD,
            inputs: [TranslationStreams.IN_MIC],
            outputs: [TranslationStreams.OUT_SPEAKER]
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
        let aType = Self.parseAudioType(args["audioType"]) ?? .OPUS
        let recordType = Self.parseRecordType(args["strategy"], default: .byPhone)
        self.session = s

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            tm.recordtype = recordType
            let mode = Self.buildMode(modeType: .onlyRecord, audioType: aType, channel: 1, sampleRate: sr)
            self.emitLog("Record start audioType=\(aType.rawValue) sr=\(sr) recordType=\(recordType.rawValue)")
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
        emitLog("Record stop")
    }

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        // STRATEGY_CUSTOM_RECORDING 语义下耳机不上推；如果固件配成 byDevice 也直接外抛上行帧
        guard working else { return }
        switch audio.audioType {
        case .PCM:
            pushFrame(streamId: TranslationStreams.IN_MIC, pcm: audio.data)
        default:
            // 其他编码（OPUS 等）原样透传 + encoding 标注，避免内嵌解码器误用
            let encoding: String = {
                switch audio.audioType {
                case .OPUS: return "opus"
                case .SPEEX: return "speex"
                case .JLA_V2: return "jla_v2"
                case .MSBC: return "msbc"
                default: return "unknown"
                }
            }()
            pushFrame(streamId: TranslationStreams.IN_MIC, pcm: audio.data, encoding: encoding)
        }
    }

    public override func onTranslatedAudio(streamId: String, pcm: Data, format: AudioFormat, isFinal: Bool) -> Bool {
        // 与 Android 一致：RECORD 模式下耳机不参与回送 TTS；宿主自己用音频播放器播
        if streamId == TranslationStreams.OUT_SPEAKER {
            emitLog("recv tts pcm=\(pcm.count)B final=\(isFinal) (host-side playback)")
            return true
        }
        return false
    }
}

/// MODE_RECORDING_TRANSLATION（mode=2）—— 流式录音翻译。与 RecordModeHandler 仅 modeType 不同。
public final class RecordingTranslationModeHandler: BaseTranslationModeHandler {

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_RECORDING_TRANSLATION,
            inputs: [TranslationStreams.IN_MIC],
            outputs: [TranslationStreams.OUT_SPEAKER]
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
        let aType = Self.parseAudioType(args["audioType"]) ?? .OPUS
        let recordType = Self.parseRecordType(args["strategy"], default: .byPhone)
        self.session = s

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            tm.recordtype = recordType
            let mode = Self.buildMode(modeType: .recordTranslate, audioType: aType, channel: 1, sampleRate: sr)
            self.emitLog("RecordingTranslation start audioType=\(aType.rawValue) sr=\(sr) recordType=\(recordType.rawValue)")
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
        emitLog("RecordingTranslation stop")
    }

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        guard working else { return }
        if audio.audioType == .PCM {
            pushFrame(streamId: TranslationStreams.IN_MIC, pcm: audio.data)
        }
    }
}
