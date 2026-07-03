package com.aiagent.sts_polychat

import io.flutter.embedding.engine.plugins.FlutterPlugin
import com.aiagent.plugin_interface.NativeServiceRegistry
import com.aiagent.plugin_interface.VoitransWebRtcSession

/**
 * Flutter 插件入口：注册 vendor "polychat" 到 NativeServiceRegistry (STS)
 */
class StsPolychatPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        NativeServiceRegistry.registerSts("polychat") { StsPolychatService(context) }
        // 预初始化 WebRTC Factory，避免首次连接卡顿
        VoitransWebRtcSession.warmup(context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
