import Foundation
import JL_BLEKit

/// 查询设备静态信息（电量 / 版本 / VID-PID 等）。
///
/// - `snapshot(address:)` 直接读 iOS SDK 缓存（连接成功后 BleManager 已经
///   触发过 `cmdTargetFeatureResult`）。
/// - `queryTargetInfo(address:mask:)` 主动再向设备拉一次最新值。
public final class DeviceInfoFeature {

    private weak var server: JieliHomeServer?
    init(server: JieliHomeServer) { self.server = server }

    public func snapshot(address: String) -> [String: Any?]? {
        guard let entity = server?.connectedEntity(forUuid: address) else { return nil }
        let m = entity.mCmdManager.getDeviceModel()
        let pidvidParts = (m.pidvid ?? "").split(separator: "-")
        let vid: String? = pidvidParts.count >= 1 ? String(pidvidParts[0]) : nil
        let pid: String? = pidvidParts.count >= 2 ? String(pidvidParts[1]) : nil
        return [
            "address": entity.mUUID ?? address,
            "battery": Int(m.battery),
            "volume": Int(m.currentVol),
            "maxVolume": Int(m.maxVol),
            "versionCode": nil, // iOS SDK 只暴露 versionFirmware（字符串），与 Android versionCode 含义不同
            "versionName": m.versionFirmware ?? "",
            "name": entity.mPeripheral.name ?? "",
            "vid": vid,
            "pid": pid,
            "uid": m.license ?? "",
            "edrAddr": entity.mEdr ?? m.btAddr ?? "",
        ]
    }

    public func queryTargetInfo(
        address: String,
        mask: Int,
        completion: @escaping (_ info: [String: Any?]?, _ errCode: Int?, _ errMsg: String?) -> Void
    ) {
        guard let entity = server?.connectedEntity(forUuid: address) else {
            completion(nil, -1, "remote device not found"); return
        }
        let cmd = entity.mCmdManager
        // iOS SDK 的 mask 走"选择性获取"接口
        cmd.cmdGetSystemInfo(.COMMON, selectionBit: UInt32(mask)) { [weak self] status, _, _ in
            guard let self = self else { return }
            if status == .success {
                completion(self.snapshot(address: address), nil, nil)
            } else {
                completion(nil, Int(status.rawValue), "cmd status=\(status.rawValue)")
            }
        }
    }
}
