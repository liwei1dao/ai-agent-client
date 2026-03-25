package com.aiagent.agent_sts_chat

import android.util.Log
import com.aiagent.plugin_interface.NativeAgentRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * StsChatAgentFlutterPlugin — STS Chat Agent Flutter 插件入口
 *
 * 在 onAttachedToEngine 时注册 "sts" Agent 类型到 NativeAgentRegistry。
 * agents_server 通过 NativeAgentRegistry.create("sts") 创建 StsChatAgentSession 实例。
 */
class StsChatAgentFlutterPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeAgentRegistry.register("sts") { StsChatAgentSession() }
        Log.d("StsChatAgentPlugin", "Registered NativeAgent type=sts")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
