import Flutter

/// iOS stub for the Android-side `AssistantServerPlugin`.
///
/// The Android implementation glues a chat agent to the headset RCSP audio
/// loop. iOS lacks the underlying RCSP integration today, so any
/// `startAssistant` call returns `assistant.not_implemented`; the Dart
/// facade wraps that into an `AssistantException`.
public class AssistantServerPlugin: NSObject, FlutterPlugin {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AssistantServerPlugin()
        let messenger = registrar.messenger()

        instance.methodChannel = FlutterMethodChannel(
            name: "assistant_server/method",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "assistant_server/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(SilentStreamHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "stopActiveSession":
            result(nil)
        case "startAssistant":
            result(FlutterError(
                code: "assistant.not_implemented",
                message: "Assistant server is not yet implemented on iOS.",
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
