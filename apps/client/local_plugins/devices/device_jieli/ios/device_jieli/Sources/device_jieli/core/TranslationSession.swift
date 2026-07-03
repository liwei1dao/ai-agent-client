import Foundation
import JL_BLEKit

/// 翻译管理器的"会话所有者"协议。
///
/// 与 Android 的"互斥"约束完全对齐：iOS SDK 一个设备只有一个 `JLTranslationManager`，
/// 同一时刻只能服务一个业务场景：
///   - `TranslationFeature.<某个 mode handler>`（翻译流）
///   - `AssistantBridge`（AI 助理：MODE_RECORD + 设备录音）
///   - `DeviceRecordFeature`（设备录音：MODE=7 + stereo + 设备录音）
///
/// 业务方 enter 时把自己注册为 `currentOwner`，所有 SDK 回调（onReceiveAudioData /
/// onModeChange / onError / onSendAudioQueueOver / isOnCalling）都会路由到它；exit 时
/// 主动让出所有权。中途被其他业务抢占时，先抢占方需要先调 [TranslationSession.release]。
public protocol TranslationSessionOwner: AnyObject {
    /// 与 Android `BaseTranslationModeHandler.modeId` 等价；用于日志和事件 payload
    var sessionModeId: Int { get }

    func onReceiveAudio(_ audio: JLTranslateAudio)
    func onModeChange(_ mode: JLTranslateSetMode)
    func onError(_ error: NSError)
    func onSendAudioQueueOver()
    func onCallingChange(_ isCalling: Bool)
}

public extension TranslationSessionOwner {
    func onSendAudioQueueOver() {}
    func onCallingChange(_ isCalling: Bool) {}
}

/// 单台已连接设备的翻译会话。
///
/// - 内部独占持有 [JLTranslationManager]，对外通过 [acquire] / [release] 协调使用方。
/// - 自身作为 `JLTranslationManagerDelegate`，把回调原样转发给 `currentOwner`。
///   若当前没有 owner，回调被静默丢弃（避免 SDK 在 exitMode 后还推一两帧把状态搅乱）。
public final class TranslationSession: NSObject, JLTranslationManagerDelegate {

    public let uuid: String
    private(set) public weak var manager: JL_ManagerM?

    private var tm: JLTranslationManager?
    private weak var currentOwner: TranslationSessionOwner?
    private let lock = NSRecursiveLock()
    private var rxAudioFrameCount: Int64 = 0

    init(uuid: String, manager: JL_ManagerM) {
        self.uuid = uuid
        self.manager = manager
        super.init()
    }

    public func acquire(
        owner: TranslationSessionOwner,
        completion: @escaping (_ tm: JLTranslationManager?, _ err: String?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        print("[JieliSession] acquire uuid=\(uuid) requesterModeId=\(owner.sessionModeId) " +
              "currentOwnerModeId=\(currentOwner?.sessionModeId.description ?? "nil") tmExists=\(tm != nil)")

        // 已有 owner：先让它退出（让位）。同一 owner 重复 acquire 直接复用。
        if let existing = currentOwner, existing !== owner {
            print("[JieliSession] acquire BUSY existingModeId=\(existing.sessionModeId) requesterModeId=\(owner.sessionModeId)")
            completion(nil, "translation session busy (sessionModeId=\(existing.sessionModeId))")
            return
        }
        currentOwner = owner

        if let tm = tm {
            print("[JieliSession] acquire OK (reused tm) ownerModeId=\(owner.sessionModeId)")
            completion(tm, nil); return
        }
        guard let manager = manager else {
            print("[JieliSession] acquire FAIL manager released")
            completion(nil, "manager released")
            return
        }
        print("[JieliSession] creating new JLTranslationManager ...")
        let inst = JLTranslationManager(delegate: self, manager: manager) { [weak self] success, err in
            guard let self = self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            print("[JieliSession] JLTranslationManager init result success=\(success) err=\(err?.localizedDescription ?? "nil")")
            if success {
                completion(self.tm, nil)
            } else {
                self.currentOwner = nil
                self.tm = nil
                completion(nil, err?.localizedDescription ?? "JLTranslationManager init failed")
            }
        }
        self.tm = inst
        inst.delegate = self
    }

    /// 让出所有权。会调 `trExitMode`，调用方应在 stop 路径里调它。
    public func release(owner: TranslationSessionOwner, completion: ((Bool) -> Void)? = nil) {
        lock.lock()
        if currentOwner === owner {
            currentOwner = nil
        }
        let tm = self.tm
        lock.unlock()
        guard let tm = tm else { completion?(true); return }
        tm.trExitMode { _, _ in completion?(true) }
    }

    /// 当前是否有 owner 在使用
    public var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return currentOwner != nil
    }

    /// 给只想"探测能力"的调用方用：不需要拿所有权
    public func currentManager() -> JLTranslationManager? {
        lock.lock(); defer { lock.unlock() }
        return tm
    }

    // MARK: - JLTranslationManagerDelegate

    public func onInitSuccess(_ uuid: String) {
        print("[JieliSession/SDK] onInitSuccess uuid=\(uuid)")
    }

    public func onModeChange(_ uuid: String, mode: JLTranslateSetMode) {
        print("[JieliSession/SDK] onModeChange uuid=\(uuid) modeType=\(mode.modeType.rawValue) " +
              "dataType=\(mode.dataType.rawValue) ch=\(mode.channel) sr=\(mode.sampleRate) " +
              "ownerModeId=\(currentOwnerSnapshot()?.sessionModeId.description ?? "nil")")
        currentOwnerSnapshot()?.onModeChange(mode)
    }

    public func onReceiveAudioData(_ uuid: String, audioData data: JLTranslateAudio) {
        rxAudioFrameCount &+= 1
        if rxAudioFrameCount <= 5 || rxAudioFrameCount % 100 == 1 {
            print("[JieliSession/SDK] onReceiveAudioData #\(rxAudioFrameCount) uuid=\(uuid) " +
                  "source=\(data.sourceType.rawValue) audioType=\(data.audioType.rawValue) " +
                  "len=\(data.data.count) count=\(data.count) " +
                  "ownerModeId=\(currentOwnerSnapshot()?.sessionModeId.description ?? "nil")")
        }
        currentOwnerSnapshot()?.onReceiveAudio(data)
    }

    public func onError(_ uuid: String, error: Error) {
        print("[JieliSession/SDK] onError uuid=\(uuid) err=\(error.localizedDescription)")
        currentOwnerSnapshot()?.onError(error as NSError)
    }

    public func onSendAudioQueueOver(_ uuid: String) {
        print("[JieliSession/SDK] onSendAudioQueueOver uuid=\(uuid)")
        currentOwnerSnapshot()?.onSendAudioQueueOver()
    }

    public func isOnCalling(_ isCalling: Bool, uuid: String) {
        print("[JieliSession/SDK] isOnCalling=\(isCalling) uuid=\(uuid) " +
              "ownerModeId=\(currentOwnerSnapshot()?.sessionModeId.description ?? "nil")")
        currentOwnerSnapshot()?.onCallingChange(isCalling)
    }

    private func currentOwnerSnapshot() -> TranslationSessionOwner? {
        lock.lock(); defer { lock.unlock() }
        return currentOwner
    }
}
