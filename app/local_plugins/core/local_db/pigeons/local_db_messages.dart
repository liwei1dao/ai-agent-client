// ignore_for_file: avoid_classes_with_only_static_members
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/local_db_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/aiagent/local_db/LocalDbApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.aiagent.local_db'),
    swiftOut: 'ios/Classes/LocalDbApi.g.swift',
    dartPackageName: 'local_db',
  ),
)

// ─────────────────────────────────────────────────
// 数据类
// ─────────────────────────────────────────────────

class ServiceConfigRow {
  ServiceConfigRow({
    required this.id,
    required this.type, // 'stt' | 'tts' | 'llm' | 'sts' | 'translation'
    required this.vendor,
    required this.name,
    required this.configJson,
    required this.createdAt,
  });

  late String id;
  late String type;
  late String vendor;
  late String name;
  late String configJson;
  late int createdAt;
}

class AgentRow {
  AgentRow({
    required this.id,
    required this.name,
    required this.type, // 'chat' | 'translate'
    required this.configJson,
    required this.createdAt,
    required this.updatedAt,
  });

  late String id;
  late String name;
  late String type;
  late String configJson;
  late int createdAt;
  late int updatedAt;
}

class MessageRow {
  MessageRow({
    required this.id, // requestId (UUID)
    required this.agentId,
    required this.role, // 'user' | 'assistant' | 'system'
    required this.content,
    required this.status, // 'pending' | 'streaming' | 'done' | 'cancelled' | 'error'
    required this.createdAt,
    required this.updatedAt,
  });

  late String id;
  late String agentId;
  late String role;
  late String content;
  late String status;
  late int createdAt;
  late int updatedAt;
}

class McpServerRow {
  McpServerRow({
    required this.id,
    required this.agentId,
    required this.name,
    required this.url,
    required this.transport, // 'sse' | 'http'
    this.authHeader,
    required this.enabledToolsJson, // JSON array of tool names
    required this.isEnabled,
    required this.createdAt,
  });

  late String id;
  late String agentId;
  late String name;
  late String url;
  late String transport;
  late String? authHeader;
  late String enabledToolsJson;
  late bool isEnabled;
  late int createdAt;
}

// ─────────────────────────────────────────────────
// CRUD 接口（Flutter → Native，通过 Pigeon）
// ─────────────────────────────────────────────────

@HostApi()
abstract class LocalDbApi {
  // ── ServiceConfig ──────────────────────────────
  void upsertServiceConfig(ServiceConfigRow row);
  void deleteServiceConfig(String id);
  List<ServiceConfigRow> getAllServiceConfigs();

  // ── Agent ──────────────────────────────────────
  void upsertAgent(AgentRow row);
  void deleteAgent(String id);
  List<AgentRow> getAllAgents();

  // ── Message ────────────────────────────────────
  void insertMessage(MessageRow row);
  void updateMessageStatus(String id, String status);
  void appendMessageContent(String id, String delta);

  /// 查询某 Agent 的历史消息（按 createdAt 升序，limit 最近 N 条）
  List<MessageRow> getMessages(String agentId, int limit);

  // ── McpServer ──────────────────────────────────
  void upsertMcpServer(McpServerRow row);
  void deleteMcpServer(String id);
  List<McpServerRow> getMcpServersByAgent(String agentId);
}
