package com.aiagent.ast_volcengine

import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

class AstVolcenginePlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        // 火山引擎 AST 服务，注册多个 vendor 名（用户配置可能使用不同名称）
        val vendors = listOf("volcengine", "doubao", "bytedance")
        for (vendor in vendors) {
            NativeServiceRegistry.registerAst(vendor) { AstVolcengineService(context) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
