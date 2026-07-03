import 'dart:async';
import 'dart:convert';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:http/http.dart' as http;

/// MCP Streamable HTTP transport（MCP 2024-11-05）
///
/// 协议要点：
///   - 单一 endpoint，所有方法走 POST
///   - 请求 body 为 JSON-RPC 2.0
///   - 响应 Content-Type 可能是 `application/json` 或 `text/event-stream`
///     —— 后者按 SSE 解析出第一帧 `data:` 即为完整 JSON-RPC 响应
///   - 会话头：服务器在 `initialize` 响应中返回 `Mcp-Session-Id`，后续请求必须回带
///
/// 单实例对应单 server。多 server 由 `McpRouter` 聚合。
class McpHttpPlugin implements McpPlugin {
  late McpServerConfig _config;
  http.Client? _client;
  String? _sessionId;
  bool _initialized = false;
  int _rpcId = 0;

  @override
  Future<void> initialize(McpServerConfig config) async {
    if (_client != null) await dispose();
    _config = config;
    _client = http.Client();
    _sessionId = null;
    _initialized = false;
    _rpcId = 0;

    final initResult = await _rpc('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {'tools': {}},
      'clientInfo': {'name': 'ai-agent-client', 'version': '1.0.0'},
    });
    if (initResult['protocolVersion'] == null &&
        initResult['serverInfo'] == null) {
      throw McpException(
          'mcp.handshake_failed', 'initialize 响应缺少 protocolVersion / serverInfo');
    }
    await _rpcNotification('notifications/initialized', const {});
    _initialized = true;
  }

  @override
  Future<List<McpTool>> listTools() async {
    _ensureReady();
    final result = await _rpc('tools/list', const {});
    final list = (result['tools'] as List?) ?? const [];
    final whitelist = _config.enabledTools.toSet();
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => McpTool(
              name: (m['name'] as String?) ?? '',
              description: (m['description'] as String?) ?? '',
              inputSchema:
                  (m['inputSchema'] as Map?)?.cast<String, dynamic>() ??
                      const {},
              serverId: _config.id,
            ))
        .where((t) => t.name.isNotEmpty)
        .where((t) => whitelist.isEmpty || whitelist.contains(t.name))
        .toList();
  }

  @override
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    _ensureReady();
    final result = await _rpc('tools/call', {
      'name': name,
      'arguments': args,
    });

    final isError = result['isError'] == true;
    final contentList = (result['content'] as List?) ?? const [];
    final text = contentList
        .whereType<Map<String, dynamic>>()
        .where((c) => c['type'] == 'text')
        .map((c) => (c['text'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .join('\n');

    return McpToolResult(
      content: text,
      isError: isError,
      raw: result,
    );
  }

  @override
  Future<void> dispose() async {
    _client?.close();
    _client = null;
    _sessionId = null;
    _initialized = false;
  }

  // ─────────────────────────────────────────────────
  // 内部
  // ─────────────────────────────────────────────────

  void _ensureReady() {
    if (_client == null) {
      throw StateError('McpStreamableHttpPlugin disposed');
    }
    if (!_initialized) {
      throw StateError(
          'McpStreamableHttpPlugin not initialized — call initialize() first');
    }
  }

  Map<String, String> _buildHeaders() => {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/event-stream',
        if (_config.authHeader != null && _config.authHeader!.isNotEmpty)
          'Authorization': _config.authHeader!,
        if (_sessionId != null) 'Mcp-Session-Id': _sessionId!,
        ..._config.extraHeaders,
      };

  Future<Map<String, dynamic>> _rpc(
    String method,
    Map<String, dynamic> params,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('McpStreamableHttpPlugin disposed');
    }
    _rpcId++;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'id': _rpcId,
      'method': method,
      'params': params,
    });

    final http.Response resp;
    try {
      resp = await client
          .post(Uri.parse(_config.url),
              headers: _buildHeaders(), body: body)
          .timeout(Duration(seconds: _config.timeoutSeconds));
    } on TimeoutException {
      throw McpException('mcp.timeout', 'RPC $method 超时');
    } catch (e) {
      throw McpException('mcp.network_error', e.toString());
    }

    final sid = resp.headers['mcp-session-id'];
    if (sid != null && sid.isNotEmpty) _sessionId = sid;

    if (resp.statusCode != 200 && resp.statusCode != 202) {
      throw McpException(
          'mcp.http_${resp.statusCode}', _truncate(resp.body));
    }

    final json = _parseRpcBody(resp);
    if (json['error'] is Map) {
      final err = json['error'] as Map<String, dynamic>;
      throw McpException(
          'mcp.rpc_${err['code']}', (err['message'] ?? '').toString());
    }
    return (json['result'] as Map<String, dynamic>?) ?? const {};
  }

  Future<void> _rpcNotification(
    String method,
    Map<String, dynamic> params,
  ) async {
    final client = _client;
    if (client == null) return;
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });

    final http.Response resp;
    try {
      resp = await client
          .post(Uri.parse(_config.url),
              headers: _buildHeaders(), body: body)
          .timeout(Duration(seconds: _config.timeoutSeconds));
    } on TimeoutException {
      throw McpException('mcp.timeout', '通知 $method 超时');
    } catch (e) {
      throw McpException('mcp.network_error', e.toString());
    }

    final sid = resp.headers['mcp-session-id'];
    if (sid != null && sid.isNotEmpty) _sessionId = sid;
    if (resp.statusCode >= 400) {
      throw McpException(
          'mcp.http_${resp.statusCode}', _truncate(resp.body));
    }
  }

  /// Streamable HTTP 可能返回 application/json 或 text/event-stream，
  /// 二者都解析为 JSON-RPC 响应对象。
  Map<String, dynamic> _parseRpcBody(http.Response resp) {
    final ct = resp.headers['content-type'] ?? '';
    final body = resp.body;
    if (ct.contains('text/event-stream')) {
      for (final raw in body.split('\n')) {
        final line = raw.trimRight();
        if (line.startsWith('data:')) {
          final payload = line.substring(5).trimLeft();
          if (payload.isEmpty) continue;
          final decoded = jsonDecode(payload);
          if (decoded is Map<String, dynamic>) return decoded;
        }
      }
      throw McpException(
          'mcp.invalid_response', 'SSE 响应未包含 JSON-RPC data 帧');
    }
    if (body.isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw McpException('mcp.invalid_response', '响应不是 JSON-RPC 对象');
  }

  String _truncate(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}
