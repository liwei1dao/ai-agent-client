import Flutter

/// iOS 端 device_manager Pod 占位插件 —— 实际通道由 `device_jieli` SPM
/// 注册（`device_manager/method`, `device_manager/events`, `device_manager/triggers`,
/// `device_manager/ota` 都在 `JielihomePlugin.register(with:)` 里挂上去）。
///
/// 这里只是空 plugin，确保 Pod 模块能正常加载，不抢通道控制权。当后续 iOS 引入
/// 多 vendor（恒玄 / 高通 / 蓝讯）时再把通道路由提到这里做 vendor-agnostic 分发。
public class DeviceManagerPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        // 故意不注册任何 channel：device_jieli SPM 已声明所有 device_manager
        // 通道，由它直接服务 Dart facade。
        _ = DeviceManagerPlugin()
    }
}
