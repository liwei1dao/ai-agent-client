package com.aiagent.agent_translate

import android.util.Log
import com.aiagent.plugin_interface.NativeAgentRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * TranslateAgentFlutterPlugin — Translate Agent Flutter 插件入口
 *
 * 在 onAttachedToEngine 时注册 "translate" Agent 类型到 NativeAgentRegistry。
 * agents_server 通过 NativeAgentRegistry.create("translate") 创建 TranslateAgentSession 实例。
 */
class TranslateAgentFlutterPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeAgentRegistry.register("translate") { TranslateAgentSession() }
        Log.d("TranslateAgentPlugin", "Registered NativeAgent type=translate")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
