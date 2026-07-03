import Flutter
import ai_plugin_interface
import os.log

/// Volcengine Ark LLM Flutter plugin entry.
///
/// Mirrors the Android `LlmVolcenginePlugin`: registers vendors
/// "volcengine" and "doubao" against `LlmVolcengineService`. The service
/// talks to Ark's OpenAI-compatible `chat/completions` endpoint
/// (https://ark.cn-beijing.volces.com/api/v3 by default).
public class LlmVolcenginePlugin: NSObject, FlutterPlugin {
    private static let log = OSLog(subsystem: "com.aiagent.llm_volcengine", category: "Plugin")

    public static func register(with registrar: FlutterPluginRegistrar) {
        let vendors = ["volcengine", "doubao"]
        for vendor in vendors {
            NativeServiceRegistry.shared.registerLlm(vendor) { LlmVolcengineService() }
        }
        os_log("Registered NativeLlmService for vendors: %{public}@",
               log: log, type: .debug, vendors.description)
    }
}
