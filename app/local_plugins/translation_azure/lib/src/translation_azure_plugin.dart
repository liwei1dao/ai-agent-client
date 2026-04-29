import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// TranslationAzurePlugin — Microsoft / Azure Translator v3.0（纯 Dart HTTP）
///
/// 配置：apiKey（订阅密钥） + region（节点，如 eastus / eastasia / global）。
class TranslationAzurePlugin implements TranslationPlugin {
  static const _baseUrl = 'https://api.cognitive.microsofttranslator.com';

  String? _apiKey;
  String _region = 'global';

  @override
  Future<void> initialize({
    required String apiKey,
    Map<String, String> extra = const {},
  }) async {
    _apiKey = apiKey;
    final region = extra['region']?.trim();
    if (region != null && region.isNotEmpty) {
      _region = region;
    }
  }

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('translation.auth_failed: apiKey not configured');
    }

    final params = <String, String>{
      'api-version': '3.0',
      'to': _normalizeLang(targetLanguage)!,
      if (sourceLanguage != null && sourceLanguage.isNotEmpty)
        'from': _normalizeLang(sourceLanguage)!,
    };
    final uri = Uri.parse('$_baseUrl/translate').replace(queryParameters: params);

    final response = await http.post(
      uri,
      headers: {
        'Ocp-Apim-Subscription-Key': apiKey,
        'Ocp-Apim-Subscription-Region': _region,
        'Content-Type': 'application/json',
      },
      body: jsonEncode([
        {'Text': text},
      ]),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Azure Translator error: ${response.statusCode} ${response.body}');
    }

    final list = jsonDecode(utf8.decode(response.bodyBytes)) as List;
    if (list.isEmpty) {
      throw Exception('Azure Translator: empty response');
    }
    final first = list.first as Map<String, dynamic>;
    final translations = (first['translations'] as List?) ?? const [];
    if (translations.isEmpty) {
      throw Exception('Azure Translator: no translations returned');
    }
    final t = translations.first as Map<String, dynamic>;
    final detected = first['detectedLanguage'] as Map?;

    return TranslationResult(
      sourceText: text,
      translatedText: t['text'] as String? ?? '',
      sourceLanguage:
          (detected?['language'] as String?) ?? sourceLanguage ?? 'auto',
      targetLanguage: (t['to'] as String?) ?? targetLanguage,
    );
  }

  @override
  Future<void> dispose() async {}

  /// Normalize various code shapes to Azure Translator BCP-47:
  ///   ZH / zh / zh-CN → zh-Hans
  ///   ZH-TW / zh-TW   → zh-Hant
  ///   EN / en / en-US → en
  /// Already-valid BCP-47 codes are passed through (lower-cased prefix +
  /// title-cased script) to be safe.
  static String? _normalizeLang(String? code) {
    if (code == null || code.isEmpty) return code;
    final c = code.trim();
    final upper = c.toUpperCase();
    switch (upper) {
      case 'ZH':
      case 'ZH-CN':
      case 'ZH-HANS':
      case 'CMN':
      case 'CMN-HANS':
        return 'zh-Hans';
      case 'ZH-TW':
      case 'ZH-HK':
      case 'ZH-HANT':
        return 'zh-Hant';
      case 'EN':
      case 'EN-US':
      case 'EN-GB':
        return 'en';
      case 'JA':
      case 'JA-JP':
        return 'ja';
      case 'KO':
      case 'KO-KR':
        return 'ko';
      case 'FR':
      case 'FR-FR':
        return 'fr';
      case 'DE':
      case 'DE-DE':
        return 'de';
      case 'ES':
      case 'ES-ES':
        return 'es';
      case 'RU':
      case 'RU-RU':
        return 'ru';
      case 'AR':
        return 'ar';
      case 'PT':
      case 'PT-PT':
        return 'pt-pt';
      case 'PT-BR':
        return 'pt';
      case 'IT':
        return 'it';
      case 'TH':
        return 'th';
      case 'VI':
        return 'vi';
      case 'ID':
        return 'id';
      case 'TR':
        return 'tr';
      default:
        return c; // assume caller already gave a valid BCP-47 code
    }
  }
}
