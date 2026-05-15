import Flutter
import UIKit

@objc public class JielihomePlugin: NSObject, FlutterPlugin {

    private var router: MethodRouter?

    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "device_jieli/method",
            binaryMessenger: registrar.messenger()
        )
        let eventChannel = FlutterEventChannel(
            name: "device_jieli/event",
            binaryMessenger: registrar.messenger()
        )

        let server = JieliHomeServer.shared
        let plugin = JielihomePlugin()
        let router = MethodRouter(server: server)
        plugin.router = router

        methodChannel.setMethodCallHandler { [weak router] call, result in
            router?.handle(call: call, result: result)
        }
        eventChannel.setStreamHandler(server.dispatcher)

        registrar.addMethodCallDelegate(plugin, channel: methodChannel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // 真正的 method 分派在 setMethodCallHandler 闭包里直接走 router；
        // 这里仅是 FlutterPlugin 协议要求。
        router?.handle(call: call, result: result)
    }
}
