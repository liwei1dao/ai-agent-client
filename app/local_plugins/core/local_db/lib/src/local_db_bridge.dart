import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LocalDbBridge — 本地数据访问门面。
///
/// - **移动端（Android / iOS）**：通过 MethodChannel 访问原生 SQLite（Room / GRDB）。
///   原生层是数据主体，agent 原生运行时直接访问原生 DB，无需经过此 Channel。
/// - **桌面（macOS / Windows / Linux）**：无原生 DB 实现，改用 [SharedPreferences]
///   持久化（与 web 端 `local_db_bridge_web.dart` 同一套逻辑），避免调用桌面侧
///   不存在的 `local_db/commands` 原生 handler 而抛 MissingPluginException。
///
/// 条件导入无法区分 mobile 与 desktop（两者都满足 `dart.library.io`），故这里
/// 在 default 分支内用运行时 [defaultTargetPlatform] 选择具体实现。
class LocalDbBridge {
  static final LocalDbBridge _instance = LocalDbBridge._();
  LocalDbBridge._() : _impl = _pickImpl();
  factory LocalDbBridge() => _instance;

  final _LocalDbImpl _impl;

  static _LocalDbImpl _pickImpl() {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return isDesktop ? _PrefsLocalDb() : _MethodChannelLocalDb();
  }

  // ── ServiceConfig ──────────────────────────────────────────────────────

  Future<void> upsertServiceConfig(ServiceConfigDto dto) =>
      _impl.upsertServiceConfig(dto);

  Future<void> deleteServiceConfig(String id) => _impl.deleteServiceConfig(id);

  Future<List<ServiceConfigDto>> getAllServiceConfigs() =>
      _impl.getAllServiceConfigs();

  // ── Agent ──────────────────────────────────────────────────────────────

  Future<void> upsertAgent(AgentDto dto) => _impl.upsertAgent(dto);

  Future<void> deleteAgent(String id) => _impl.deleteAgent(id);

  Future<List<AgentDto>> getAllAgents() => _impl.getAllAgents();

  // ── Message ────────────────────────────────────────────────────────────

  Future<void> deleteMessages(String agentId) => _impl.deleteMessages(agentId);

  Future<List<MessageDto>> getMessages(String agentId, {int limit = 50}) =>
      _impl.getMessages(agentId, limit: limit);

  // ── McpServer ──────────────────────────────────────────────────────────

  Future<void> upsertMcpServer(McpServerDto dto) => _impl.upsertMcpServer(dto);

  Future<void> deleteMcpServer(String id) => _impl.deleteMcpServer(id);

  Future<List<McpServerDto>> getMcpServersByAgent(String agentId) =>
      _impl.getMcpServersByAgent(agentId);
}

/// 内部实现契约：移动端 [_MethodChannelLocalDb] 与桌面 [_PrefsLocalDb] 各实现一份。
abstract interface class _LocalDbImpl {
  Future<void> upsertServiceConfig(ServiceConfigDto dto);
  Future<void> deleteServiceConfig(String id);
  Future<List<ServiceConfigDto>> getAllServiceConfigs();
  Future<void> upsertAgent(AgentDto dto);
  Future<void> deleteAgent(String id);
  Future<List<AgentDto>> getAllAgents();
  Future<void> deleteMessages(String agentId);
  Future<List<MessageDto>> getMessages(String agentId, {int limit});
  Future<void> upsertMcpServer(McpServerDto dto);
  Future<void> deleteMcpServer(String id);
  Future<List<McpServerDto>> getMcpServersByAgent(String agentId);
}

/// 移动端实现：MethodChannel → 原生 SQLite。
class _MethodChannelLocalDb implements _LocalDbImpl {
  static const _channel = MethodChannel('local_db/commands');

  @override
  Future<void> upsertServiceConfig(ServiceConfigDto dto) =>
      _channel.invokeMethod('upsertServiceConfig', dto.toMap());

  @override
  Future<void> deleteServiceConfig(String id) =>
      _channel.invokeMethod('deleteServiceConfig', {'id': id});

  @override
  Future<List<ServiceConfigDto>> getAllServiceConfigs() async {
    final list = await _channel.invokeMethod<List>('getAllServiceConfigs');
    return (list ?? [])
        .cast<Map<Object?, Object?>>()
        .map(ServiceConfigDto.fromMap)
        .toList();
  }

  @override
  Future<void> upsertAgent(AgentDto dto) =>
      _channel.invokeMethod('upsertAgent', dto.toMap());

  @override
  Future<void> deleteAgent(String id) =>
      _channel.invokeMethod('deleteAgent', {'id': id});

  @override
  Future<List<AgentDto>> getAllAgents() async {
    final list = await _channel.invokeMethod<List>('getAllAgents');
    return (list ?? [])
        .cast<Map<Object?, Object?>>()
        .map(AgentDto.fromMap)
        .toList();
  }

  @override
  Future<void> deleteMessages(String agentId) =>
      _channel.invokeMethod('deleteMessages', {'agentId': agentId});

  @override
  Future<List<MessageDto>> getMessages(String agentId, {int limit = 50}) async {
    final list = await _channel.invokeMethod<List>('getMessages', {
      'agentId': agentId,
      'limit': limit,
    });
    return (list ?? [])
        .cast<Map<Object?, Object?>>()
        .map(MessageDto.fromMap)
        .toList();
  }

  @override
  Future<void> upsertMcpServer(McpServerDto dto) =>
      _channel.invokeMethod('upsertMcpServer', dto.toMap());

  @override
  Future<void> deleteMcpServer(String id) =>
      _channel.invokeMethod('deleteMcpServer', {'id': id});

  @override
  Future<List<McpServerDto>> getMcpServersByAgent(String agentId) async {
    final list = await _channel.invokeMethod<List>('getMcpServersByAgent', {
      'agentId': agentId,
    });
    return (list ?? [])
        .cast<Map<Object?, Object?>>()
        .map(McpServerDto.fromMap)
        .toList();
  }
}

/// 桌面实现：SharedPreferences 持久化（JSON 编码列表）。
/// 逻辑与 web 端 `local_db_bridge_web.dart` 保持一致。
class _PrefsLocalDb implements _LocalDbImpl {
  static const _kServiceConfigs = 'local_db.service_configs';
  static const _kAgents = 'local_db.agents';
  static const _kMessagesPrefix = 'local_db.messages.';
  static const _kMcpServersPrefix = 'local_db.mcp_servers.';

  SharedPreferences? _prefs;
  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  List<Map<String, dynamic>> _readList(SharedPreferences p, String key) {
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> _writeList(
    SharedPreferences p,
    String key,
    List<Map<String, dynamic>> list,
  ) async {
    await p.setString(key, jsonEncode(list));
  }

  @override
  Future<void> upsertServiceConfig(ServiceConfigDto dto) async {
    final p = await _p;
    final list = _readList(p, _kServiceConfigs);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(dto.toMap());
    await _writeList(p, _kServiceConfigs, list);
  }

  @override
  Future<void> deleteServiceConfig(String id) async {
    final p = await _p;
    final list = _readList(p, _kServiceConfigs);
    list.removeWhere((m) => m['id'] == id);
    await _writeList(p, _kServiceConfigs, list);
  }

  @override
  Future<List<ServiceConfigDto>> getAllServiceConfigs() async {
    final p = await _p;
    return _readList(p, _kServiceConfigs)
        .map(ServiceConfigDto.fromMap)
        .toList();
  }

  @override
  Future<void> upsertAgent(AgentDto dto) async {
    final p = await _p;
    final list = _readList(p, _kAgents);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(dto.toMap());
    await _writeList(p, _kAgents, list);
  }

  @override
  Future<void> deleteAgent(String id) async {
    final p = await _p;
    final list = _readList(p, _kAgents);
    list.removeWhere((m) => m['id'] == id);
    await _writeList(p, _kAgents, list);
    await p.remove('$_kMessagesPrefix$id');
    await p.remove('$_kMcpServersPrefix$id');
  }

  @override
  Future<List<AgentDto>> getAllAgents() async {
    final p = await _p;
    return _readList(p, _kAgents).map(AgentDto.fromMap).toList();
  }

  @override
  Future<void> deleteMessages(String agentId) async {
    final p = await _p;
    await p.remove('$_kMessagesPrefix$agentId');
  }

  @override
  Future<List<MessageDto>> getMessages(String agentId, {int limit = 50}) async {
    final p = await _p;
    final list = _readList(p, '$_kMessagesPrefix$agentId')
        .map(MessageDto.fromMap)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  @override
  Future<void> upsertMcpServer(McpServerDto dto) async {
    final p = await _p;
    final key = '$_kMcpServersPrefix${dto.agentId}';
    final list = _readList(p, key);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(dto.toMap());
    await _writeList(p, key, list);
  }

  @override
  Future<void> deleteMcpServer(String id) async {
    final p = await _p;
    final keys = p.getKeys().where((k) => k.startsWith(_kMcpServersPrefix));
    for (final key in keys) {
      final list = _readList(p, key);
      final before = list.length;
      list.removeWhere((m) => m['id'] == id);
      if (list.length != before) {
        await _writeList(p, key, list);
      }
    }
  }

  @override
  Future<List<McpServerDto>> getMcpServersByAgent(String agentId) async {
    final p = await _p;
    return _readList(p, '$_kMcpServersPrefix$agentId')
        .map(McpServerDto.fromMap)
        .toList();
  }
}

// ─────────────────────────────────────────────────
// DTO 数据类
// ─────────────────────────────────────────────────

class ServiceConfigDto {
  const ServiceConfigDto({
    required this.id,
    required this.type,
    required this.vendor,
    required this.name,
    required this.configJson,
    required this.createdAt,
  });

  final String id;
  final String type;   // stt | tts | llm | sts | translation
  final String vendor;
  final String name;
  final String configJson;
  final int createdAt;

  Map<String, dynamic> toMap() => {
        'id': id, 'type': type, 'vendor': vendor,
        'name': name, 'configJson': configJson, 'createdAt': createdAt,
      };

  static ServiceConfigDto fromMap(Map<Object?, Object?> m) => ServiceConfigDto(
        id: m['id'] as String,
        type: m['type'] as String,
        vendor: m['vendor'] as String,
        name: m['name'] as String,
        configJson: m['configJson'] as String,
        createdAt: m['createdAt'] as int,
      );
}

class AgentDto {
  const AgentDto({
    required this.id,
    required this.name,
    required this.type,
    required this.configJson,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String type;   // chat | translate
  final String configJson;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'type': type,
        'configJson': configJson,
        'createdAt': createdAt, 'updatedAt': updatedAt,
      };

  static AgentDto fromMap(Map<Object?, Object?> m) => AgentDto(
        id: m['id'] as String,
        name: m['name'] as String,
        type: m['type'] as String,
        configJson: m['configJson'] as String,
        createdAt: m['createdAt'] as int,
        updatedAt: m['updatedAt'] as int,
      );
}

class MessageDto {
  const MessageDto({
    required this.id,
    required this.agentId,
    required this.role,
    required this.content,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;       // requestId
  final String agentId;
  final String role;     // user | assistant | system
  final String content;
  final String status;   // pending | streaming | done | cancelled | error
  final int createdAt;
  final int updatedAt;

  static MessageDto fromMap(Map<Object?, Object?> m) => MessageDto(
        id: m['id'] as String,
        agentId: m['agentId'] as String,
        role: m['role'] as String,
        content: m['content'] as String,
        status: m['status'] as String,
        createdAt: m['createdAt'] as int,
        updatedAt: m['updatedAt'] as int,
      );
}

class McpServerDto {
  const McpServerDto({
    required this.id,
    required this.agentId,
    required this.name,
    required this.url,
    required this.transport,
    this.authHeader,
    required this.enabledToolsJson,
    required this.isEnabled,
    required this.createdAt,
  });

  final String id;
  final String agentId;
  final String name;
  final String url;
  final String transport; // sse | http
  final String? authHeader;
  final String enabledToolsJson;
  final bool isEnabled;
  final int createdAt;

  Map<String, dynamic> toMap() => {
        'id': id, 'agentId': agentId, 'name': name, 'url': url,
        'transport': transport, 'authHeader': authHeader,
        'enabledToolsJson': enabledToolsJson,
        'isEnabled': isEnabled, 'createdAt': createdAt,
      };

  static McpServerDto fromMap(Map<Object?, Object?> m) => McpServerDto(
        id: m['id'] as String,
        agentId: m['agentId'] as String,
        name: m['name'] as String,
        url: m['url'] as String,
        transport: m['transport'] as String,
        authHeader: m['authHeader'] as String?,
        enabledToolsJson: m['enabledToolsJson'] as String,
        isEnabled: m['isEnabled'] as bool,
        createdAt: m['createdAt'] as int,
      );
}
