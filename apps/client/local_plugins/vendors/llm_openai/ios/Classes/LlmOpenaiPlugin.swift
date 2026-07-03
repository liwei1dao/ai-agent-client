import Flutter
import ai_plugin_interface
import os.log

/// OpenAI-compatible LLM Flutter plugin entry.
///
/// At registration time we register `LlmOpenaiService` against every vendor
/// id that speaks the OpenAI chat-completions SSE protocol. The volcengine
/// Ark API is split out into its own plugin (`llm_volcengine`).
public class LlmOpenaiPlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.llm_openai", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let vendors = ["openai", "deepseek", "moonshot", "zhipu", "qwen", "minimax", "baichuan"]
        for vendor in vendors {
            NativeServiceRegistry.shared.registerLlm(vendor) { LlmOpenaiService() }
        }
        os_log("Registered NativeLlmService for vendors: %{public}@",
               log: log, type: .debug, vendors.description)
    }
}
