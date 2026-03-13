import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// TranslationDeeplPlugin — DeepL API v2 翻译（纯 Dart HTTP）
///
/// 每条消息独立翻译，无打断机制。
class TranslationDeeplPlugin implements TranslationPlugin {
  String? _apiKey;
  static const _baseUrl = 'https://api-free.deepl.com/v2';

  @override
  Future<void> initialize({
    required String apiKey,
    Map<String, String> extra = const {},
  }) async {
    _apiKey = apiKey;
    // 付费 API 使用 api.deepl.com
    // extra['isPro'] == 'true' → 切换 baseUrl
  }

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/translate'),
      headers: {
        'Authorization': 'DeepL-Auth-Key $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'text': [text],
        'target_lang': targetLanguage.toUpperCase(),
        if (sourceLanguage != null) 'source_lang': sourceLanguage.toUpperCase(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('DeepL API error: ${response.statusCode} ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final translations = json['translations'] as List;
    final first = translations.first as Map<String, dynamic>;

    return TranslationResult(
      sourceText: text,
      translatedText: first['text'] as String,
      sourceLanguage: (first['detected_source_language'] as String?)?.toLowerCase() ??
          sourceLanguage ?? 'auto',
      targetLanguage: targetLanguage,
    );
  }

  @override
  Future<void> dispose() async {}
}
