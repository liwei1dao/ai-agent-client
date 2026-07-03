import Flutter

/// iOS stub for the Android-side `DeviceManagerPlugin`.
///
/// Mirrors the four channels the Dart client expects:
///   - `device_manager/method`   — command facade
///   - `device_manager/events`   — DeviceManagerEvent stream
///   - `device_manager/triggers` — DeviceAgentTrigger stream
///   - `device_manager/ota`      — OTA progress stream
///
/// All four are wired so the Dart side never throws `MissingPluginException`.
/// No vendor SDK is registered yet on iOS — the stub answers query methods
/// with empty results and rejects write methods with a `device.not_supported`
/// PlatformException so the Dart `MethodChannelDeviceManager` can surface a
/// clean `DeviceException` instead of a cast failure on `null`.
///
/// 27ca7e0 误把本文件改成 16 行 noop（注释声称 "device_jieli SPM 会注册
/// device_manager/* 通道"），但 device_jieli SPM 实际只注册 device_jieli/*，
/// 导致 Dart 调 device_manager/method 的 useVendor 报 MissingPluginException。
/// 已恢复为 9ae1853 的完整 stub。后续 iOS 真要支持多 vendor 时，把 useVendor /
/// startScan / connect 等路由到对应 jieli iOS server。
public class DeviceManagerPlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var triggerChannel: FlutterEventChannel?
    private var otaChannel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = DeviceManagerPlugin()
        let messenger = registrar.messenger()

        instance.methodChannel = FlutterMethodChannel(
            name: "device_manager/method",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "device_manager/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(SilentStreamHandler())

        instance.triggerChannel = FlutterEventChannel(
            name: "device_manager/triggers",
            binaryMessenger: messenger
        )
        instance.triggerChannel?.setStreamHandler(SilentStreamHandler())

        instance.otaChannel = FlutterEventChannel(
            name: "device_manager/ota",
            binaryMessenger: messenger
        )
        instance.otaChannel?.setStreamHandler(SilentStreamHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        // ── Query methods: return inert defaults the Dart side already
        // treats as "no active device / no vendors yet". ─────────────────
        case "listVendors":
            result([Any]())
        case "isBluetoothEnabled":
            result(false)
        case "bondedDevices":
            result([Any]())
        case "activeVendor":
            result(nil)
        case "activeCapabilities":
            result([String]())
        case "activeSession":
            result(nil)
        case "readRssi", "readBattery":
            result(nil)
        case "refreshInfo", "invokeFeature":
            result([String: Any?]())
        case "otaIsRunning", "otaSupported":
            result(false)

        // ── Lifecycle / no-op writes: silently succeed. ──────────────────
        case "useVendor",
             "clearVendor",
             "startScan",
             "stopScan",
             "disconnect",
             "syncActive",
             "otaCancel":
            result(nil)

        // ── Operations that need a real native session: refuse cleanly. ──
        case "connect",
             "otaStart":
            result(FlutterError(
                code: "device.not_supported",
                message: "Device runtime is not yet implemented on iOS.",
                details: nil
            ))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private final class SilentStreamHandler: NSObject, FlutterStreamHandler {
    // Hold the sink open but never emit. Dart subscribers keep listening,
    // matching the "no devices ever appear" semantics of the stub.
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}
