import Flutter
import Foundation
import JL_BLEKit

/// AI 助理通路（iOS）—— 与 Android `AssistantBridge + JieliAssistantPort` 对齐。
///
/// # 通路细节（与 Android 一致）
///   - 进入 `MODE_RECORD(1)` + `recordtype = .byDevice`（等价 STRATEGY_DEVICE_ALWAYS_RECORDING）
///   - 耳机持续推 OPUS 单声道帧；本类解码成 16k/16bit/mono PCM
///   - 上行帧通过 `assistantAudio` EventChannel 推给 Dart
///   - TTS 下行**不走** RCSP（iOS 同样让宿主走 AVAudioEngine + 系统蓝牙路由播放）
///
/// # 与 [TranslationFeature] 的关系
/// 两者都走同一个 [TranslationSession]，是设备级互斥的。`MethodRouter` 在调 `assistantStart`
/// 前会先 stop 翻译 / 设备录音。
public final class AssistantBridge: NSObject, TranslationSessionOwner {

    private weak var server: JieliHomeServer?
    private var session: TranslationSession?
    private var decoder: OpusStreamDecoder?
    private(set) public var isRunning: Bool = false
    private var sequence: Int64 = 0

    public var sessionModeId: Int { TranslationModeIds.MODE_RECORD }

    init(server: JieliHomeServer) {
        self.server = server
        super.init()
    }

    @discardableResult
    public func start(address: String? = nil, sampleRate: Int = 16000) -> Bool {
        guard let server = server, !isRunning else { return false }

        let session = address.flatMap { server.translationSession(for: $0) }
            ?? server.currentTranslationSession()
        guard let s = session else {
            emitError("device.assistant.no_device", "no connected device")
            return false
        }
        self.session = s

        // OPUS 解码器：单帧 40 B / 16k / mono，与 Android JieliAssistantPort packetSize=40 对齐
        decoder = OpusStreamDecoder(channels: 1, dataSize: 40, sampleRate: sampleRate) { [weak self] pcm in
            self?.emitAudioFrame(pcm: pcm, sampleRate: sampleRate)
        } onError: { [weak self] code, msg in
            self?.emitError("device.decoder_failed", "opus: code=\(code) msg=\(msg ?? "")")
        }

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                self.cleanup()
                self.emitError("device.assistant.session_busy", errMsg)
                return
            }
            tm.recordtype = .byDevice
            let mode = BaseTranslationModeHandler.buildMode(
                modeType: .onlyRecord, audioType: .OPUS, channel: 1, sampleRate: sampleRate
            )
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                if status == .success || status == .sameMode {
                    self.isRunning = true
                    self.server?.dispatcher.send([
                        "type": "assistantStart",
                        "sampleRate": sampleRate,
                        "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
                    ])
                } else {
                    self.cleanup()
                    self.emitError("device.assistant.enter_failed", err?.localizedDescription ?? "trStartTranslateMode status=\(status.rawValue)")
                }
            }
        }
        return true
    }

    public func stop() {
        guard isRunning else { cleanup(); return }
        isRunning = false
        let session = self.session
        session?.release(owner: self)
        cleanup()
        server?.dispatcher.send([
            "type": "assistantEnd",
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
        ])
    }

    // MARK: - TranslationSessionOwner

    public func onReceiveAudio(_ audio: JLTranslateAudio) {
        guard isRunning else { return }
        switch audio.audioType {
        case .OPUS: decoder?.feed(audio.data)
        case .PCM: emitAudioFrame(pcm: audio.data, sampleRate: 16000)
        default: break
        }
    }

    public func onModeChange(_ mode: JLTranslateSetMode) {
        if mode.modeType == .idle && isRunning {
            emitError("device.mode_exited", "headset exited MODE_RECORD → MODE_IDLE")
            stop()
        }
    }

    public func onError(_ error: NSError) {
        emitError("device.translation_error", "code=\(error.code) msg=\(error.localizedDescription)")
    }

    // MARK: - Helpers

    private func emitAudioFrame(pcm: Data, sampleRate: Int) {
        sequence &+= 1
        server?.dispatcher.send([
            "type": "assistantAudio",
            "encoding": "pcm16",
            "sampleRate": sampleRate,
            "channels": 1,
            "bitsPerSample": 16,
            "sequence": NSNumber(value: sequence),
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
            "pcm": FlutterStandardTypedData(bytes: pcm),
        ])
    }

    private func emitError(_ code: String, _ message: String?) {
        server?.dispatcher.send([
            "type": "assistantError",
            "code": code,
            "message": message as Any,
        ])
    }

    private func cleanup() {
        decoder?.release()
        decoder = nil
        session = nil
    }
}
