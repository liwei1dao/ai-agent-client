import Flutter
import ai_plugin_interface
import os.log

/// PolyChat STS Flutter plugin entry.
///
/// Mirrors the Android `StsPolychatPlugin`: registers vendor "polychat"
/// against `StsPolychatService` and pre-warms the shared WebRTC factory so
/// the first connection doesn't pay the init latency.
public class StsPolychatPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.sts_polychat", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeServiceRegistry.shared.registerSts("polychat") { StsPolychatService() }
        VoitransWebRtcSession.warmup()
        os_log("Registered NativeStsService for vendor: polychat",
               log: log, type: .debug)
    }
}
