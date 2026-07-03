import Flutter
import ai_plugin_interface
import os.log

/// PolyChat AST Flutter plugin entry.
///
/// Mirrors the Android `AstPolychatPlugin`: registers vendor "polychat"
/// against `AstPolychatService`.
public class AstPolychatPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.ast_polychat", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeServiceRegistry.shared.registerAst("polychat") { AstPolychatService() }
        os_log("Registered NativeAstService for vendor: polychat",
               log: log, type: .debug)
    }
}
