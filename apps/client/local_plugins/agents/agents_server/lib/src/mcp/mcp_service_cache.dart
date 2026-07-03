import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// 进程级 MCP plugin + tool list 缓存（单例）。
///
/// 设计动机：每次 [WebChatAgent] 创建都重复做 `initialize` 握手 +
/// `listTools()` HTTP 请求，多 agent 同绑同一 MCP server 时尤其浪费。MCP
/// 工具列表是 server 端状态，正常情况下进程生命周期内不变。
///
/// 行为：
/// - 按 `serverId` 索引；同 id 配置（fingerprint）变更时丢弃旧 entry 重建
/// - `getOrInit` 串行化（per-id），并发首启不会重复握手
/// - 缓存条目永不主动过期；显式 `evict(id)` / `evictAll()` 用于"用户改配置"
class McpServiceCache {
  McpServiceCache._();
  static final McpServiceCache instance = McpServiceCache._();

  final Map<String, _Entry> _entries = {};
  final Map<String, Future<_Entry>> _inflight = {};

  /// 取 server 的 (plugin, tools)，没缓存或 fingerprint 变了就 init。
  /// 失败抛异常，由调用方记 warning，不污染缓存。
  Future<({McpPlugin plugin, List<McpTool> tools})> getOrInit({
    required McpServerConfig config,
    required McpPlugin Function(String transport) pluginFactory,
    String transport = 'streamable_http',
  }) async {
    final fp = _fingerprint(config, transport);
    final existing = _entries[config.id];
    if (existing != null &&
        existing.fingerprint == fp &&
        existing.transport == transport) {
      return (plugin: existing.plugin, tools: existing.tools);
    }

    // 同 id 并发首启：复用同一个 Future，避免重复握手
    final pending = _inflight[config.id];
    if (pending != null) {
      final e = await pending;
      if (e.fingerprint == fp && e.transport == transport) {
        return (plugin: e.plugin, tools: e.tools);
      }
      // 配置在等待期间又变了 → 落到下面重新 init
    }

    final future = _initEntry(config, pluginFactory, transport, fp);
    _inflight[config.id] = future;
    try {
      final entry = await future;
      return (plugin: entry.plugin, tools: entry.tools);
    } finally {
      _inflight.remove(config.id);
    }
  }

  Future<_Entry> _initEntry(
    McpServerConfig config,
    McpPlugin Function(String transport) pluginFactory,
    String transport,
    String fingerprint,
  ) async {
    // 若有旧 entry（fingerprint 不匹配），先释放
    final old = _entries.remove(config.id);
    if (old != null) {
      try {
        await old.plugin.dispose();
      } catch (_) {}
    }

    final plugin = pluginFactory(transport);
    try {
      await plugin.initialize(config);
      final tools = await plugin.listTools();
      final entry =
          _Entry(plugin: plugin, tools: tools, fingerprint: fingerprint, transport: transport);
      _entries[config.id] = entry;
      return entry;
    } catch (e) {
      try {
        await plugin.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  /// 用户在 UI 改了某个 MCP server 配置时调用。下次 getOrInit 会重建。
  Future<void> evict(String serverId) async {
    final e = _entries.remove(serverId);
    if (e != null) {
      try {
        await e.plugin.dispose();
      } catch (_) {}
    }
  }

  Future<void> evictAll() async {
    final all = _entries.values.toList();
    _entries.clear();
    for (final e in all) {
      try {
        await e.plugin.dispose();
      } catch (_) {}
    }
  }

  /// fingerprint：取配置中影响连接 + 工具暴露的字段。不含 `name`。
  /// `enabledTools` / `extraHeaders` 排序后参与 hash 保证稳定。
  String _fingerprint(McpServerConfig c, String transport) {
    final tools = [...c.enabledTools]..sort();
    final headerKeys = c.extraHeaders.keys.toList()..sort();
    final headers = headerKeys.map((k) => '$k=${c.extraHeaders[k]}').join('&');
    return [
      'transport=$transport',
      'url=${c.url}',
      'auth=${c.authHeader ?? ''}',
      'timeout=${c.timeoutSeconds}',
      'tools=${tools.join(",")}',
      'headers=$headers',
    ].join('|');
  }
}

class _Entry {
  _Entry({
    required this.plugin,
    required this.tools,
    required this.fingerprint,
    required this.transport,
  });
  final McpPlugin plugin;
  final List<McpTool> tools;
  final String fingerprint;
  final String transport;
}
