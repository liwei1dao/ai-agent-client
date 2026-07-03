import Flutter
import ai_plugin_interface
import os.log

/// Translate agent Flutter plugin entry.
///
/// Registers a factory for the `"translate"` agent type with the global
/// `NativeAgentRegistry`. `agents_server` instantiates a session via
/// `NativeAgentRegistry.shared.create("translate")` when the Dart side calls
/// `createAgent(agentType:"translate", …)`.
public class TranslateAgentFlutterPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.agent_translate", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeAgentRegistry.shared.register("translate") { TranslateAgentSession() }
        os_log("Registered NativeAgent type=translate", log: log, type: .debug)
    }
}
