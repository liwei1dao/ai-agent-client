package com.aiagent.sts_voitrans

import io.flutter.embedding.engine.plugins.FlutterPlugin
import com.aiagent.plugin_interface.NativeServiceRegistry
import com.aiagent.plugin_interface.VoitransWebRtcSession

/**
 * Flutter 插件入口：注册 vendor "voitrans" 到 NativeServiceRegistry (STS)
 */
class StsVoitransPlugin : FlutterPlugin {

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        NativeServiceRegistry.registerSts("voitrans") { StsVoitransService(context) }
        // 预初始化 WebRTC Factory，避免首次连接卡顿
        VoitransWebRtcSession.warmup(context)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
