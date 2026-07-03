import Foundation
import JL_BLEKit
import JL_OTALib

/// OTA 升级（iOS）—— 与 iOS demo `OTAViewController` 对齐。
///
/// 走 per-device 的 `JL_OTAManager.cmdUpgrade(_:option:result:)`：
///   - `mOTAManager` 挂在 `JL_ManagerM` 上，由 SDK 在连接成功后自动初始化
///   - 我们直接读取固件文件字节，调 `cmdUpgrade(data, option: nil, result: ...)`
///   - 取消用 `cmdOTACancelResult()`（无参，demo 形态）
public final class OtaFeature {

    private weak var server: JieliHomeServer?
    public private(set) var isRunning: Bool = false

    private var currentFileSize: Int64 = 0
    private var currentAddress: String?
    private weak var currentOtaManager: JL_OTAManager?

    init(server: JieliHomeServer) { self.server = server }

    public func start(
        address: String?,
        firmwareFilePath: String,
        blockSize: Int,
        fileFlagBytes: Data
    ) {
        guard let server = server else {
            emitError(-1, "server uninitialized"); return
        }
        guard !isRunning else { emitError(-2, "ota already running"); return }

        let entity: JL_EntityM? = {
            if let addr = address { return server.connectedEntity(forUuid: addr) }
            return server.currentConnectedEntity()
        }()
        guard let target = entity else {
            emitError(-3, "no connected device"); return
        }
        let otaManager = target.mCmdManager.mOTAManager
        guard let firmwareData = try? Data(contentsOf: URL(fileURLWithPath: firmwareFilePath)) else {
            emitError(-4, "firmware file invalid: \(firmwareFilePath)"); return
        }
        if firmwareData.isEmpty { emitError(-5, "firmware file is empty"); return }
        currentFileSize = Int64(firmwareData.count)

        currentAddress = target.mUUID
        currentOtaManager = otaManager
        isRunning = true
        emitState("INQUIRING", sent: 0, total: currentFileSize)

        otaManager.cmdUpgrade(firmwareData, option: nil) { [weak self] result, progress in
            self?.dispatchOtaCallback(result: result, progress: progress)
        }
    }

    public func cancel() {
        guard isRunning else { return }
        // demo 形态：无参取消
        currentOtaManager?.cmdOTACancelResult()
        isRunning = false
        emitState("CANCELLED", sent: -1, total: currentFileSize)
    }

    // MARK: - SDK callback dispatch

    private func dispatchOtaCallback(result: JL_OTAResult, progress: Float) {
        let total = currentFileSize
        let sent = Int64((Float(total) * max(0, min(1.0, progress))).rounded())

        switch result {
        case .success:
            isRunning = false
            emitState("DONE", sent: total, total: total)
        case .fail, .commandFail, .seekFail, .infoFail, .lowPower, .enterFail,
             .failVerification, .failCompletely, .failKey, .failErrorFile, .failUboot,
             .failLenght, .failFlash, .failCmdTimeout, .failSameVersion,
             .failTWSDisconnect, .failNotInBin, .disconnect, .failSameSN, .unknown:
            isRunning = false
            emitError(Int(result.rawValue), "ota failed result=\(result.rawValue)")
            emitState("FAILED", sent: -1, total: total)
        case .upgrading, .preparing, .prepared:
            emitState("TRANSFERRING", sent: sent, total: total)
        case .reconnect, .reconnectWithMacAddr, .reconnectUpdateSource:
            emitState("ENTERING", sent: sent, total: total)
        case .reboot:
            emitState("REBOOTING", sent: total, total: total)
        case .cancel:
            isRunning = false
            emitState("CANCELLED", sent: -1, total: total)
        case .statusIsUpdating, .failedConnectMore, .dataIsNull:
            isRunning = false
            emitError(Int(result.rawValue), "ota cannot start: \(result.rawValue)")
            emitState("FAILED", sent: -1, total: total)
        @unknown default:
            // 默认作进度
            emitState("TRANSFERRING", sent: sent, total: total)
        }
    }

    // MARK: - Event emission

    private func emitState(_ state: String, sent: Int64, total: Int64) {
        let percent: Int = {
            if total > 0 && sent >= 0 && sent <= total {
                return Int((Double(sent) * 100.0 / Double(total)).rounded())
            }
            return -1
        }()
        server?.dispatcher.send([
            "type": "otaState",
            "state": state,
            "sent": NSNumber(value: sent),
            "total": NSNumber(value: total),
            "percent": percent,
            "tsMs": NSNumber(value: Int64(Date().timeIntervalSince1970 * 1000)),
        ])
    }

    private func emitError(_ code: Int, _ msg: String?) {
        server?.dispatcher.send([
            "type": "otaError",
            "code": code,
            "message": msg as Any,
        ])
    }
}
