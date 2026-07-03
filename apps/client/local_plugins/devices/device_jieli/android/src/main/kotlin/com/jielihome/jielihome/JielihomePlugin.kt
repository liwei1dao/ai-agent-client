package com.jielihome.jielihome

import com.jielihome.jielihome.bridge.MethodRouter
import com.jielihome.jielihome.core.JieliHomeServer
import com.jielihome.jielihome.integration.JieliNativeDevicePlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 入口，仅负责注册 Channel 并把请求转交给 MethodRouter。
 * 全部业务逻辑在 [JieliHomeServer] 与 feature/event 子模块中。
 */
class JielihomePlugin : FlutterPlugin {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var router: MethodRouter

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val server = JieliHomeServer.get()
        router = MethodRouter(binding.applicationContext, server)

        methodChannel = MethodChannel(binding.binaryMessenger, "device_jieli/method")
        methodChannel.setMethodCallHandler(router)

        eventChannel = EventChannel(binding.binaryMessenger, "device_jieli/event")
        eventChannel.setStreamHandler(server.dispatcher)

        // 把杰理 vendor 注册到 device_manager 的 NativeDevicePluginRegistry：
        // 这样 app 走 device_manager 路径时能 listVendors / useVendor("jieli")。
        // SDK 直连路径（device_jieli/method 上面那条）保留不变；两条路径并存。
        JieliNativeDevicePlugin.register(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        // 进程级资源不在这里 shutdown，保持后续 attach 仍可继续使用
    }
}
