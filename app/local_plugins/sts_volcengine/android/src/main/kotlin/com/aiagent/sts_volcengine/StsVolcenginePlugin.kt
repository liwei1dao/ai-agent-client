package com.aiagent.sts_volcengine

import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

class StsVolcenginePlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        // 火山引擎 STS 服务，注册多个 vendor 名
        val vendors = listOf("doubao", "volcengine", "bytedance")
        for (vendor in vendors) {
            NativeServiceRegistry.registerSts(vendor) { StsVolcengineService(context) }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
