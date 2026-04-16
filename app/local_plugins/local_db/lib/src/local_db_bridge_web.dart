import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Web implementation of LocalDbBridge backed by SharedPreferences (IndexedDB).
/// Mirrors the public API of the mobile bridge so that agents_server/service_manager
/// can use the same code paths.
class LocalDbBridge {
  static const _kServiceConfigs = 'local_db.service_configs';
  static const _kAgents = 'local_db.agents';
  static const _kMessagesPrefix = 'local_db.messages.';
  static const _kMcpServersPrefix = 'local_db.mcp_servers.';

  static final LocalDbBridge _instance = LocalDbBridge._();
  LocalDbBridge._();
  factory LocalDbBridge() => _instance;

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

  // ── ServiceConfig ──────────────────────────────────────────────────────

  Future<void> upsertServiceConfig(ServiceConfigDto dto) async {
    final p = await _p;
    final list = _readList(p, _kServiceConfigs);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(dto.toMap());
    await _writeList(p, _kServiceConfigs, list);
  }

  Future<void> deleteServiceConfig(String id) async {
    final p = await _p;
    final list = _readList(p, _kServiceConfigs);
    list.removeWhere((m) => m['id'] == id);
    await _writeList(p, _kServiceConfigs, list);
  }

  Future<List<ServiceConfigDto>> getAllServiceConfigs() async {
    final p = await _p;
    return _readList(p, _kServiceConfigs).map(ServiceConfigDto.fromMap).toList();
  }

  // ── Agent ──────────────────────────────────────────────────────────────

  Future<void> upsertAgent(AgentDto dto) async {
    final p = await _p;
    final list = _readList(p, _kAgents);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(dto.toMap());
    await _writeList(p, _kAgents, list);
  }

  Future<void> deleteAgent(String id) async {
    final p = await _p;
    final list = _readList(p, _kAgents);
    list.removeWhere((m) => m['id'] == id);
    await _writeList(p, _kAgents, list);
    await p.remove('$_kMessagesPrefix$id');
    await p.remove('$_kMcpServersPrefix$id');
  }

  Future<List<AgentDto>> getAllAgents() async {
    final p = await _p;
    return _readList(p, _kAgents).map(AgentDto.fromMap).toList();
  }

  // ── Message ────────────────────────────────────────────────────────────

  Future<void> deleteMessages(String agentId) async {
    final p = await _p;
    await p.remove('$_kMessagesPrefix$agentId');
  }

  Future<List<MessageDto>> getMessages(String agentId, {int limit = 50}) async {
    final p = await _p;
    final list = _readList(p, '$_kMessagesPrefix$agentId')
        .map(MessageDto.fromMap)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  /// Web-only helper used by the Dart agent runtime to persist messages.
  Future<void> insertMessage(MessageDto dto) async {
    final p = await _p;
    final key = '$_kMessagesPrefix${dto.agentId}';
    final list = _readList(p, key);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(_messageToMap(dto));
    await _writeList(p, key, list);
  }

  Future<void> updateMessageStatus(
    String agentId,
    String messageId,
    String status,
    int updatedAt,
  ) async {
    final p = await _p;
    final key = '$_kMessagesPrefix$agentId';
    final list = _readList(p, key);
    for (final m in list) {
      if (m['id'] == messageId) {
        m['status'] = status;
        m['updatedAt'] = updatedAt;
      }
    }
    await _writeList(p, key, list);
  }

  Future<void> appendMessageContent(
    String agentId,
    String messageId,
    String delta,
    int updatedAt,
  ) async {
    final p = await _p;
    final key = '$_kMessagesPrefix$agentId';
    final list = _readList(p, key);
    for (final m in list) {
      if (m['id'] == messageId) {
        m['content'] = '${m['content'] ?? ''}$delta';
        m['updatedAt'] = updatedAt;
      }
    }
    await _writeList(p, key, list);
  }

  Map<String, dynamic> _messageToMap(MessageDto m) => {
        'id': m.id,
        'agentId': m.agentId,
        'role': m.role,
        'content': m.content,
        'status': m.status,
        'createdAt': m.createdAt,
        'updatedAt': m.updatedAt,
      };

  // ── McpServer ──────────────────────────────────────────────────────────

  Future<void> upsertMcpServer(McpServerDto dto) async {
    final p = await _p;
    final key = '$_kMcpServersPrefix${dto.agentId}';
    final list = _readList(p, key);
    list.removeWhere((m) => m['id'] == dto.id);
    list.add(dto.toMap());
    await _writeList(p, key, list);
  }

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

  Future<List<McpServerDto>> getMcpServersByAgent(String agentId) async {
    final p = await _p;
    return _readList(p, '$_kMcpServersPrefix$agentId')
        .map(McpServerDto.fromMap)
        .toList();
  }
}

// ─────────────────────────────────────────────────
// DTO classes (identical to the mobile bridge)
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
  final String type;
  final String vendor;
  final String name;
  final String configJson;
  final int createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'vendor': vendor,
        'name': name,
        'configJson': configJson,
        'createdAt': createdAt,
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
  final String type;
  final String configJson;
  final int createdAt;
  final int updatedAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'configJson': configJson,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
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

  final String id;
  final String agentId;
  final String role;
  final String content;
  final String status;
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
  final String transport;
  final String? authHeader;
  final String enabledToolsJson;
  final bool isEnabled;
  final int createdAt;

  Map<String, dynamic> toMap() => {
        'id': id,
        'agentId': agentId,
        'name': name,
        'url': url,
        'transport': transport,
        'authHeader': authHeader,
        'enabledToolsJson': enabledToolsJson,
        'isEnabled': isEnabled,
        'createdAt': createdAt,
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
