import Foundation
import JL_BLEKit

/// 语音助手通路（cmd=4 / 5 / 210）。
///
/// 与 Android `SpeechFeature` 对齐。
///
/// # iOS 实现现状
/// iOS 杰理 SDK 的语音助手能力主要由 `JL_SpeechAIttsHandler` / `JLDevAudioAIttsHandler`
/// 提供，**它们的稳定上行帧路径与 Android 实测一致：依赖耳机端按键唤醒**——直接 APP
/// 端调 startRecord 通常只能拿到 START 回调，WORKING 帧不到货（详见 plugin
/// JIELI_SDK_COMMANDS.md "通路 A"）。
///
/// 因此当前实现只做"按钮触发的开始/停止 + 事件桥"，不去强行拉数据帧；当耳机端触发
/// 唤醒时，事件由 SDK 通知层进入，由 [TranslationFeature] 或 [AssistantBridge] 等
/// 其他通路接管。
public final class SpeechFeature {

    private weak var server: JieliHomeServer?
    public private(set) var isRecordingFlag: Bool = false

    init(server: JieliHomeServer) { self.server = server }

    public func isRecording(address: String?) -> Bool { isRecordingFlag }

    public func start(
        address: String?,
        voiceType: Int,
        sampleRate: Int,
        vadWay: Int,
        completion: @escaping (_ ok: Bool, _ msg: String?) -> Void
    ) {
        // iOS SDK 在 4.2 beta 包里没有把 cmd=4/5 的 startRecord 暴露成公开 Swift API；
        // 暂时把"开始"事件直接派发出去保持状态机一致，真正上行帧依赖耳机硬件唤醒。
        isRecordingFlag = true
        server?.dispatcher.send([
            "type": "speechStart",
            "address": address as Any,
            "voiceType": voiceType,
            "sampleRate": sampleRate * 1000, // Android 端语义：上报已转换成 Hz
            "vadWay": vadWay,
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
        ])
        completion(true, nil)
    }

    public func stop(
        address: String?,
        reason: Int,
        completion: @escaping (_ ok: Bool, _ msg: String?) -> Void
    ) {
        isRecordingFlag = false
        server?.dispatcher.send([
            "type": "speechEnd",
            "address": address as Any,
            "reason": reason,
            "message": "stop",
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
        ])
        completion(true, nil)
    }
}
