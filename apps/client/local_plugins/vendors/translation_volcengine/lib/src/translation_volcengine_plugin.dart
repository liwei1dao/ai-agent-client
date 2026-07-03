import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// TranslationVolcenginePlugin — 火山引擎机器翻译 API（纯 Dart HTTP）
///
/// 调用火山引擎 OpenAPI 网关的 `TranslateText` 接口，使用火山引擎签名 V4
/// （HMAC-SHA256）鉴权。每条消息独立翻译，无打断机制。
///
/// 配置字段（来自服务配置 JSON，web bridge 会拆成 apiKey + extra 两部分）：
///   - accessKeyId:     火山引擎 Access Key ID
///   - secretAccessKey: 火山引擎 Secret Access Key
///   - region:          地域，默认 cn-north-1
class TranslationVolcenginePlugin implements TranslationPlugin {
  // 火山引擎机器翻译 OpenAPI 网关常量，与原生侧实现保持一致。
  static const String _host = 'open.volcengineapi.com';
  static const String _service = 'translate';
  static const String _action = 'TranslateText';
  static const String _version = '2020-06-01';
  static const String _defaultRegion = 'cn-north-1';

  String _accessKeyId = '';
  String _secretAccessKey = '';
  String _region = _defaultRegion;

  @override
  Future<void> initialize({
    required String apiKey,
    Map<String, String> extra = const {},
  }) async {
    // accessKeyId / secretAccessKey 通过 extra 传入（服务配置表单的独立字段）；
    // 同时兼容把 apiKey 写成 "{accessKeyId}:{secretAccessKey}" 的形式。
    _accessKeyId = extra['accessKeyId']?.trim() ?? '';
    _secretAccessKey = extra['secretAccessKey']?.trim() ?? '';
    if ((_accessKeyId.isEmpty || _secretAccessKey.isEmpty) &&
        apiKey.contains(':')) {
      final parts = apiKey.split(':');
      _accessKeyId = parts[0].trim();
      _secretAccessKey = parts.length > 1 ? parts[1].trim() : '';
    }
    final region = extra['region']?.trim();
    if (region != null && region.isNotEmpty) _region = region;
  }

  @override
  Future<TranslationResult> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async {
    if (_accessKeyId.isEmpty || _secretAccessKey.isEmpty) {
      throw Exception(
          'translation.auth_failed: Volcengine accessKeyId/secretAccessKey not configured');
    }

    final from = _toVolcLang(sourceLanguage);
    final to = _toVolcLang(targetLanguage) ?? targetLanguage;

    final body = jsonEncode({
      'SourceLanguage': from ?? '', // 空字符串 → 自动检测
      'TargetLanguage': to,
      'TextList': [text],
    });

    final uri = Uri.https(_host, '/', {
      'Action': _action,
      'Version': _version,
    });
    final response =
        await http.post(uri, headers: _signedHeaders(body), body: body);

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    // 火山引擎错误以 ResponseMetadata.Error 返回，HTTP 状态码可能仍是非 200。
    final meta = decoded['ResponseMetadata'] as Map<String, dynamic>?;
    final apiError = meta?['Error'] as Map<String, dynamic>?;
    if (apiError != null) {
      throw Exception('Volcengine translate error: '
          '${apiError['Code']} ${apiError['Message']}');
    }
    if (response.statusCode != 200) {
      throw Exception('Volcengine translate HTTP ${response.statusCode}');
    }

    final list = (decoded['TranslationList'] as List?) ?? const [];
    if (list.isEmpty) {
      throw Exception('Volcengine translate: empty TranslationList');
    }
    final first = list.first as Map<String, dynamic>;
    final detected = first['DetectedSourceLanguage'] as String?;

    return TranslationResult(
      sourceText: text,
      translatedText: first['Translation'] as String? ?? '',
      sourceLanguage: (detected != null && detected.isNotEmpty)
          ? detected
          : (from ?? 'auto'),
      targetLanguage: to,
    );
  }

  @override
  Future<void> dispose() async {}

  // ── 火山引擎签名 V4 ──────────────────────────────────────────────────

  /// 构造已签名的请求头。火山引擎 V4 与 AWS V4 类似，但派生签名密钥时
  /// 直接使用 SecretAccessKey（不加 "AWS4" 前缀）。
  Map<String, String> _signedHeaders(String body) {
    final now = DateTime.now().toUtc();
    final xDate = _formatXDate(now); // 20250521T120000Z
    final shortDate = xDate.substring(0, 8); // 20250521

    final payloadHash = sha256.convert(utf8.encode(body)).toString();
    final canonicalQuery = 'Action=$_action&Version=$_version';

    // 参与签名的 header：lowercase + 按字典序排列。
    final canonicalHeaders = 'content-type:application/json\n'
        'host:$_host\n'
        'x-content-sha256:$payloadHash\n'
        'x-date:$xDate\n';
    const signedHeaders = 'content-type;host;x-content-sha256;x-date';

    final canonicalRequest = [
      'POST',
      '/',
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final credentialScope = '$shortDate/$_region/$_service/request';
    final stringToSign = [
      'HMAC-SHA256',
      xDate,
      credentialScope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final signature = Hmac(sha256, _signingKey(shortDate))
        .convert(utf8.encode(stringToSign))
        .toString();

    final authorization = 'HMAC-SHA256 '
        'Credential=$_accessKeyId/$credentialScope, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';

    // Host 由 HTTP client 自动写入（浏览器禁止手动设置），故不放进 headers。
    return {
      'Content-Type': 'application/json',
      'X-Date': xDate,
      'X-Content-Sha256': payloadHash,
      'Authorization': authorization,
    };
  }

  List<int> _hmac(List<int> key, String msg) =>
      Hmac(sha256, key).convert(utf8.encode(msg)).bytes;

  /// kSigning = HMAC(HMAC(HMAC(HMAC(SK, date), region), service), "request")
  List<int> _signingKey(String shortDate) {
    final kDate = _hmac(utf8.encode(_secretAccessKey), shortDate);
    final kRegion = _hmac(kDate, _region);
    final kService = _hmac(kRegion, _service);
    return _hmac(kService, 'request');
  }

  String _formatXDate(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}T'
      '${dt.hour.toString().padLeft(2, '0')}'
      '${dt.minute.toString().padLeft(2, '0')}'
      '${dt.second.toString().padLeft(2, '0')}Z';

  /// canonical → 火山引擎翻译语言码（ISO 639-1 短码 + 中文变体）。
  /// 返回 null 表示自动检测（仅对源语言有意义）。
  static String? _toVolcLang(String? code) {
    if (code == null || code.isEmpty) return null;
    switch (code.trim().toUpperCase()) {
      case 'AUTO':
        return null;
      case 'ZH':
      case 'ZH-CN':
      case 'ZH-HANS':
        return 'zh';
      case 'ZH-TW':
      case 'ZH-HK':
      case 'ZH-HANT':
        return 'zh-Hant';
      default:
        return code.split('-').first.toLowerCase();
    }
  }
}
