package com.aiagent.mcp

import android.util.Log
import com.aiagent.plugin_interface.NativeServiceRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * McpFlutterPlugin — Flutter 插件入口
 *
 * onAttachedToEngine 时把当前包内的 transport 实现注册到 NativeServiceRegistry。
 * 当前只注册 Streamable HTTP（MCP 2024-11-05）；后续要加 SSE 旧版时在此追加。
 */
class McpFlutterPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        NativeServiceRegistry.registerMcp("streamable_http") { McpStreamableHttpService() }
        Log.d("McpFlutterPlugin", "Registered NativeMcpService for transport: streamable_http")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // no-op
    }
}
