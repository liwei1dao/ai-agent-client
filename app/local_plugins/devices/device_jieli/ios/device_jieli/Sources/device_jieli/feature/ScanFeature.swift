import CoreBluetooth
import Foundation
import JL_BLEKit

/// BLE 扫描入口（iOS）—— 与 Android `feature/ScanFeature.kt` 对齐：
///
/// 1. **不**走 Jieli SDK 的 `JL_BLEMultiple.scanStart()`（其内部只对 Jieli 协议
///    匹配的广播抛 `kJL_BLE_M_FOUND`，且不支持按 16-bit UUID 过滤）。改用
///    `CBCentralManager` 原生扫描。
/// 2. UUID 白名单走 **OS 级过滤**：把 `CBUUID` 列表传给
///    `scanForPeripherals(withServices:)`，对应 Android 端
///    `ScanFilter.Builder().setServiceUuid(...)`。空列表 = 不过滤。
/// 3. 软过滤只剩 `nameList`（精确忽略大小写）+ `skipUnnamed`，对应 Android
///    `handleScanResult` 中的 in-code 过滤。
/// 4. 不在 native 层做 dedupe —— 每条 ADV 都派发 `deviceFound`，
///    对应 Android `CALLBACK_TYPE_ALL_MATCHES`（由 Dart 侧 `scannedDevices`
///    自行去重）。
///
/// 上报字段与 Android schema 1:1：
/// ```
/// {
///   type: "deviceFound",
///   name, address, edrAddr, deviceType, connectWay, rssi,
///   rawAdv,                              // ⚠️ iOS 仅 manufacturer hex —— 见下
///   advRecords: [{len, type, data}],     // 重建一份伪 AD record，方便 Dart UI
///   advFlags,                            // iOS CoreBluetooth 不暴露 → null
///   manufacturerCompanyId, manufacturerData,
///   serviceUuids: [String]
/// }
/// ```
///
/// `rawAdv` 在 iOS 上是 **manufacturer data 完整 hex**（不是整段 scan record）—
/// CoreBluetooth 不暴露原始 scan record 字节。Dart 侧 [JieliAdvParser] 已经按
/// `Platform.isIOS` 给了不同的字节偏移：iOS 从 company-id 开头算起，所以喂
/// manufacturer 完整 hex 即可让绑定解析跑通。
///
/// `address` 在 iOS 上是 `CBPeripheral.identifier.uuidString`（iOS 系统对 BLE
/// MAC 全程匿名）。`ConnectFeature` 那一侧用同样的字符串走
/// `bleMultiple.makeEntity(withUUID:)` 回查。
public final class ScanFeature: NSObject, CBCentralManagerDelegate {

    private weak var server: JieliHomeServer?

    /// 扫描专用 central（与 SDK 内部的 `JL_BLEMultiple` central 解耦）。
    private var centralManager: CBCentralManager?

    public private(set) var isScanning: Bool = false

    private var nameFilter: [String] = []
    private var skipUnnamed: Bool = true

    private var stopTimer: DispatchSourceTimer?

    init(server: JieliHomeServer) {
        self.server = server
        super.init()
        // 立刻起 central —— didUpdateState 会把 adapterStatus 推上去；
        // 同时也让 BLE state 在第一次 startScan 前就 poweredOn。
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    public func startScan(
        timeoutMs: Int,
        nameList: [String],
        uuidList: [String],
        skipUnnamed: Bool
    ) throws {
        guard let central = centralManager else {
            throw NSError(domain: "jieli.scan", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "BLE central unavailable"])
        }
        // 已在扫描：先停旧的（替换扫描参数），对齐 Android `if (scanning) doStop(scanner)`
        if isScanning { doStopScan(silent: true) }

        nameFilter = nameList.filter { !$0.isEmpty }
        self.skipUnnamed = skipUnnamed
        let serviceFilters: [CBUUID] = uuidList.compactMap { Self.parseUuid($0) }

        guard central.state == .poweredOn else {
            throw NSError(domain: "jieli.scan", code: -2,
                          userInfo: [NSLocalizedDescriptionKey:
                            "BLE adapter not powered on (state=\(central.state.rawValue))"])
        }

        // OS 级 UUID 过滤；空 → nil（扫所有广播）。
        let services: [CBUUID]? = serviceFilters.isEmpty ? nil : serviceFilters
        // allowDuplicates=true：每条 ADV 都回调，对应 Android CALLBACK_TYPE_ALL_MATCHES。
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ]
        central.scanForPeripherals(withServices: services, options: options)
        isScanning = true
        NSLog("%@", "[JieliScan] startScan timeoutMs=\(timeoutMs) filters=\(serviceFilters.count) nameList=\(nameFilter)")
        server?.dispatcher.send([
            "type": "scanStatus",
            "ble": true,
            "started": true,
        ])

        stopTimer?.cancel()
        if timeoutMs > 0 {
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + .milliseconds(timeoutMs))
            t.setEventHandler { [weak self] in
                NSLog("%@", "[JieliScan] scan timeout reached, stopping")
                self?.stopScan()
            }
            t.resume()
            stopTimer = t
        }
    }

    public func stopScan() {
        doStopScan(silent: false)
    }

    private func doStopScan(silent: Bool) {
        stopTimer?.cancel()
        stopTimer = nil
        if let central = centralManager, central.state == .poweredOn {
            central.stopScan()
        }
        let wasScanning = isScanning
        isScanning = false
        nameFilter = []
        if wasScanning && !silent {
            server?.dispatcher.send([
                "type": "scanStatus",
                "ble": true,
                "started": false,
            ])
        }
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let on = central.state == .poweredOn
        server?.dispatcher.send([
            "type": "adapterStatus",
            "enabled": on,
            "hasBle": true,
        ])
        if !on && isScanning { doStopScan(silent: false) }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? localName

        // === 软过滤：与 Android handleScanResult 顺序对齐 ===
        // (1) skipUnnamed
        if skipUnnamed && (name?.isEmpty ?? true) { return }
        // (2) name 白名单（忽略大小写）
        if !nameFilter.isEmpty {
            guard let n = name,
                  nameFilter.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame })
            else { return }
        }
        // UUID 过滤在 OS 级已完成，这里不再重复。

        // === 解析广播 ===
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let advServiceUuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []

        // rawAdv：iOS 没有原始 scan record 字节 —— 见类注释。
        let rawAdvHex: String? = manufacturerData?
            .map { String(format: "%02X", $0) }.joined()

        var mfrCompanyId: Int? = nil
        var mfrPayloadHex: String? = nil
        if let m = manufacturerData, m.count >= 2 {
            // companyId 在 ADV 里是小端，对齐 Android `(it[1] shl 8) or it[0]`
            mfrCompanyId = Int(m[0]) | (Int(m[1]) << 8)
            if m.count > 2 {
                mfrPayloadHex = m[2..<m.count].map { String(format: "%02X", $0) }.joined()
            }
        }

        // advRecords —— iOS 拿不到原始 §11 AD 结构，按 Android schema 重建一份
        // 伪 record 列表，仅用于 Flutter "广播详情" 弹窗展示。
        var advRecords: [[String: String]] = []
        if let m = manufacturerData {
            advRecords.append([
                "len": String(format: "%02d", m.count + 1),
                "type": "0xFF",
                "data": "0x" + m.map { String(format: "%02X", $0) }.joined(),
            ])
        }
        if let n = name, !n.isEmpty {
            let bytes = Array(n.utf8)
            advRecords.append([
                "len": String(format: "%02d", bytes.count + 1),
                "type": "0x09",
                "data": "0x" + bytes.map { String(format: "%02X", $0) }.joined(),
            ])
        }

        let serviceUuidsUpper = advServiceUuids.map { $0.uuidString.uppercased() }
        let id = peripheral.identifier.uuidString

        let payload: [String: Any?] = [
            "type": "deviceFound",
            "name": name ?? "",
            "address": id,
            "edrAddr": NSNull(),     // iOS 不暴露 EDR MAC
            "deviceType": NSNull(),  // 留给 Dart 侧 fallback
            "connectWay": NSNull(),
            "rssi": RSSI.intValue,
            "rawAdv": (rawAdvHex as Any?) ?? NSNull(),
            "advRecords": advRecords,
            "advFlags": NSNull(),    // CoreBluetooth 不暴露 AD flags
            "manufacturerCompanyId": (mfrCompanyId as Any?) ?? NSNull(),
            "manufacturerData": (mfrPayloadHex as Any?) ?? NSNull(),
            "serviceUuids": serviceUuidsUpper,
        ]
        server?.dispatcher.send(payload)
    }

    // MARK: - Helpers

    /// 与 Android `parseUuid` 对齐：4-char(16-bit) / 8-char(32-bit) / 32/36-char(128-bit)。
    /// `CBUUID(string:)` 在底层对这些写法都接受。
    private static func parseUuid(_ raw: String) -> CBUUID? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        let len = s.count
        // 显式校验长度，避免 `CBUUID(string:)` 对非法输入抛 Obj-C 异常。
        guard len == 4 || len == 8 || len == 32 || len == 36 else {
            NSLog("%@", "[JieliScan] invalid UUID format: \(raw)")
            return nil
        }
        return CBUUID(string: s)
    }
}
