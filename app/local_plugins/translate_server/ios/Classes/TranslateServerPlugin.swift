import Flutter

/// iOS stub for the Android-side `TranslateServerPlugin`.
///
/// The composite call/face-to-face/audio translation pipeline is driven by
/// the native side on Android (it wires device RCSP audio frames into the
/// agent runner). iOS has no equivalent yet — any `startXxx` call is
/// rejected with `translate.not_implemented` so the Dart facade surfaces a
/// `TranslateException` instead of a cast on `null`.
public class TranslateServerPlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TranslateServerPlugin()
        let messenger = registrar.messenger()

        instance.methodChannel = FlutterMethodChannel(
            name: "translate_server/method",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "translate_server/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(SilentStreamHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "stopActiveSession":
            // Best-effort no-op on the Dart side. Don't propagate an error.
            result(nil)
        case "startCallTranslation",
             "startFaceToFaceTranslation",
             "startAudioTranslation":
            result(FlutterError(
                code: "translate.not_implemented",
                message: "Translate server is not yet implemented on iOS.",
                details: nil
            ))
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private final class SilentStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? { nil }
}
