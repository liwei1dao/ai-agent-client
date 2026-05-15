import Foundation
import JL_BLEKit

/// MODE_CALL_RECORD（mode=7）—— 通话录音（设备采集，无 TTS 回写）。
///
/// 与 Android `JieliDeviceRecordPort` 对齐：
///   - 下发 `mode=7 / audioType=OPUS / channel=2 / sampleRate=16k / recordtype=byDevice`
///   - 耳机持续上推 `SOURCE_E_SCO_MIX` 双声道交织 OPUS（L=本端 / R=对端）
///   - `OpusStreamDecoder(channels=2, dataSize=80)` 解码成 16k/16bit/stereo 交织 PCM
///   - 以单路 `in.stereo` 向 Dart 抛 PCM；**无 output 流**，不接 TTS 回写
///
/// 与 [StereoCallTranslationModeHandler]（mode=6）的区别：
///   - mode=6 是立体声"通话翻译"：耳机把 mix 上推、APP 可把译文回写给耳机
///   - mode=7 是专门的"通话录音"：只采集，不回写，固件通路与通话翻译互斥
///
/// 注：SDK 的 `JLTranslateSetModeType` 枚举没有 0x07，但它是 `NS_ENUM(NSUInteger, …)`，
/// 可以用 `JLTranslateSetModeType(rawValue: 7)` 构造未命名 case 下发到设备。
public final class CallRecordModeHandler: BaseTranslationModeHandler {

    private var decoder: OpusStreamDecoder?
    private var sampleRate = 16000
    private var audioType: JL_SpeakDataType = .OPUS
    private var rxFrameCount: Int64 = 0
    private var rxBytes: Int64 = 0
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "callrecord.heartbeat", qos: .utility)

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_CALL_RECORD,
            inputs: [TranslationStreams.IN_STEREO],
            outputs: []
        )
    }

    public override func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        print("[CallRecord] start ENTRY args=\(args)")
        guard let server = server else {
            completion(false, "server uninitialized"); return
        }
        if working {
            print("[CallRecord] start already working, returning ok")
            completion(true, nil); return
        }

        let address = args["address"] as? String
        let session: TranslationSession? = {
            if let addr = address { return server.translationSession(for: addr) }
            return server.currentTranslationSession()
        }()
        guard let s = session else {
            emitError(-200, "no connected device; pass args.address or connect first")
            completion(false, "no connected device"); return
        }

        let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
        let aType = Self.parseAudioType(args["audioType"]) ?? .OPUS
        // 通话录音固件通路强制由耳机侧采集；`byPhone` 不适用，这里默认并只允许 byDevice。
        let recordType = Self.parseRecordType(args["strategy"], default: .byDevice)
        print("[CallRecord] start params sr=\(sr) audioType=\(aType.rawValue) recordType=\(recordType.rawValue)")

        sampleRate = sr
        audioType = aType
        self.session = s

        // 立体声 OPUS 解码：单帧 80 B（16k/16bit/stereo/20ms）。
        if aType == .OPUS {
            decoder = OpusStreamDecoder(channels: 2, dataSize: 80, sampleRate: sr) { [weak self] stereoPcm in
                self?.emitStereo(stereoPcm)
            } onError: { [weak self] code, msg in
                self?.emitError(code, "opus stereo decode: \(msg ?? "")")
            }
        }

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                print("[CallRecord] acquire FAIL err=\(errMsg ?? "nil")")
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            print("[CallRecord] acquire OK isSupportTranslate=\(tm.trIsSupportTranslate()) " +
                  "isPlayWithA2dp=\(tm.trIsPlayWithA2dp()) isWorking=\(tm.trIsWorking()) isCalling=\(tm.isCalling)")

            tm.recordtype = recordType
            // JLTranslateSetModeType 枚举只显式定义到 0x06，0x07 不是合法 enum case：
            // - `JLTranslateSetModeType(rawValue: 7)` 在 NS_ENUM 严格模式下会返回 nil
            // - 这里直接用 KVC 写 modeType 属性，绕过 Swift 枚举校验，底层 Obj-C
            //   仅存个 NSUInteger，enterMode 单测是按原值透传给设备的
            let mode = JLTranslateSetMode()
            mode.dataType = aType
            mode.channel = 2
            mode.sampleRate = sr
            mode.setValue(NSNumber(value: 7), forKey: "modeType")
            self.emitLog("CallRecord start audioType=\(aType.rawValue) sr=\(sr) recordType=\(recordType.rawValue) ch=2")
            print("[CallRecord] calling trStartTranslate mode=MODE_CALL_RECORD(0x07) dataType=\(aType.rawValue) ch=2 sr=\(sr)")
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                print("[CallRecord] trStartTranslate completion status=\(status.rawValue) err=\(err?.localizedDescription ?? "nil")")
                if status == .success || status == .sameMode {
                    self.working = true
                    NSLog("[CallRecord] ✅ 通话录音启动成功 (status=\(status.rawValue) mode=7 sr=\(sr) recordType=\(recordType.rawValue)) — 等待耳机 SCO_MIX 上行...")
                    self.startHeartbeat()
                    completion(true, nil)
                } else {
                    NSLog("[CallRecord] ❌ 通话录音启动失败 status=\(status.rawValue) err=\(err?.localizedDescription ?? "nil")")
                    self.emitError(Int(status.rawValue), err?.localizedDescription ?? "trStartTranslate failed")
                    self.stop()
                    completion(false, "tm status=\(status.rawValue)")
                }
            }
        }
    }

    public override func stop() {
        stopHeartbeat()
        guard let s = session, working else { working = false; return }
        working = false
        s.release(owner: self)
        decoder?.release(); decoder = nil
        NSLog("[CallRecord] 🛑 CallRecord stop (totalRxFrames=\(rxFrameCount) bytes=\(rxBytes))")
        emitLog("CallRecord stop")
    }

    // MARK: - Audio upstream (SDK → APP)

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        rxFrameCount &+= 1
        if rxFrameCount <= 5 || rxFrameCount % 100 == 1 {
            let msg = "[CallRecord/onRx] #\(rxFrameCount) working=\(working) " +
                      "source=\(audio.sourceType.rawValue) audioType=\(audio.audioType.rawValue) " +
                      "len=\(audio.data.count) count=\(audio.count)"
            NSLog("%@", msg)
            emitLog(msg)
        }
        guard working else { return }
        // mode=7 与 mode=6 一致：SDK 把上行帧 source 标成 .typeESCOMax (SOURCE_E_SCO_MIX)
        guard audio.sourceType == .typeESCOMax else {
            if rxFrameCount <= 5 || rxFrameCount % 100 == 1 {
                emitLog("[CallRecord/onRx] drop unhandled sourceType=\(audio.sourceType.rawValue)")
            }
            return
        }
        rxBytes &+= Int64(audio.data.count)
        switch audio.audioType {
        case .OPUS: decoder?.feed(audio.data)
        case .PCM: emitStereo(audio.data)
        default:
            // 其它编码暂不支持（通话录音固件只会推 OPUS/PCM），丢弃并打日志
            if rxFrameCount <= 5 || rxFrameCount % 100 == 1 {
                emitLog("[CallRecord/onRx] drop unsupported audioType=\(audio.audioType.rawValue)")
            }
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        rxFrameCount = 0
        rxBytes = 0
        let t = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        t.schedule(deadline: .now() + 2, repeating: 2.0)
        t.setEventHandler { [weak self] in
            guard let self = self, self.working else { return }
            if self.rxFrameCount == 0 {
                NSLog("[CallRecord/Heartbeat] ⚠️ 通话录音运行中，但耳机上行 0 帧 — 请确认设备是否处于真实通话状态（SCO_MIX 仅在通话期间上推）。")
            } else {
                NSLog("[CallRecord/Heartbeat] ✓ rx=\(self.rxFrameCount) 帧 bytes=\(self.rxBytes)")
            }
        }
        heartbeatTimer = t
        t.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // MARK: - Helpers

    private func emitStereo(_ pcm: Data) {
        pushFrame(
            streamId: TranslationStreams.IN_STEREO,
            pcm: pcm,
            format: AudioFormat(sampleRate: sampleRate, channels: 2, bitsPerSample: 16)
        )
    }
}
