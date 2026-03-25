package com.aiagent.plugin_interface

/**
 * Agent 初始化配置（从 Flutter MethodChannel 传入）
 */
data class NativeAgentConfig(
    val agentId: String,
    val inputMode: String,              // "text" | "short_voice" | "call"
    val sttVendor: String?,             // "azure"
    val ttsVendor: String?,             // "azure"
    val llmVendor: String?,             // "openai"
    val stsVendor: String?,             // "doubao"
    val astVendor: String?,             // "volcengine"
    val translationVendor: String?,     // "deepl" | "aliyun"
    val sttConfigJson: String?,
    val ttsConfigJson: String?,
    val llmConfigJson: String?,
    val stsConfigJson: String?,
    val astConfigJson: String?,
    val translationConfigJson: String?,
    val extraParams: Map<String, String> = emptyMap(),  // srcLang, dstLang etc.
) {
    companion object {
        /**
         * 从 Flutter MethodChannel 的 Map 构建
         */
        fun fromMap(map: Map<*, *>) = NativeAgentConfig(
            agentId = map["agentId"] as String,
            inputMode = map["inputMode"] as? String ?: "text",
            sttVendor = map["sttVendor"] as? String,
            ttsVendor = map["ttsVendor"] as? String,
            llmVendor = map["llmVendor"] as? String,
            stsVendor = map["stsVendor"] as? String,
            astVendor = map["astVendor"] as? String,
            translationVendor = map["translationVendor"] as? String,
            sttConfigJson = map["sttConfigJson"] as? String,
            ttsConfigJson = map["ttsConfigJson"] as? String,
            llmConfigJson = map["llmConfigJson"] as? String,
            stsConfigJson = map["stsConfigJson"] as? String,
            astConfigJson = map["astConfigJson"] as? String,
            translationConfigJson = map["translationConfigJson"] as? String,
            extraParams = (map["extraParams"] as? Map<*, *>)
                ?.map { (k, v) -> k.toString() to v.toString() }
                ?.toMap() ?: emptyMap(),
        )
    }
}
