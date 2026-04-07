package com.aiagent.ast_voitrans

import io.flutter.embedding.engine.plugins.FlutterPlugin
import com.aiagent.plugin_interface.NativeServiceRegistry

/**
 * Flutter 插件入口：注册 vendor "voitrans" 到 NativeServiceRegistry (AST)
 */
class AstVoitransPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        NativeServiceRegistry.registerAst("voitrans") { AstVoitransService(context) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
