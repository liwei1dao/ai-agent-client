import Flutter
import ai_plugin_interface

public class TranslationVolcenginePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeServiceRegistry.shared.registerTranslation("volcengine") {
            TranslationVolcengineService()
        }
    }
}
