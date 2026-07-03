import 'dart:convert';
import 'package:http/http.dart' as http;

/// PolyChat 平台 Agent 公开信息
class PolychatAgent {
  const PolychatAgent({
    required this.agentId,
    required this.name,
    required this.type,
    this.avatarUrl,
    this.description,
    this.supportedLangs = const [],
  });

  final String agentId;
  final String name;
  final String type; // "sts-chat" | "ast-translate" | "chat" | "translate"
  final String? avatarUrl;
  final String? description;
  final List<String> supportedLangs; // 平台返回的支持语言列表

  factory PolychatAgent.fromJson(Map<String, dynamic> json) {
    final raw = (json['supported_languages'] as List?) ?? const [];
    final normalized = <String>{
      for (final e in raw)
        if (e is String && e.trim().isNotEmpty) _normalizeLangCode(e),
    };
    return PolychatAgent(
      agentId: json['agent_id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      avatarUrl: json['avatar_url'] as String?,
      description: json['description'] as String?,
      supportedLangs: normalized.toList(),
    );
  }
}

/// Normalize a BCP-47 / IETF language tag (e.g. `zh-CN`, `en_US`) down to its
/// ISO 639-1 primary subtag (`zh`, `en`) — the format used internally by the
/// app's language pickers.
String _normalizeLangCode(String raw) {
  final lower = raw.trim().toLowerCase();
  if (lower.isEmpty) return '';
  final sep = lower.indexOf(RegExp(r'[-_]'));
  return sep > 0 ? lower.substring(0, sep) : lower;
}

/// PolyChat 平台 HTTP 客户端
class PolychatApiClient {
  PolychatApiClient({
    required this.baseUrl,
    required this.appId,
    required this.appSecret,
  });

  final String baseUrl;
  final String appId;
  final String appSecret;

  Map<String, String> get _headers => {
        'X-App-Id': appId,
        'X-App-Secret': appSecret,
        'Content-Type': 'application/json',
      };

  String get _base => baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

  /// 获取平台 Agent 列表
  Future<List<PolychatAgent>> fetchAgents() async {
    final uri = Uri.parse('$_base/open/v1/agents');
    final resp = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

    if (resp.statusCode != 200) {
      throw Exception('获取 Agent 列表失败: ${resp.statusCode} ${resp.body}');
    }

    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final agents = (body['agents'] as List)
        .map((e) => PolychatAgent.fromJson(e as Map<String, dynamic>))
        .toList();
    return agents;
  }

}
