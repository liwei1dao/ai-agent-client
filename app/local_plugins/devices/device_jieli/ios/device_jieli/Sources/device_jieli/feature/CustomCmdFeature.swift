import Foundation
import JL_BLEKit

/// 厂商扩展指令通道（与 Android `CustomCmdFeature` 对齐）。
///
/// iOS SDK 通过每个设备 `JL_ManagerM` 上的 `mCustomManager` 暴露 `cmdCustomData:`。
/// 设备主动推的数据由 [CustomEventForwarder] 监听通知转发。
public final class CustomCmdFeature {

    private weak var server: JieliHomeServer?
    init(server: JieliHomeServer) { self.server = server }

    public func send(
        address: String,
        opCode: Int,
        payload: Data,
        completion: @escaping (_ ok: Bool, _ response: Data?, _ errCode: Int?, _ errMsg: String?) -> Void
    ) {
        guard let entity = server?.connectedEntity(forUuid: address) else {
            completion(false, nil, -1, "remote device not found"); return
        }
        let custom = entity.mCmdManager.mCustomManager

        // iOS SDK 没有原生 opCode 字段——厂商扩展指令 0xF0 的 sub-op 习惯放在 payload 第一字节，
        // 这里把 Dart 端传入的 opCode 拼到 payload 头部，保持与 Android 端 SDK 的等价语义。
        var bytes = [UInt8]()
        bytes.append(UInt8(truncatingIfNeeded: opCode))
        bytes.append(contentsOf: [UInt8](payload))
        let outData = Data(bytes)

        custom.cmdCustomData(outData, isNeedResponse: true) { status, _, replyData in
            if status == .success {
                completion(true, replyData, nil, nil)
            } else {
                completion(false, nil, Int(status.rawValue), "cmd status=\(status.rawValue)")
            }
        }
    }
}
