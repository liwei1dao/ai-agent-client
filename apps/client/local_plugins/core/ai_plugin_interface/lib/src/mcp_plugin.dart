import 'package:flutter/foundation.dart';

import 'llm_plugin.dart';

/// MCP 服务器配置（单 server 单实例）
@immutable
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.authHeader,
    this.enabledTools = const [],
    this.timeoutSeconds = 30,
    this.extraHeaders = const {},
  });

  /// 用户态 id（UUID 之类，跨 server 唯一），用于路由 toolName→server
  final String id;

  /// 展示名（仅用于日志/UI）
  final String name;

  /// 服务端点（Streamable HTTP 是单 endpoint，POST JSON-RPC）
  final String url;

  /// 可选认证头，如 `Bearer xxx`
  final String? authHeader;

  /// 启用的工具白名单；为空表示启用全部
  final List<String> enabledTools;

  /// 单次 RPC 超时
  final int timeoutSeconds;

  /// 额外 HTTP 头（如 X-Org / X-Project）
  final Map<String, String> extraHeaders;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        if (authHeader != null) 'authHeader': authHeader,
        if (enabledTools.isNotEmpty) 'enabledTools': enabledTools,
        'timeoutSeconds': timeoutSeconds,
        if (extraHeaders.isNotEmpty) 'extraHeaders': extraHeaders,
      };

  static McpServerConfig fromJson(Map<String, dynamic> m) => McpServerConfig(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? (m['id'] as String),
        url: m['url'] as String,
        authHeader: m['authHeader'] as String?,
        enabledTools: ((m['enabledTools'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        timeoutSeconds: (m['timeoutSeconds'] as num?)?.toInt() ?? 30,
        extraHeaders: ((m['extraHeaders'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
      );
}

/// MCP 工具描述（来自 server 的 tools/list）
@immutable
class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.serverId,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema; // JSON Schema
  final String serverId;

  /// 转成 LLM 厂商可以直接塞进 chat 请求的 tool 定义。
  LlmTool toLlmTool() => LlmTool(
        name: name,
        description: description,
        parameters: inputSchema.isNotEmpty
            ? inputSchema
            : const {'type': 'object', 'properties': {}},
      );
}

/// MCP 工具调用结果
@immutable
class McpToolResult {
  const McpToolResult({
    required this.content,
    this.isError = false,
    this.raw,
  });

  /// 文本结果（如果 server 返回多段 text content，拼接后给到 LLM）
  final String content;

  /// server 标记为错误（仍然是合法的响应，区别于网络异常）
  final bool isError;

  /// 原始 JSON-RPC result（调试用）
  final Map<String, dynamic>? raw;
}

/// MCP 插件抽象接口
///
/// **单实例对应单 server**。多 server 聚合由上层 `McpRouter` 负责。
///
/// 生命周期与 §2.1 一致：`uninitialized → initialize → ready → dispose → disposed`。
/// `initialize` 内必须完成 MCP 协议握手（`initialize` + `notifications/initialized`）；
/// 失败必须抛出 `McpException` 并把 server 标记为不可用。
abstract class McpPlugin {
  /// 握手并就绪
  Future<void> initialize(McpServerConfig config);

  /// 拉取该 server 的工具列表（按 enabledTools 过滤）
  Future<List<McpTool>> listTools();

  /// 调用工具
  Future<McpToolResult> callTool(String name, Map<String, dynamic> args);

  /// 释放资源（关闭 HTTP client，清理 sessionId 等）
  Future<void> dispose();
}

/// MCP 调用异常（错误码遵循 `mcp.<reason>`）
class McpException implements Exception {
  McpException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'McpException($code): $message';
}
