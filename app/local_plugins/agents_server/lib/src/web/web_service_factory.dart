import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:ast_polychat/ast_polychat_web.dart';
import 'package:ast_volcengine/ast_volcengine.dart';
import 'package:llm_openai/llm_openai.dart';
import 'package:sts_doubao/sts_doubao.dart';
import 'package:sts_polychat/sts_polychat_web.dart';
import 'package:stt_azure/stt_azure.dart';
import 'package:translation_aliyun/translation_aliyun.dart';
import 'package:translation_deepl/translation_deepl.dart';
import 'package:tts_azure/tts_azure.dart';

/// Maps vendor names to their web implementation classes. Mirrors the native
/// `NativeServiceRegistry` on Android but lives entirely in Dart for the web.
class WebServiceFactory {
  static SttPlugin createStt(String vendor) {
    switch (vendor) {
      case 'azure':
        return SttAzurePluginDart();
      default:
        throw UnimplementedError('STT vendor "$vendor" not available on web');
    }
  }

  static TtsPlugin createTts(String vendor) {
    switch (vendor) {
      case 'azure':
        return TtsAzurePluginDart();
      default:
        throw UnimplementedError('TTS vendor "$vendor" not available on web');
    }
  }

  static LlmPlugin createLlm(String vendor) {
    switch (vendor) {
      case 'openai':
        return LlmOpenaiPlugin();
      default:
        throw UnimplementedError('LLM vendor "$vendor" not available on web');
    }
  }

  static StsPlugin createSts(String vendor) {
    switch (vendor) {
      case 'doubao':
      case 'volcengine':
      case 'bytedance':
        return StsDoubaoPlugin();
      case 'polychat':
        return StsPolychatPluginWeb();
      default:
        throw UnimplementedError('STS vendor "$vendor" not available on web');
    }
  }

  static AstPlugin createAst(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao':
      case 'bytedance':
        return AstVolcenginePluginWeb();
      case 'polychat':
        return AstPolychatPluginWeb();
      default:
        throw UnimplementedError('AST vendor "$vendor" not available on web');
    }
  }

  static TranslationPlugin createTranslation(String vendor) {
    switch (vendor) {
      case 'deepl':
        return TranslationDeeplPlugin();
      case 'aliyun':
        return TranslationAliyunPlugin();
      default:
        throw UnimplementedError(
          'Translation vendor "$vendor" not available on web',
        );
    }
  }
}
