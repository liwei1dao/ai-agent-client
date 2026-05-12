import Flutter
import ai_plugin_interface

public class TranslationDeeplPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeServiceRegistry.shared.registerTranslation("deepl") { TranslationDeeplService() }
    }
}
