import CoreBluetooth
import Foundation
import JL_BLEKit
import JL_OTALib
import JLLogHelper

/// 全局单例。与 Android `JieliHomeServer` 对应：
///   - 持有 `JL_BLEMultiple`（搜索 + 连接 + 已连 entity 列表）
///   - 持有 `JL_OTAManager` 引用（OTA 由 SDK 暴露的单例）
///   - 持有 per-device [TranslationSession]，**全平台单一翻译入口**
///   - 各 feature 模块通过 [translationSession(for:)] 拿当前会话，
///     与 Android 通过 `JL_BluetoothManager.connectedDevice + TranslationImpl` 等价。
public final class JieliHomeServer: NSObject {

    public static let shared = JieliHomeServer()

    public let dispatcher = EventDispatcher()

    public private(set) var initialized: Bool = false

    public let bleMultiple: JL_BLEMultiple = JL_BLEMultiple()
    public var otaManager: JL_OTAManager { JL_OTAManager.getOTAManager() }

    // MARK: - Per-device translation sessions

    private var sessions: [String: TranslationSession] = [:]
    private let sessionsLock = NSLock()

    /// 取或新建给定设备的翻译会话。会话生命周期与连接绑定（断开时 [removeTranslationSession]）。
    public func translationSession(for uuid: String) -> TranslationSession? {
        guard let entity = connectedEntity(forUuid: uuid) else { return nil }
        let mgr = entity.mCmdManager
        sessionsLock.lock(); defer { sessionsLock.unlock() }
        if let exist = sessions[uuid] { return exist }
        let s = TranslationSession(uuid: uuid, manager: mgr)
        sessions[uuid] = s
        return s
    }

    public func currentTranslationSession() -> TranslationSession? {
        guard let entity = currentConnectedEntity() else { return nil }
        return translationSession(for: entity.mUUID ?? "")
    }

    public func removeTranslationSession(uuid: String) {
        sessionsLock.lock(); defer { sessionsLock.unlock() }
        sessions.removeValue(forKey: uuid)
    }

    // MARK: - Feature modules

    public private(set) lazy var scanFeature: ScanFeature = ScanFeature(server: self)
    public private(set) lazy var connectFeature: ConnectFeature = ConnectFeature(server: self)
    public private(set) lazy var deviceInfoFeature: DeviceInfoFeature = DeviceInfoFeature(server: self)
    public private(set) lazy var customCmdFeature: CustomCmdFeature = CustomCmdFeature(server: self)
    public private(set) lazy var translationFeature: TranslationFeature = TranslationFeature(server: self)
    public private(set) lazy var speechFeature: SpeechFeature = SpeechFeature(server: self)
    public private(set) lazy var assistantBridge: AssistantBridge = AssistantBridge(server: self)
    public private(set) lazy var deviceRecordFeature: DeviceRecordFeature = DeviceRecordFeature(server: self)
    public private(set) lazy var otaFeature: OtaFeature = OtaFeature(server: self)

    // MARK: - Event forwarder

    private var bluetoothForwarder: BluetoothEventForwarder?
    private var customForwarder: CustomEventForwarder?
    private var deviceInfoForwarder: DeviceInfoEventForwarder?

    private override init() { super.init() }

    public func initialize(multiDevice: Bool, skipNoNameDev: Bool, enableLog: Bool, useDeviceAuth: Bool = true) {
        if initialized { return }

        JLLogManager.clearLog()
        JLLogManager.setLog(enableLog, isMore: false, level: .DEBUG)
        JLLogManager.log(withTimestamp: true)
        JLLogManager.saveLog(asFile: enableLog)

        bleMultiple.ble_FILTER_ENABLE = false
        bleMultiple.ble_TIMEOUT = 10
        // RCSP 设备认证：见 Android JieliHomeServer.initialize 注释。默认开启，
        // 调试无签名设备时可关闭。
        bleMultiple.authEnable = useDeviceAuth

        let btFwd = BluetoothEventForwarder(server: self)
        btFwd.attach()
        bluetoothForwarder = btFwd

        let customFwd = CustomEventForwarder(server: self)
        customFwd.attach()
        customForwarder = customFwd

        let infoFwd = DeviceInfoEventForwarder(server: self)
        infoFwd.attach()
        deviceInfoForwarder = infoFwd

        // 提前实例化 ScanFeature，让它的 CBCentralManager 趁早创建，
        // 等用户第一次 startScan 时 state 已经 poweredOn。
        _ = scanFeature

        initialized = true
    }

    // MARK: - Helpers

    /// 通过 BLE UUID 找到已搜索 / 已连接到的 entity
    public func entity(forUuid uuid: String) -> JL_EntityM? {
        let pool: [JL_EntityM] = (bleMultiple.bleConnectedArr as? [JL_EntityM] ?? []) +
                                 (bleMultiple.blePeripheralArr as? [JL_EntityM] ?? [])
        return pool.first { $0.mUUID == uuid }
    }

    public func connectedEntity(forUuid uuid: String) -> JL_EntityM? {
        let pool = bleMultiple.bleConnectedArr as? [JL_EntityM] ?? []
        return pool.first { $0.mUUID == uuid }
    }

    public func currentConnectedEntity() -> JL_EntityM? {
        let pool = bleMultiple.bleConnectedArr as? [JL_EntityM] ?? []
        return pool.first
    }
}
