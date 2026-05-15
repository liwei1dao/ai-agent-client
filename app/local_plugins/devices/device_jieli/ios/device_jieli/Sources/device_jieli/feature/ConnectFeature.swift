import CoreBluetooth
import Foundation
import JL_BLEKit

/// 连接 / 断开 / 状态查询 —— 与 Android `ConnectFeature` 对齐。
///
/// # 注意
/// - iOS 上 `address` 是 BLE 设备的 CoreBluetooth identifier (UUID 字符串)，
///   不是 BLE MAC（iOS 系统对 BLE MAC 全程匿名）。Android 端 `address` 是 MAC。
/// - 配对成功后**主动调一次 `cmdTargetFeatureResult`**，以拿到电量 / 版本 / vid-pid 等
///   基础信息——这一步与 Android `RCSPController.init` 后由 SDK 自动拉取的行为对齐。
///   完成后向 Dart 推 `rcspInit`，让上层确定 RCSP 已 ready。
///
/// # 一键双连（LE + BR/EDR 桥接）
/// Android 端默认走 SPP（经典蓝牙）拉音频通道；iOS 只能以 BLE 方式建连，但可以借助
/// `CBConnectPeripheralOptionEnableTransportBridgingKey`（WWDC19 引入，iOS 13+）
/// 提示系统"LE proximity 触发 BR/EDR connection"——要求设备支持 CTKD。
///
/// ## 实测坑（2026-05 验证）
/// **不要**在 `bleMultiple.connectEntity` 之前抢跑 `connect(options: bridging)`——
/// iOS 对同一 peripheral 的 connect 请求以**第一次的 options 为准** dedupe，后续 SDK
/// 的无 options connect 会被忽略；如果设备不支持 CTKD 或未配对，我们这条带 bridging
/// 的请求会卡死在等 CTKD，表现为 `peripheralState=0 → connectionState=2` 之后再也不
/// 前进，BLE 通路本身直接挂掉。
///
/// 正确做法：让 SDK 先正常把 BLE 建立好（`.paired/.connectRepeat`），**之后**再发
/// bridging hint——此时 iOS 会尝试做 CTKD → BR/EDR 升级但不影响已建立的 BLE 通路，
/// 设备不支持 CTKD 也只是升级失败，BLE 可用。并给一个 `dualConnect` 开关，默认关，
/// 由 Dart 侧在设备明确支持 CTKD 时打开。
public final class ConnectFeature {

    private weak var server: JieliHomeServer?

    init(server: JieliHomeServer) { self.server = server }

    public func connect(
        bleAddress: String,
        edrAddress: String?,
        deviceType: Int,
        connectWay: Int,
        dualConnect: Bool = false,
        completion: @escaping (_ ok: Bool, _ errMsg: String?) -> Void
    ) {
        guard let server = server else { completion(false, "server uninitialized"); return }
        let bleMultiple = server.bleMultiple

        let entity: JL_EntityM? = server.entity(forUuid: bleAddress)
            ?? bleMultiple.makeEntity(withUUID: bleAddress)
        guard let target = entity else {
            completion(false, "entity not found for uuid=\(bleAddress)")
            return
        }

        server.dispatcher.send([
            "type": "connectionState",
            "address": bleAddress,
            "state": 2, // CONNECTION_CONNECTING
        ])

        // ⚠️ 不在这里发 bridging hint——实测会把 BLE connect 卡死（见类注释）。
        //    只让 SDK 跑纯 BLE 正常流程，bridging 在 .paired 之后再补。
        NSLog("[JieliConnect] connect uuid=%@ edr=%@ deviceType=%ld connectWay=%ld dualConnect=%@",
              bleAddress, edrAddress ?? "nil", deviceType, connectWay,
              dualConnect ? "YES" : "NO")

        bleMultiple.connectEntity(target) { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .paired, .connectRepeat:
                // BLE 已建立。dualConnect=true 时尝试一次 BR/EDR 桥接升级——
                // 对不支持 CTKD 的设备不会影响已建立的 BLE 通路。
                if dualConnect {
                    ConnectFeature.requestTransportBridging(
                        centralManager: bleMultiple.getCenterManaer(),
                        peripheral: target.mPeripheral,
                        uuid: bleAddress
                    )
                }
                // 1) 触发一次 RCSP TargetFeature 拉取，等价于 Android 端 SDK 内部
                //    在 RCSPController.init 成功后自动做的事。
                target.mCmdManager.cmdTargetFeatureResult { [weak self] state, _, _ in
                    guard let self = self else { return }
                    let ok = state == .success
                    // 2) 拉取 COMMON 字段（电量 / 版本号等）填充 model 缓存，
                    //    供 deviceSnapshot() 读取。
                    if ok {
                        target.mCmdManager.cmdGetSystemInfo(.COMMON) { _, _, _ in }
                    }
                    self.server?.dispatcher.send([
                        "type": "rcspInit",
                        "address": target.mUUID ?? bleAddress,
                        "code": ok ? 0 : 1,
                    ])
                    completion(ok, ok ? nil : "rcsp init failed")
                }
            case .connecting:
                break
            case .bleOFF:
                completion(false, "ble off")
            case .connectFail:
                completion(false, "connect fail")
            case .connectTimeout:
                completion(false, "connect timeout")
            case .connectRefuse:
                completion(false, "connect refuse")
            case .pairFail:
                completion(false, "pair fail")
            case .pairTimeout:
                completion(false, "pair timeout")
            case .masterChanging:
                break
            case .disconnectOk:
                completion(false, "disconnected")
            case .null:
                completion(false, "entity null")
            @unknown default:
                completion(false, "unknown status \(status.rawValue)")
            }
        }
    }

    public func disconnect(address: String, completion: @escaping (_ ok: Bool, _ errMsg: String?) -> Void) {
        guard let server = server else { completion(false, "server uninitialized"); return }
        guard let entity = server.connectedEntity(forUuid: address) else {
            completion(false, "not connected: \(address)")
            return
        }
        // 断开前先收尾翻译 / 助理 / 设备录音，避免脏状态
        server.translationFeature.stop()
        server.assistantBridge.stop()
        server.deviceRecordFeature.stop()

        server.bleMultiple.disconnectEntity(entity) { _ in
            // 让翻译会话也一起释放
            server.removeTranslationSession(uuid: address)
            completion(true, nil)
        }
    }

    public func isConnected(address: String) -> Bool {
        guard let server = server else { return false }
        return server.connectedEntity(forUuid: address) != nil
    }

    public func connectedDeviceInfo() -> [String: Any?]? {
        guard let entity = server?.currentConnectedEntity() else { return nil }
        return [
            "address": entity.mUUID ?? "",
            "name": entity.mPeripheral.name ?? "",
        ]
    }

    // MARK: - Transport Bridging (LE → BR/EDR, WWDC19)

    /// 向系统申请把 LE 连接桥接到 BR/EDR，实现"一键双连"——
    /// 设备支持 CTKD 时，iOS 会在 BLE 建连同时自动拉起经典蓝牙，
    /// HFP / A2DP 等 Classic profile 会自动可用。
    ///
    /// 失败不抛错、不阻塞：设备不支持 CTKD 时，系统会忽略这个 option，
    /// 后续 SDK 的 `connectEntity` 照常走纯 LE 路径。
    private static func requestTransportBridging(
        centralManager: CBCentralManager?,
        peripheral: CBPeripheral?,
        uuid: String
    ) {
        guard let cm = centralManager, let p = peripheral else {
            NSLog("[JieliConnect] bridging skipped: centralManager/peripheral nil uuid=%@", uuid)
            return
        }
        // iOS 13+ 才有 CBConnectPeripheralOptionEnableTransportBridgingKey。
        if #available(iOS 13.0, *) {
            let options: [String: Any] = [
                CBConnectPeripheralOptionEnableTransportBridgingKey: true,
            ]
            NSLog("[JieliConnect] request BR/EDR bridging uuid=%@ peripheralState=%ld",
                  uuid, p.state.rawValue)
            cm.connect(p, options: options)
        } else {
            NSLog("[JieliConnect] bridging unavailable on iOS <13 uuid=%@", uuid)
        }
    }
}
