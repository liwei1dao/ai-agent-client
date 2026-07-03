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
        'target_lang': _toDeeplTarget(targetLanguage),
        if (sourceLanguage != null &&
            sourceLanguage.isNotEmpty &&
            _toDeeplSource(sourceLanguage).isNotEmpty)
          'source_lang': _toDeeplSource(sourceLanguage),
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

  /// canonical（zh-CN / en-US / pt-BR …） → DeepL `target_lang`。
  /// DeepL 接受带地区的形式（EN-US/EN-GB/PT-BR/PT-PT/ZH-HANS/ZH-HANT），
  /// 其它语种用大写两字（JA/KO/...）。
  static String _toDeeplTarget(String code) {
    final upper = code.trim().toUpperCase();
    switch (upper) {
      case 'ZH':
      case 'ZH-CN':
      case 'ZH-HANS':
        return 'ZH-HANS';
      case 'ZH-TW':
      case 'ZH-HK':
      case 'ZH-HANT':
        return 'ZH-HANT';
      case 'EN':
      case 'EN-US':
        return 'EN-US';
      case 'EN-GB':
        return 'EN-GB';
      case 'PT':
      case 'PT-BR':
        return 'PT-BR';
      case 'PT-PT':
        return 'PT-PT';
      default:
        return upper.split('-').first;
    }
  }

  /// canonical → DeepL `source_lang`：基本上是大写两字。
  static String _toDeeplSource(String code) {
    final upper = code.trim().toUpperCase();
    if (upper == 'AUTO') return ''; // DeepL 不传 source_lang 即自动检测
    return upper.split('-').first;
  }
}
