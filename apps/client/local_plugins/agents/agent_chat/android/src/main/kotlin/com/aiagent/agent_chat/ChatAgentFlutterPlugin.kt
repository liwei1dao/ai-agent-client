package com.aiagent.agent_chat

import android.util.Log
import com.aiagent.plugin_interface.NativeAgentRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * ChatAgentFlutterPlugin — Chat Agent Flutter 插件入口
 *
 * 在 onAttachedToEngine 时注册 "chat" Agent 类型到 NativeAgentRegistry。
 * agents_server 通过 NativeAgentRegistry.create("chat") 创建 ChatAgentSession 实例。
 */
class ChatAgentFlutterPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeAgentRegistry.register("chat") { ChatAgentSession() }
        Log.d("ChatAgentPlugin", "Registered NativeAgent type=chat")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
