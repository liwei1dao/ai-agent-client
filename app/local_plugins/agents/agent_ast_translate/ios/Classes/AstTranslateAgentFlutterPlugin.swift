import Flutter
import ai_plugin_interface
import os.log

/// AST translate agent Flutter plugin entry.
///
/// Registers a factory for the `"ast-translate"` agent type with the global
/// `NativeAgentRegistry`. `agents_server` instantiates a session via
/// `NativeAgentRegistry.shared.create("ast-translate")` when the Dart side
/// calls `createAgent(agentType:"ast-translate", …)`.
public class AstTranslateAgentFlutterPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.agent_ast_translate", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeAgentRegistry.shared.register("ast-translate") { AstTranslateAgentSession() }
        os_log("Registered NativeAgent type=ast-translate", log: log, type: .debug)
    }
}
