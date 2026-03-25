package com.aiagent.agent_ast_translate

import android.util.Log
import com.aiagent.plugin_interface.NativeAgentRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * AstTranslateAgentFlutterPlugin — AST Translate Agent Flutter 插件入口
 *
 * 在 onAttachedToEngine 时注册 "ast" Agent 类型到 NativeAgentRegistry。
 * agents_server 通过 NativeAgentRegistry.create("ast") 创建 AstTranslateAgentSession 实例。
 */
class AstTranslateAgentFlutterPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeAgentRegistry.register("ast") { AstTranslateAgentSession() }
        Log.d("AstTranslateAgentPlugin", "Registered NativeAgent type=ast")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
