import 'package:flutter/services.dart';

/// LocalDbBridge — Flutter 侧通过 MethodChannel 访问原生 SQLite
///
/// 原生层（Room/GRDB）是数据主体，Flutter 仅做读取和写入配置数据。
/// agent_runtime 直接访问原生 DB，无需经过此 Channel。
class LocalDbBridge {
  static const _channel = MethodChannel('local_db/commands');

  static final LocalDbBridge _instance = LocalDbBridge._();
  LocalDbBridge._();
  factory LocalDbBridge() => _instance;

  // ── ServiceConfig ──────────────────────────────────────────────────────

  Future<void> upsertServiceConfig(ServiceConfigDto dto) =>
      _channel.invokeMethod('upsertServiceConfig', dto.toMap());

  Future<void> deleteServiceConfig(String id) =>
      _channel.invokeMethod('deleteServiceConfig', {'id': id});

  Future<List<ServiceConfigDto>> getAllServiceConfigs() async {
    final list = await _channel.invokeMethod<List>('getAllServiceConfigs');
    return (list ?? [])
        .cast<Map<Object?, Object?>>()
        .map(ServiceConfigDto.fromMap)
        .toList();
  }

  // ── Agent ──────────────────────────────────────────────────────────────

  Future<void> upsertAgent(AgentDto dto) =>
      _channel.invokeMethod('upsertAgent', dto.toMap());

  Future<void> deleteAgent(String id) =>
      _channel.invokeMethod('deleteAgent', {'id': id});

  Future<List<AgentDto>> getAllAgents() async {
    final list = await _channel.invokeMethod<List>('getAllAgents');
    return (list ?? [])
        .cast<Map<Object?, Object?>>()
        .map(AgentDto.fromMap)
        .toList();
  }

  // ── Message ────────────────────────────────────────────────────────────

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

  // ── McpServer ──────────────────────────────────────────────────────────

  Future<void> upsertMcpServer(McpServerDto dto) =>
      _channel.invokeMethod('upsertMcpServer', dto.toMap());

  Future<void> deleteMcpServer(String id) =>
      _channel.invokeMethod('deleteMcpServer', {'id': id});

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
