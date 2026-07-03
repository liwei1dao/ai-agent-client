import Flutter
import ai_plugin_interface

public class TranslationAliyunPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeServiceRegistry.shared.registerTranslation("aliyun") { TranslationAliyunService() }
    }
}
