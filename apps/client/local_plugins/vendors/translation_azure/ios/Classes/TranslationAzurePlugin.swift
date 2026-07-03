import Flutter
import ai_plugin_interface

public class TranslationAzurePlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        NativeServiceRegistry.shared.registerTranslation("azure") { TranslationAzureService() }
    }
}
