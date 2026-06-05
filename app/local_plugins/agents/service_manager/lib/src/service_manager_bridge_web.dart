import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;
import 'package:ast_polychat/ast_polychat_web.dart';
import 'package:ast_volcengine/ast_volcengine_web.dart';
import 'package:llm_openai/llm_openai.dart';
import 'package:llm_volcengine/llm_volcengine.dart';
import 'package:local_db/local_db.dart';
import 'package:sts_volcengine/sts_volcengine.dart';
import 'package:sts_polychat/sts_polychat_web.dart';
import 'package:stt_azure/stt_azure.dart';
import 'package:translation_aliyun/translation_aliyun.dart';
import 'package:translation_azure/translation_azure.dart';
import 'package:translation_deepl/translation_deepl.dart';
import 'package:translation_volcengine/translation_volcengine.dart';
import 'package:tts_azure/tts_azure.dart';

import 'dart_service_tester.dart';
import 'service_manager_api.dart';

/// Web implementation of [ServiceManagerBridge]. 复用共享的 [DartServiceTester]，
/// 注入浏览器侧厂商工厂与 LocalDb（web = SharedPreferences）配置加载。
class ServiceManagerBridge extends DartServiceTester {
  static final ServiceManagerBridge _instance = ServiceManagerBridge._();
  ServiceManagerBridge._()
      : super(const _WebServiceTestFactory(), _loadConfig);
  factory ServiceManagerBridge() => _instance;

  static Future<ServiceConfigRecord?> _loadConfig(String serviceId) async {
    final all = await LocalDbBridge().getAllServiceConfigs();
    for (final c in all) {
      if (c.id == serviceId) {
        return ServiceConfigRecord(
          type: c.type,
          vendor: c.vendor,
          configJson: c.configJson,
        );
      }
    }
    return null;
  }
}

class _WebServiceTestFactory implements ServiceTestFactory {
  const _WebServiceTestFactory();

  @override
  ai.SttPlugin createStt(String vendor) {
    switch (vendor) {
      case 'azure':
        return SttAzurePluginDart();
      default:
        throw UnimplementedError('STT vendor "$vendor" not available on web');
    }
  }

  @override
  ai.TtsPlugin createTts(String vendor) {
    switch (vendor) {
      case 'azure':
        return TtsAzurePluginDart();
      default:
        throw UnimplementedError('TTS vendor "$vendor" not available on web');
    }
  }

  @override
  ai.LlmPlugin createLlm(String vendor) {
    switch (vendor) {
      case 'openai':
        return LlmOpenaiPlugin();
      case 'volcengine':
      case 'doubao': // legacy alias
        return LlmVolcenginePlugin();
      default:
        throw UnimplementedError('LLM vendor "$vendor" not available on web');
    }
  }

  @override
  ai.StsPlugin createSts(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao':
      case 'bytedance':
        return StsVolcenginePlugin();
      case 'polychat':
        return StsPolychatPluginWeb();
      default:
        throw UnimplementedError('STS vendor "$vendor" not available on web');
    }
  }

  @override
  ai.AstPlugin createAst(String vendor) {
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

  @override
  ai.TranslationPlugin createTranslation(String vendor) {
    switch (vendor) {
      case 'deepl':
        return TranslationDeeplPlugin();
      case 'aliyun':
        return TranslationAliyunPlugin();
      case 'azure':
      case 'microsoft':
        return TranslationAzurePlugin();
      case 'volcengine':
        return TranslationVolcenginePlugin();
      default:
        throw UnimplementedError(
            'Translation vendor "$vendor" not available on web');
    }
  }
}
