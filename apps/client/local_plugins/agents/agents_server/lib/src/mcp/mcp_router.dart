import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// 多 MCP server 聚合路由器
///
/// - 持有多个 [McpPlugin] 实例（每个 server 一个）
/// - 聚合所有工具列表（toolName 冲突时**先到先得**，后到者打日志跳过）
/// - 按 toolName 路由 callTool 到对应 server
///
/// 单 chat agent 实例独占一个 router；router 的生命周期与 agent 一致：
/// `addServer × N → listAllTools → callTool* → dispose`
///
/// 注：进程级缓存在 [McpServiceCache]（保留备用）—— 当前 router 走直连，
/// 之前接进缓存触发了"LLM 看不到工具"的回归，先回退到稳定版。
class McpRouter {
  McpRouter({required this.pluginFactory});

  /// 工厂：根据传输类型创建对应的 [McpPlugin]（暂只支持 `streamable_http`）。
  final McpPlugin Function(String transport) pluginFactory;

  final Map<String, McpPlugin> _plugins = {}; // serverId -> plugin
  final Map<String, McpTool> _toolByName = {}; // toolName -> tool（含 serverId）
  final List<String> _warnings = [];

  /// 已聚合的工具列表（顺序：按 server 添加顺序，再按 server 内顺序）
  List<McpTool> get tools => _toolByName.values.toList(growable: false);

  /// 给 LLM 用的 tool 定义
  List<LlmTool> get llmTools =>
      tools.map((t) => t.toLlmTool()).toList(growable: false);

  /// 添加并初始化一个 server。失败不抛，转为 warning 记录，使其它 server 可继续工作。
  Future<void> addServer(
    McpServerConfig config, {
    String transport = 'streamable_http',
  }) async {
    if (_plugins.containsKey(config.id)) return;
    final plugin = pluginFactory(transport);
    try {
      await plugin.initialize(config);
      final serverTools = await plugin.listTools();
      _plugins[config.id] = plugin;
      for (final t in serverTools) {
        if (_toolByName.containsKey(t.name)) {
          _warnings.add(
              'tool "${t.name}" from server "${config.name}" shadowed by earlier server');
          continue;
        }
        _toolByName[t.name] = t;
      }
    } catch (e) {
      _warnings.add('connect server "${config.name}" failed: $e');
      try {
        await plugin.dispose();
      } catch (_) {}
    }
  }

  /// 调用工具。toolName 不存在或对应 server 已 dispose 时返回错误结果（不抛）。
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    final tool = _toolByName[name];
    if (tool == null) {
      return McpToolResult(
        content: 'Error: tool "$name" not found',
        isError: true,
      );
    }
    final plugin = _plugins[tool.serverId];
    if (plugin == null) {
      return McpToolResult(
        content: 'Error: server "${tool.serverId}" not connected',
        isError: true,
      );
    }
    try {
      return await plugin.callTool(name, args);
    } on McpException catch (e) {
      return McpToolResult(
        content: 'Error: ${e.code} ${e.message}',
        isError: true,
      );
    } catch (e) {
      return McpToolResult(content: 'Error: $e', isError: true);
    }
  }

  /// 警告日志（连接失败、工具名冲突等）；UI 层可展示给用户。
  List<String> get warnings => List.unmodifiable(_warnings);

  Future<void> dispose() async {
    for (final p in _plugins.values) {
      try {
        await p.dispose();
      } catch (_) {}
    }
    _plugins.clear();
    _toolByName.clear();
    _warnings.clear();
  }
}
