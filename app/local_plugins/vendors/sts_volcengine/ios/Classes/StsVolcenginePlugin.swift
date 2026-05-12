import Flutter
import ai_plugin_interface
import os.log

/// Volcengine realtime speech-to-speech Flutter plugin entry.
///
/// Mirrors the Android `StsVolcenginePlugin`: registers vendors "doubao",
/// "volcengine" and "bytedance" against `StsVolcengineService`. The service
/// drives the binary dialogue protocol on
/// `wss://openspeech.bytedance.com/api/v3/realtime/dialogue`.
public class StsVolcenginePlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.sts_volcengine", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let vendors = ["doubao", "volcengine", "bytedance"]
        for vendor in vendors {
            NativeServiceRegistry.shared.registerSts(vendor) { StsVolcengineService() }
        }
        os_log("Registered NativeStsService for vendors: %{public}@",
               log: log, type: .debug, vendors.description)
    }
}
