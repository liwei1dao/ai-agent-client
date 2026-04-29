import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// TranslationAliyunPlugin — 阿里云机器翻译 API（纯 Dart HTTP）
///
/// 使用阿里云通用版翻译 API（translate.aliyuncs.com）。
/// 每条消息独立翻译，无打断机制。
class TranslationAliyunPlugin implements TranslationPlugin {
  String? _accessKeyId;
  String? _accessKeySecret;

  @override
  Future<void> initialize({
    required String apiKey,
    Map<String, String> extra = const {},
  }) async {
    // apiKey 格式："{accessKeyId}:{accessKeySecret}"
    final parts = apiKey.split(':');
    _accessKeyId = parts[0];
    _accessKeySecret = parts.length > 1 ? parts[1] : '';
  }

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    final params = _buildParams(text, targetLanguage, sourceLanguage);
    final signature = _sign(params);
    params['Signature'] = signature;

    final uri = Uri.https('mt.aliyuncs.com', '/', params);
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Aliyun MT error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['Data'] as Map<String, dynamic>?;
    final translated = data?['Translated'] as String? ?? '';

    return TranslationResult(
      sourceText: text,
      translatedText: translated,
      sourceLanguage: _toAliyunLang(sourceLanguage) ?? 'auto',
      targetLanguage: _toAliyunLang(targetLanguage)!,
    );
  }

  @override
  Future<void> dispose() async {}

  Map<String, String> _buildParams(
    String text,
    String targetLanguage,
    String? sourceLanguage,
  ) {
    final now = DateTime.now().toUtc();
    return {
      'Action': 'TranslateGeneral',
      'Version': '2018-10-12',
      'AccessKeyId': _accessKeyId!,
      'SignatureMethod': 'HMAC-SHA1',
      'SignatureNonce': _randomNonce(),
      'SignatureVersion': '1.0',
      'Timestamp': _formatTimestamp(now),
      'Format': 'JSON',
      'SourceLanguage': _toAliyunLang(sourceLanguage) ?? 'auto',
      'TargetLanguage': _toAliyunLang(targetLanguage)!,
      'SourceText': text,
      'Scene': 'general',
    };
  }

  /// canonical → 阿里云机器翻译语言码（ISO 639-1 短码 + 部分中文变体）。
  static String? _toAliyunLang(String? code) {
    if (code == null || code.isEmpty) return null;
    final upper = code.trim().toUpperCase();
    switch (upper) {
      case 'AUTO':
        return 'auto';
      case 'ZH':
      case 'ZH-CN':
      case 'ZH-HANS':
        return 'zh';
      case 'ZH-TW':
      case 'ZH-HK':
      case 'ZH-HANT':
        return 'zh-tw';
      default:
        return upper.split('-').first.toLowerCase();
    }
  }

  String _sign(Map<String, String> params) {
    final sorted = params.keys.toList()..sort();
    final canonical = sorted
        .map((k) => '${Uri.encodeComponent(k)}=${Uri.encodeComponent(params[k]!)}')
        .join('&');
    final stringToSign = 'GET&${Uri.encodeComponent('/')}&${Uri.encodeComponent(canonical)}';
    final key = utf8.encode('$_accessKeySecret&');
    final message = utf8.encode(stringToSign);
    final hmac = Hmac(sha1, key);
    return base64.encode(hmac.convert(message).bytes);
  }

  String _randomNonce() {
    final rand = Random.secure();
    return List.generate(16, (_) => rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  String _formatTimestamp(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-'
      '${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}T'
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}Z';
}
