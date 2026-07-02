import Flutter
import Foundation

/// 占位 FlutterPlugin：内核由**纯原生 agents_server 直接使用**，无需 Flutter 通道。
public class AgentKernelPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {}
}
