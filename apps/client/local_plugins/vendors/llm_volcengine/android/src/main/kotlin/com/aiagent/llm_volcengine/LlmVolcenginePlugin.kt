package com.aiagent.llm_volcengine

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * LlmVolcenginePlugin — 火山引擎 Ark LLM Flutter 插件
 *
 * 注册 vendor="volcengine"（兼容旧数据 "doubao"），走 ark OpenAI 兼容接口
 * (POST /api/v3/chat/completions + Bearer ApiKey)。
 */
class LlmVolcenginePlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        listOf("volcengine", "doubao").forEach { vendor ->
            NativeServiceRegistry.registerLlm(vendor) { LlmVolcengineService() }
        }
        Log.d("LlmVolcenginePlugin", "Registered NativeLlmService for vendors: volcengine, doubao")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // no-op
    }
}
