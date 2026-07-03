import Flutter
import Foundation
import JL_BLEKit

/// 翻译模式处理器协议。与 Android `TranslationModeHandler` 对齐：
///   - 声明自己消费哪些「输入流」、产出哪些「输出流」
///   - `start` 进入翻译模式，启动上下行通路
///   - `stop` 退出模式，释放编解码器
///   - `onTranslatedAudio` 接外部 TTS PCM，按输出流路由
public protocol TranslationModeHandler: TranslationSessionOwner {
    var modeId: Int { get }
    var inputStreams: [String] { get }
    var outputStreams: [String] { get }
    var isWorking: Bool { get }
    func start(args: [String: Any], completion: @escaping (_ ok: Bool, _ errMsg: String?) -> Void)
    func stop()
    func onTranslatedAudio(streamId: String, pcm: Data, format: AudioFormat, isFinal: Bool) -> Bool
}

/// 公共基类：维护 `working` 标志，提供 pushFrame / emitLog / emitError 等工具。
public class BaseTranslationModeHandler: NSObject, TranslationModeHandler {

    public let modeId: Int
    public let inputStreams: [String]
    public let outputStreams: [String]

    weak var server: JieliHomeServer?
    var session: TranslationSession?
    @objc dynamic var working: Bool = false

    public var isWorking: Bool { working }

    public var sessionModeId: Int { modeId }

    private var seq: Int64 = 0

    public init(server: JieliHomeServer, modeId: Int, inputs: [String], outputs: [String]) {
        self.server = server
        self.modeId = modeId
        self.inputStreams = inputs
        self.outputStreams = outputs
        super.init()
    }

    // 子类需要重写
    public func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        completion(false, "unimplemented")
    }
    public func stop() { working = false }
    public func onTranslatedAudio(streamId: String, pcm: Data, format: AudioFormat, isFinal: Bool) -> Bool { false }

    // TranslationSessionOwner
    public func onReceiveAudio(_ audio: JLTranslateAudio) {}
    public func onModeChange(_ mode: JLTranslateSetMode) {
        // 设备退出回到 IDLE 时收尾
        if mode.modeType == .idle && working {
            emitError(-1, "device exited mode → IDLE")
            stop()
        }
    }
    public func onError(_ error: NSError) { emitError(error.code, error.localizedDescription) }

    // MARK: - Helpers

    func pushFrame(
        streamId: String,
        pcm: Data,
        format: AudioFormat = AudioFormat(),
        isFinal: Bool = false,
        encoding: String = "pcm16"
    ) {
        seq &+= 1
        server?.dispatcher.send([
            "type": "translationAudio",
            "modeId": modeId,
            "streamId": streamId,
            "sampleRate": format.sampleRate,
            "channels": format.channels,
            "bitsPerSample": format.bitsPerSample,
            "encoding": encoding,
            "seq": NSNumber(value: seq),
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
            "final": isFinal,
            "pcm": FlutterStandardTypedData(bytes: pcm),
        ])
    }

    func emitLog(_ content: String) {
        server?.dispatcher.send([
            "type": "translationLog",
            "modeId": modeId,
            "content": content,
        ])
    }

    func emitError(_ code: Int, _ message: String?) {
        server?.dispatcher.send([
            "type": "translationError",
            "modeId": modeId,
            "code": code,
            "message": message as Any,
        ])
    }

    // MARK: - Mode helpers

    /// 解析常用枚举参数（audioType / strategy）
    static func parseAudioType(_ raw: Any?) -> JL_SpeakDataType? {
        if let s = raw as? String {
            switch s.lowercased() {
            case "opus": return .OPUS
            case "pcm": return .PCM
            case "speex": return .SPEEX
            case "jla_v2", "jlav2": return .JLA_V2
            case "msbc", "m_sbc": return .MSBC
            default: break
            }
        }
        if let n = (raw as? NSNumber)?.uint8Value {
            return JL_SpeakDataType(rawValue: n)
        }
        return nil
    }

    /// 解析录音策略（与 Android STRATEGY_DEVICE_ALWAYS_RECORDING / CUSTOM 对齐）
    static func parseRecordType(_ raw: Any?, default def: JLTranslateRecordType) -> JLTranslateRecordType {
        if let s = raw as? String {
            switch s.lowercased() {
            case "phone", "custom": return .byPhone
            case "device", "always": return .byDevice
            default: break
            }
        }
        if let n = (raw as? NSNumber)?.intValue {
            return JLTranslateRecordType(rawValue: n) ?? def
        }
        return def
    }

    /// 构造 SDK 的 JLTranslateSetMode
    static func buildMode(
        modeType: JLTranslateSetModeType,
        audioType: JL_SpeakDataType,
        channel: Int,
        sampleRate: Int
    ) -> JLTranslateSetMode {
        let m = JLTranslateSetMode()
        m.modeType = modeType
        m.dataType = audioType
        m.channel = channel
        m.sampleRate = sampleRate
        return m
    }
}
