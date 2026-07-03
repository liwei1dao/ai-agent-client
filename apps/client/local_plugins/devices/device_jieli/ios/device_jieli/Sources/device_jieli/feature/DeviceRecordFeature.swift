import Flutter
import Foundation
import JL_BLEKit

/// 设备录音通路（iOS）—— 与 Android `DeviceRecordFeature + JieliDeviceRecordPort` 对齐。
///
/// # 通路细节（与 Android 一致）
///   - 进入 `MODE_CALL_RECORD(7)` + `recordtype = .byDevice` + `channel = 2`
///   - 耳机一路推 SOURCE_E_SCO_MIX 立体声 OPUS（L=本端 / R=对端）
///   - 内部用 `OpusStreamDecoder(channels=2, dataSize=80)` 解码成 16k/16bit/stereo 交织 PCM
///   - 通过 `deviceRecordAudio` EventChannel 外抛（streamId = "in.stereo"）
///
/// # 真机注意
/// mode=7 是专门的通话录音通路（与 mode=6 通话翻译互斥），耳机固件持续上推 SCO_MIX
/// 双声道交织 OPUS，不再像 mode=6 那样需要真实 SCO 通话才上行。
///
/// # 与 mode=6 的历史
/// 早先此通路下发的是 `MODE_CALL_TRANSLATION_WITH_STEREO(6)`，与 Android 对齐后
/// 固件侧切换到专用的 `MODE_CALL_RECORD(7)`；`JLTranslateSetModeType` Obj-C 枚举
/// 只显式到 0x06，所以这里用 KVC 写 `modeType = 7` 下发给设备。
public final class DeviceRecordFeature: NSObject, TranslationSessionOwner {

    private weak var server: JieliHomeServer?
    private var session: TranslationSession?
    private var decoder: OpusStreamDecoder?
    private(set) public var isRecording: Bool = false
    private var deviceAddress: String?
    private var sampleRate = 16000

    public var sessionModeId: Int { TranslationModeIds.MODE_CALL_RECORD }

    init(server: JieliHomeServer) {
        self.server = server
        super.init()
    }

    public func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let server = server, !isRecording else {
            completion(false, "already recording"); return
        }
        let addressArg = args["address"] as? String
        let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000

        let session = addressArg.flatMap { server.translationSession(for: $0) }
            ?? server.currentTranslationSession()
        guard let s = session else {
            emitError("device.record.no_device", code: -1, message: "no connected device")
            completion(false, "no connected device"); return
        }
        self.session = s
        self.sampleRate = sr
        self.deviceAddress = addressArg ?? server.currentConnectedEntity()?.mUUID

        // 立体声 OPUS 解码：单帧 80 B / 16k / stereo
        decoder = OpusStreamDecoder(channels: 2, dataSize: 80, sampleRate: sr) { [weak self] stereoPcm in
            self?.emitStereoFrame(stereoPcm)
        } onError: { [weak self] code, msg in
            self?.emitError("device.record.decode_failed", code: code, message: "opus stereo: \(msg ?? "")")
        }

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.cleanup()
                self.emitError("device.record.session_busy", code: -2, message: errMsg)
                completion(false, errMsg)
                return
            }
            tm.recordtype = .byDevice
            // `JLTranslateSetModeType` 枚举只到 0x06，MODE_CALL_RECORD(7) 不是合法 enum case。
            // 通过 KVC 写 modeType，绕开 Swift 枚举校验，底层 Obj-C 仅存 NSUInteger，
            // 会原值透传给固件（与 CallRecordModeHandler 完全一致）。
            let mode = JLTranslateSetMode()
            mode.dataType = .OPUS
            mode.channel = 2
            mode.sampleRate = sr
            mode.setValue(NSNumber(value: 7), forKey: "modeType")
            NSLog("[DeviceRecord] trStartTranslate mode=MODE_CALL_RECORD(0x07) dataType=OPUS ch=2 sr=\(sr) recordType=byDevice")
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                if status == .success || status == .sameMode {
                    self.isRecording = true
                    self.server?.dispatcher.send([
                        "type": "deviceRecordStart",
                        "address": self.deviceAddress as Any,
                        "sampleRate": sr,
                        "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
                    ])
                    completion(true, nil)
                } else {
                    self.cleanup()
                    self.emitError("device.record.enter_failed", code: Int(status.rawValue),
                                   message: err?.localizedDescription ?? "trStartTranslateMode status=\(status.rawValue)")
                    completion(false, "tm status=\(status.rawValue)")
                }
            }
        }
    }

    public func stop() {
        guard isRecording else { cleanup(); return }
        isRecording = false
        session?.release(owner: self)
        let addr = deviceAddress
        cleanup()
        server?.dispatcher.send([
            "type": "deviceRecordStop",
            "address": addr as Any,
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
        ])
    }

    // MARK: - TranslationSessionOwner

    public func onReceiveAudio(_ audio: JLTranslateAudio) {
        guard isRecording else { return }
        // mode=7 与 mode=6 一致：SDK 把上行帧 source 标成 .typeESCOMax (SOURCE_E_SCO_MIX)；其他 source 忽略
        guard audio.sourceType == .typeESCOMax else { return }
        switch audio.audioType {
        case .OPUS: decoder?.feed(audio.data)
        case .PCM: emitStereoFrame(audio.data)
        default: break
        }
    }

    public func onModeChange(_ mode: JLTranslateSetMode) {
        if mode.modeType == .idle && isRecording {
            emitError("device.record.mode_exited", code: -1,
                      message: "headset exited MODE=7 → MODE_IDLE")
            stop()
        }
    }

    public func onError(_ error: NSError) {
        emitError("device.record.translation_error", code: error.code, message: error.localizedDescription)
    }

    // MARK: - Helpers

    private func emitStereoFrame(_ pcm: Data) {
        server?.dispatcher.send([
            "type": "deviceRecordAudio",
            "address": deviceAddress as Any,
            "streamId": "in.stereo",
            "sampleRate": sampleRate,
            "channels": 2,
            "bitsPerSample": 16,
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
            "pcm": FlutterStandardTypedData(bytes: pcm),
        ])
    }

    private func emitError(_ code: String, code intCode: Int, message: String?) {
        server?.dispatcher.send([
            "type": "deviceRecordError",
            "address": deviceAddress as Any,
            "code": intCode,
            "message": message as Any,
            "errorCode": code,
        ])
    }

    private func cleanup() {
        decoder?.release()
        decoder = nil
        session = nil
    }
}
