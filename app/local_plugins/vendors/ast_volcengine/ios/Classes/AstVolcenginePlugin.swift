import Flutter
import ai_plugin_interface
import os.log

/// Volcengine speech translation (AST) Flutter plugin entry.
///
/// Mirrors the Android `AstVolcenginePlugin`: registers vendors "volcengine",
/// "doubao" and "bytedance" against `AstVolcengineService`.
public class AstVolcenginePlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.ast_volcengine", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let vendors = ["volcengine", "doubao", "bytedance"]
        for vendor in vendors {
            NativeServiceRegistry.shared.registerAst(vendor) { AstVolcengineService() }
        }
        os_log("Registered NativeAstService for vendors: %{public}@",
               log: log, type: .debug, vendors.description)
    }
}
