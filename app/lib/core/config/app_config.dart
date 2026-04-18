import 'package:flutter_dotenv/flutter_dotenv.dart';

/// AppConfig — 从 .env 文件读取所有 API Key
class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  // STT
  String get azureSttKey => dotenv.env['AZURE_STT_KEY'] ?? '';
  String get azureSttRegion => dotenv.env['AZURE_STT_REGION'] ?? '';
  String get aliyunSttKey => dotenv.env['ALIYUN_STT_KEY'] ?? '';
  String get googleSttKey => dotenv.env['GOOGLE_STT_KEY'] ?? '';
  String get doubaoSttKey => dotenv.env['DOUBAO_STT_KEY'] ?? '';

  // TTS
  String get azureTtsKey => dotenv.env['AZURE_TTS_KEY'] ?? '';
  String get azureTtsRegion => dotenv.env['AZURE_TTS_REGION'] ?? '';
  String get aliyunTtsKey => dotenv.env['ALIYUN_TTS_KEY'] ?? '';
  String get doubaoTtsKey => dotenv.env['DOUBAO_TTS_KEY'] ?? '';

  // LLM
  String get openaiApiKey => dotenv.env['OPENAI_API_KEY'] ?? '';
  String get openaiBaseUrl =>
      dotenv.env['OPENAI_BASE_URL'] ?? 'https://api.openai.com/v1';
  String get openaiModel => dotenv.env['OPENAI_MODEL'] ?? 'gpt-4o';
  String get cozeApiKey => dotenv.env['COZE_API_KEY'] ?? '';

  // STS
  String get doubaoStsKey => dotenv.env['DOUBAO_STS_KEY'] ?? '';
  String get doubaoStsAppId => dotenv.env['DOUBAO_STS_APP_ID'] ?? '';

  // Translation
  String get deeplApiKey => dotenv.env['DEEPL_API_KEY'] ?? '';
  String get aliyunTranslationKey => dotenv.env['ALIYUN_TRANSLATION_KEY'] ?? '';
  String get googleTranslateKey => dotenv.env['GOOGLE_TRANSLATE_KEY'] ?? '';

  // PolyChat（默认平台配置，SharedPreferences 为空时使用）
  String get polychatBaseUrl => dotenv.env['POLYCHAT_BASE_URL'] ?? '';
  String get polychatAppId => dotenv.env['POLYCHAT_APP_ID'] ?? '';
  String get polychatAppSecret => dotenv.env['POLYCHAT_APP_SECRET'] ?? '';
}
