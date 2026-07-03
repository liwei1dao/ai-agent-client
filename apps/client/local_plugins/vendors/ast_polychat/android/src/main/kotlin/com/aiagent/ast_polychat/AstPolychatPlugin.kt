package com.aiagent.ast_polychat

import io.flutter.embedding.engine.plugins.FlutterPlugin
import com.aiagent.plugin_interface.NativeServiceRegistry

/**
 * Flutter 插件入口：注册 vendor "polychat" 到 NativeServiceRegistry (AST)
 */
class AstPolychatPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        NativeServiceRegistry.registerAst("polychat") { AstPolychatService(context) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
