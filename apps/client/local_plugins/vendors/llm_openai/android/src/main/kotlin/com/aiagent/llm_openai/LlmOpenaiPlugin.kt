package com.aiagent.llm_openai

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * LlmOpenaiPlugin — OpenAI-compatible LLM Flutter 插件
 *
 * 主要角色：在 onAttachedToEngine 时注册 NativeLlmService 到 NativeServiceRegistry，
 * 供 Agent 类型插件（agent_chat 等）在原生层直接调用。
 *
 * Dart 侧的纯 HTTP 实现 (llm_openai_plugin.dart) 保留向后兼容。
 */
class LlmOpenaiPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // 注册 OpenAI 兼容的 LLM 厂商（共用一套 HTTP SSE 协议）。
        // 火山引擎（volcengine）已拆到 llm_volcengine 插件独立实现，不在此列表。
        val vendors = listOf("openai", "deepseek", "moonshot", "zhipu", "qwen", "minimax", "baichuan")
        for (vendor in vendors) {
            NativeServiceRegistry.registerLlm(vendor) { LlmOpenaiService() }
        }
        Log.d("LlmOpenaiPlugin", "Registered NativeLlmService for vendors: $vendors")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // no-op
    }
}
