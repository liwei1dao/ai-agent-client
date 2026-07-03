import Flutter
import ai_plugin_interface
import os.log

/// Chat agent Flutter plugin entry.
///
/// Registers a factory for the `"chat"` agent type with the global
/// `NativeAgentRegistry`. `agents_server` instantiates an agent via
/// `NativeAgentRegistry.shared.create("chat")` when the Dart side calls
/// `createAgent(agentType:"chat", …)`.
public class ChatAgentFlutterPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.agent_chat", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeAgentRegistry.shared.register("chat") { ChatAgentSession() }
        os_log("Registered NativeAgent type=chat", log: log, type: .debug)
    }
}
