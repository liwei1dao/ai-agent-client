import Foundation
import JL_BLEKit

/// 设备主动推送的状态事件（电量 / 通话状态 / 系统信息 / 耳机广播）。
///
/// 与 Android `DeviceInfoEventForwarder` 对齐，覆盖：
///   - `battery`          — 电量变化（来源：`kJL_MANAGER_HEADSET_ADV` 通知里的 POWER_C/L/R，
///                          以及 `kJL_MANAGER_SYSTEM_INFO` 通知里 JLModel_Device.battery 字段）
///   - `phoneCallStatus`  — 通话状态（来源：`kJL_MANAGER_CALL_STATUS`）
///
/// iOS SDK 没有像 Android `OnRcspEventListener.onBatteryChange` 那种细粒度推送，电量更新
/// 都是间接通过广播 / 系统信息走的。我们订阅两条通知，把每次推上来的最新值统一外抛 `battery`。
public final class DeviceInfoEventForwarder: NSObject {

    private weak var server: JieliHomeServer?
    private var lastBatteryByDevice: [String: Int] = [:]

    public init(server: JieliHomeServer) {
        self.server = server
    }

    public func attach() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onCallStatus(_:)),
                       name: NSNotification.Name(kJL_MANAGER_CALL_STATUS), object: nil)
        nc.addObserver(self, selector: #selector(onHeadsetAdv(_:)),
                       name: NSNotification.Name(kJL_MANAGER_HEADSET_ADV), object: nil)
        nc.addObserver(self, selector: #selector(onSystemInfo(_:)),
                       name: NSNotification.Name(kJL_MANAGER_SYSTEM_INFO), object: nil)
        nc.addObserver(self, selector: #selector(onTargetInfo(_:)),
                       name: NSNotification.Name(kJL_MANAGER_TARGET_INFO), object: nil)
    }

    public func detach() {
        NotificationCenter.default.removeObserver(self)
    }

    deinit { detach() }

    // MARK: - Notifications → events

    @objc private func onCallStatus(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let uuid = info[kJL_MANAGER_KEY_UUID] as? String
        // payload 一般是 status (NSNumber) 或对象，按 SDK 习惯取 intValue
        var status: Int = 0
        if let n = info[kJL_MANAGER_KEY_OBJECT] as? NSNumber {
            status = n.intValue
        } else if let n = info[kJL_MANAGER_KEY_OBJECT] as? Int {
            status = n
        } else if let dict = info[kJL_MANAGER_KEY_OBJECT] as? [String: Any] {
            status = (dict["status"] as? NSNumber)?.intValue ?? 0
        }
        server?.dispatcher.send([
            "type": "phoneCallStatus",
            "address": uuid as Any,
            "status": status,
        ])
    }

    @objc private func onHeadsetAdv(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let uuid = info[kJL_MANAGER_KEY_UUID] as? String
        guard let raw = info[kJL_MANAGER_KEY_OBJECT] as? [String: Any] else { return }
        // 广播里 POWER_C 是充电仓电量，POWER_L/R 是左右耳；Android 端 `battery` 取的是
        // 综合电量。这里优先取仓位（最常用于显示），再回退左/右耳的最小值。
        let pc = (raw["POWER_C"] as? NSNumber)?.intValue
        let pl = (raw["POWER_L"] as? NSNumber)?.intValue
        let pr = (raw["POWER_R"] as? NSNumber)?.intValue
        let level: Int? = pc ?? [pl, pr].compactMap { $0 }.min()
        guard let lv = level else { return }
        if let id = uuid, lastBatteryByDevice[id] == lv { return }
        if let id = uuid { lastBatteryByDevice[id] = lv }
        server?.dispatcher.send([
            "type": "battery",
            "address": uuid as Any,
            "level": lv,
            "left": pl as Any,
            "right": pr as Any,
            "case": pc as Any,
        ])
    }

    @objc private func onSystemInfo(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let uuid = info[kJL_MANAGER_KEY_UUID] as? String
        // 系统信息推送时拉一次最新 model
        guard let id = uuid, let entity = server?.connectedEntity(forUuid: id) else { return }
        let model = entity.mCmdManager.getDeviceModel()
        let lv = Int(model.battery)
        if lastBatteryByDevice[id] == lv { return }
        lastBatteryByDevice[id] = lv
        server?.dispatcher.send([
            "type": "battery",
            "address": id,
            "level": lv,
        ])
    }

    @objc private func onTargetInfo(_ note: Notification) {
        // 设备配对成功后 SDK 会自动拉一次 TargetInfo；与 Android RcspInit 完成时机对齐。
        guard let info = note.userInfo as? [String: Any] else { return }
        let uuid = (info[kJL_MANAGER_KEY_UUID] as? String) ?? ""
        server?.dispatcher.send([
            "type": "rcspInit",
            "address": uuid,
            "code": 0,
        ])
    }
}
