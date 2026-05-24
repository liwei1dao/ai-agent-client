import Flutter
import ai_plugin_interface
import os.log

/// STS chat agent Flutter plugin entry.
///
/// Registers a factory for the `"sts-chat"` agent type with the global
/// `NativeAgentRegistry`. `agents_server` instantiates a session via
/// `NativeAgentRegistry.shared.create("sts-chat")` when the Dart side calls
/// `createAgent(agentType:"sts-chat", …)`.
public class StsChatAgentFlutterPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.agent_sts_chat", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeAgentRegistry.shared.register("sts-chat") { StsChatAgentSession() }
        os_log("Registered NativeAgent type=sts-chat", log: log, type: .debug)
    }
}
