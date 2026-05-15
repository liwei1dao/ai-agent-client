import CoreBluetooth
import Foundation
import JL_BLEKit

/// 监听 iOS SDK 的 BLE 状态 / 连接通知，转成 Android 端同形态的事件 payload：
///   - adapterStatus  : { enabled, hasBle } ← 由 ScanFeature 内的 CBCentralManager 兜底派发；
///                                              这里也监听 SDK 的 kJL_BLE_M_ON / OFF 作为补充
///   - scanStatus     : { ble:true, started } ← ScanFeature 直接派发，这里不参与
///   - deviceFound    : { ...JieliDevice 字段 } ← ScanFeature 直接派发，这里不参与
///   - connectionState: { address, state }
///   - rcspInit       : { address, code }     ← iOS SDK 不区分；我们把"connected 后 cmdTargetFeature"成功视为 init OK
///
/// iOS SDK 通知名常量定义在 `JL_BLEMultiple.h`：
///   - kJL_BLE_M_ON / kJL_BLE_M_OFF
///   - kJL_BLE_M_ENTITY_CONNECTED / kJL_BLE_M_ENTITY_DISCONNECTED
public final class BluetoothEventForwarder: NSObject {

    private weak var server: JieliHomeServer?

    public init(server: JieliHomeServer) {
        self.server = server
    }

    public func attach() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onBleOn(_:)), name: NSNotification.Name(kJL_BLE_M_ON), object: nil)
        nc.addObserver(self, selector: #selector(onBleOff(_:)), name: NSNotification.Name(kJL_BLE_M_OFF), object: nil)
        nc.addObserver(self, selector: #selector(onConnected(_:)), name: NSNotification.Name(kJL_BLE_M_ENTITY_CONNECTED), object: nil)
        nc.addObserver(self, selector: #selector(onDisconnected(_:)), name: NSNotification.Name(kJL_BLE_M_ENTITY_DISCONNECTED), object: nil)
        // 注：扫描发现走 ScanFeature 内部的 CBCentralManager，SDK 的 kJL_BLE_M_FOUND
        // 通知（只对 Jieli 协议匹配的广播抛）这里不再监听，避免重复 / 路径冲突。
    }

    public func detach() {
        NotificationCenter.default.removeObserver(self)
    }

    deinit { detach() }

    // MARK: - Notification handlers

    @objc private func onBleOn(_ note: Notification) {
        server?.dispatcher.send([
            "type": "adapterStatus",
            "enabled": true,
            "hasBle": true,
        ])
    }

    @objc private func onBleOff(_ note: Notification) {
        server?.dispatcher.send([
            "type": "adapterStatus",
            "enabled": false,
            "hasBle": true,
        ])
    }

    @objc private func onConnected(_ note: Notification) {
        guard let entity = extractEntity(note) else { return }
        let address = entity.mUUID ?? ""
        server?.dispatcher.send([
            "type": "connectionState",
            "address": address,
            "state": 1, // CONNECTION_OK
        ])
        // 与 Android RcspInitEvent 等价：iOS SDK 在 connected 时已可发命令，
        // 这里直接把 init code=0 发出去，方便 Dart 侧的状态机走通
        server?.dispatcher.send([
            "type": "rcspInit",
            "address": address,
            "code": 0,
        ])
    }

    @objc private func onDisconnected(_ note: Notification) {
        // 通知 object 可能是 CBPeripheral 或 JL_EntityM
        let address: String = {
            if let entity = note.object as? JL_EntityM { return entity.mUUID ?? "" }
            if let peripheral = note.object as? CBPeripheral { return peripheral.identifier.uuidString }
            return ""
        }()
        server?.dispatcher.send([
            "type": "connectionState",
            "address": address,
            "state": 0, // CONNECTION_DISCONNECT
        ])
    }

    // MARK: - helpers

    private func extractEntity(_ note: Notification) -> JL_EntityM? {
        if let entity = note.object as? JL_EntityM { return entity }
        if let cbp = note.object as? CBPeripheral,
           let server = server {
            return server.entity(forUuid: cbp.identifier.uuidString)
        }
        return nil
    }
}
