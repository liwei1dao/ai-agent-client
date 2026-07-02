package ai.unihelper.agentkernel

import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * 占位 FlutterPlugin：本包核心是被**纯原生 agents_server 直接使用**的编排内核，
 * 不需要 Flutter 通道。保留空注册仅为满足插件打包声明。
 */
class AgentKernelPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
