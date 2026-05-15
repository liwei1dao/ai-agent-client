import Foundation
import JL_BLEKit

/// 监听设备主动推送的 Custom Cmd / Custom Response。
///
/// 设备 → APP 自定义命令在 iOS SDK 里通过 NSNotification 形式抛出（key
/// `kJL_MANAGER_CUSTOM_DATA` / `kJL_MANAGER_CUSTOM_DATA_RSP`），具体 payload
/// 走 `JL_CustomManager` 的 delegate；这里仅把"设备主动请求"广播事件转发到 Dart 端，
/// payload 用 base64 encode 兼容 Android 端 `ExpandFunctionEvent` 形态。
public final class CustomEventForwarder: NSObject {

    private weak var server: JieliHomeServer?

    public init(server: JieliHomeServer) {
        self.server = server
    }

    public func attach() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onCustomData(_:)),
            name: NSNotification.Name(kJL_MANAGER_CUSTOM_DATA),
            object: nil
        )
    }

    public func detach() {
        NotificationCenter.default.removeObserver(self)
    }

    deinit { detach() }

    @objc private func onCustomData(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let uuid = info[kJL_MANAGER_KEY_UUID] as? String
        var opCode: Int = 0
        var base64: String? = nil

        // iOS SDK 把 payload 放在 kJL_MANAGER_KEY_OBJECT 里——历史上有时是 NSData，
        // 有时是字典含 opCode + data；两边都兜底处理。
        if let dict = info[kJL_MANAGER_KEY_OBJECT] as? [String: Any] {
            if let code = (dict["opCode"] as? NSNumber)?.intValue { opCode = code }
            if let data = dict["data"] as? Data { base64 = data.base64EncodedString() }
        } else if let data = info[kJL_MANAGER_KEY_OBJECT] as? Data {
            base64 = data.base64EncodedString()
        }

        server?.dispatcher.send([
            "type": "expandFunction",
            "address": uuid as Any,
            "opCode": opCode,
            "payloadBase64": base64 as Any,
        ])
    }
}
