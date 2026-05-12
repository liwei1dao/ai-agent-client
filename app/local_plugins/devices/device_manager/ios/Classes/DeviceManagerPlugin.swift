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
