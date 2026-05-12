import Foundation

/// Agent bootstrap config delivered over the Flutter MethodChannel.
public struct NativeAgentConfig {
    public let agentId: String
    /// "text" | "short_voice" | "call"
    public let inputMode: String

    public let sttVendor: String?
    public let ttsVendor: String?
    public let llmVendor: String?
    public let stsVendor: String?
    public let astVendor: String?
    public let translationVendor: String?

    public let sttConfigJson: String?
    public let ttsConfigJson: String?
    public let llmConfigJson: String?
    public let stsConfigJson: String?
    public let astConfigJson: String?
    public let translationConfigJson: String?

    /// MCP server list as a JSON array string (each entry = McpServerConfig.toJson).
    public let mcpServersJson: String?

    /// Free-form key/value extras (e.g. `srcLang`, `dstLang`).
    public let extraParams: [String: String]

    public init(
        agentId: String,
        inputMode: String = "text",
        sttVendor: String? = nil,
        ttsVendor: String? = nil,
        llmVendor: String? = nil,
        stsVendor: String? = nil,
        astVendor: String? = nil,
        translationVendor: String? = nil,
        sttConfigJson: String? = nil,
        ttsConfigJson: String? = nil,
        llmConfigJson: String? = nil,
        stsConfigJson: String? = nil,
        astConfigJson: String? = nil,
        translationConfigJson: String? = nil,
        mcpServersJson: String? = nil,
        extraParams: [String: String] = [:]
    ) {
        self.agentId = agentId
        self.inputMode = inputMode
        self.sttVendor = sttVendor
        self.ttsVendor = ttsVendor
        self.llmVendor = llmVendor
        self.stsVendor = stsVendor
        self.astVendor = astVendor
        self.translationVendor = translationVendor
        self.sttConfigJson = sttConfigJson
        self.ttsConfigJson = ttsConfigJson
        self.llmConfigJson = llmConfigJson
        self.stsConfigJson = stsConfigJson
        self.astConfigJson = astConfigJson
        self.translationConfigJson = translationConfigJson
        self.mcpServersJson = mcpServersJson
        self.extraParams = extraParams
    }

    /// Parse a MethodChannel argument dictionary into a config struct.
    /// `agentId` is required; missing/empty values fall through to `nil`.
    public static func fromMap(_ map: [String: Any?]) -> NativeAgentConfig {
        // Force-unwrap mirrors the Kotlin `as String` cast — the Dart side
        // guarantees agentId is set when invoking createAgent.
        let agentId = (map["agentId"] as? String) ?? ""
        let extras: [String: String]
        if let raw = map["extraParams"] as? [String: Any?] {
            extras = raw.reduce(into: [String: String]()) { acc, kv in
                if let value = kv.value {
                    acc[kv.key] = String(describing: value)
                }
            }
        } else {
            extras = [:]
        }
        return NativeAgentConfig(
            agentId: agentId,
            inputMode: (map["inputMode"] as? String) ?? "text",
            sttVendor: map["sttVendor"] as? String,
            ttsVendor: map["ttsVendor"] as? String,
            llmVendor: map["llmVendor"] as? String,
            stsVendor: map["stsVendor"] as? String,
            astVendor: map["astVendor"] as? String,
            translationVendor: map["translationVendor"] as? String,
            sttConfigJson: map["sttConfigJson"] as? String,
            ttsConfigJson: map["ttsConfigJson"] as? String,
            llmConfigJson: map["llmConfigJson"] as? String,
            stsConfigJson: map["stsConfigJson"] as? String,
            astConfigJson: map["astConfigJson"] as? String,
            translationConfigJson: map["translationConfigJson"] as? String,
            mcpServersJson: map["mcpServersJson"] as? String,
            extraParams: extras
        )
    }
}
