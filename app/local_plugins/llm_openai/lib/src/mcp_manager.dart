import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// McpServerConfig — 远程 MCP 服务器配置
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.transport,
    this.authHeader,
    this.enabledTools = const [],
  });

  final String id;
  final String name;
  final String url;
  final String transport; // 'sse' | 'http'
  final String? authHeader;
  final List<String> enabledTools; // 已启用工具名称列表
}

/// McpTool — 工具定义（从 MCP 服务器获取或本地注册）
class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.serverId, // 'local' 或远程 server id
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String serverId;

  LlmTool toLlmTool() => LlmTool(
        name: name,
        description: description,
        parameters: inputSchema,
      );
}

/// McpManager — 本地内置工具 + 远程 MCP 服务器路由
///
/// - 本地工具直接注册，调用时在 Dart 内执行
/// - 远程工具通过 SSE 或 HTTP 转发给 MCP 服务器
class McpManager {
  McpManager._();
  static final McpManager instance = McpManager._();

  final _localHandlers = <String, Future<String> Function(Map<String, dynamic>)>{};
  final _remoteServers = <String, McpServerConfig>{};
  final _remoteTools = <String, McpTool>{}; // name → tool

  // ─────────────────────────────────────────────────
  // 本地工具注册
  // ─────────────────────────────────────────────────

  void registerLocalTool({
    required String name,
    required String description,
    required Map<String, dynamic> inputSchema,
    required Future<String> Function(Map<String, dynamic> args) handler,
  }) {
    _localHandlers[name] = handler;
    _remoteTools[name] = McpTool(
      name: name,
      description: description,
      inputSchema: inputSchema,
      serverId: 'local',
    );
  }

  // ─────────────────────────────────────────────────
  // 远程 MCP 服务器管理
  // ─────────────────────────────────────────────────

  /// 连接远程 MCP 服务器并获取工具列表
  Future<List<McpTool>> connectServer(McpServerConfig serverConfig) async {
    _remoteServers[serverConfig.id] = serverConfig;

    final tools = await _fetchRemoteTools(serverConfig);
    for (final tool in tools) {
      if (serverConfig.enabledTools.isEmpty ||
          serverConfig.enabledTools.contains(tool.name)) {
        _remoteTools[tool.name] = tool;
      }
    }
    return tools;
  }

  void removeServer(String serverId) {
    _remoteServers.remove(serverId);
    _remoteTools.removeWhere((_, tool) => tool.serverId == serverId);
  }

  // ─────────────────────────────────────────────────
  // 工具调用路由
  // ─────────────────────────────────────────────────

  /// 获取所有已注册工具（用于 LLM tools 参数）
  List<LlmTool> get allTools =>
      _remoteTools.values.map((t) => t.toLlmTool()).toList();

  /// 执行工具调用
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    final tool = _remoteTools[name];
    if (tool == null) return 'Error: tool "$name" not found';

    if (tool.serverId == 'local') {
      final handler = _localHandlers[name];
      if (handler == null) return 'Error: no handler for "$name"';
      return handler(args);
    }

    final server = _remoteServers[tool.serverId];
    if (server == null) return 'Error: server "${tool.serverId}" not connected';

    return _callRemoteTool(server, name, args);
  }

  // ─────────────────────────────────────────────────
  // 内部：HTTP 工具调用
  // ─────────────────────────────────────────────────

  Future<List<McpTool>> _fetchRemoteTools(McpServerConfig server) async {
    try {
      final uri = Uri.parse('${server.url}/tools/list');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (server.authHeader != null) 'Authorization': server.authHeader!,
      };

      final response = await http
          .post(uri, headers: headers, body: jsonEncode({}))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final toolsList = json['tools'] as List? ?? [];

      return toolsList.map((t) {
        final tool = t as Map<String, dynamic>;
        return McpTool(
          name: tool['name'] as String,
          description: tool['description'] as String? ?? '',
          inputSchema: tool['inputSchema'] as Map<String, dynamic>? ?? {},
          serverId: server.id,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<String> _callRemoteTool(
    McpServerConfig server,
    String toolName,
    Map<String, dynamic> args,
  ) async {
    try {
      final uri = Uri.parse('${server.url}/tools/call');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (server.authHeader != null) 'Authorization': server.authHeader!,
      };

      final body = jsonEncode({'name': toolName, 'arguments': args});
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return 'Error: HTTP ${response.statusCode}';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final content = json['content'] as List?;
      if (content == null || content.isEmpty) return '';

      return content
          .whereType<Map<String, dynamic>>()
          .where((c) => c['type'] == 'text')
          .map((c) => c['text'] as String)
          .join('\n');
    } catch (e) {
      return 'Error: $e';
    }
  }
}
