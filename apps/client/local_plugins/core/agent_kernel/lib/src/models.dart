/// 核心类型：任务信封 / 事件 / 能力 / 确认 / 唤醒。对齐 UniHelper-agents-protocol.md。
library;

typedef AgentId = String;

enum AgentStatus { ok, partial, rejected, failed }

/// 专员的能力描述符（管家路由/展示用）。
class AgentCapability {
  final AgentId id;
  final String name;

  /// 规则路由关键词（命中即候选）。
  final List<String> keywords;
  final String description;

  /// 可被哪些唤醒源直唤（如 device/hotword/schedule）。
  final List<String> triggers;

  const AgentCapability({
    required this.id,
    required this.name,
    this.keywords = const [],
    this.description = '',
    this.triggers = const [],
  });
}

/// A2A 任务信封（管家 → 专员）。
class TaskEnvelope {
  final String taskId;
  final String requestId;
  final AgentId from;
  final AgentId to;
  final String intent;
  final String text;
  final Map<String, dynamic> params;

  /// 管家注入的上下文（KB/记忆），专员可直接用。
  final String? context;
  final String? userId;
  final bool needConfirm;

  const TaskEnvelope({
    required this.taskId,
    required this.requestId,
    required this.from,
    required this.to,
    required this.intent,
    required this.text,
    this.params = const {},
    this.context,
    this.userId,
    this.needConfirm = false,
  });
}

/// 专员回传事件（流式）。
sealed class AgentEvent {
  const AgentEvent();
}

class AgentPartial extends AgentEvent {
  final String text;
  const AgentPartial(this.text);
}

class AgentProgress extends AgentEvent {
  final String note;
  const AgentProgress(this.note);
}

class AgentResult extends AgentEvent {
  final AgentStatus status;
  final String text;
  final Map<String, dynamic> data;
  final List<Citation> citations;
  const AgentResult({
    this.status = AgentStatus.ok,
    required this.text,
    this.data = const {},
    this.citations = const [],
  });
}

/// 高风险动作 → 上报管家向用户确认（安全闸口）。
class AgentNeedConfirm extends AgentEvent {
  final Confirm confirm;
  const AgentNeedConfirm(this.confirm);
}

class AgentError extends AgentEvent {
  final String code;
  final String message;
  const AgentError(this.code, this.message);
}

class Citation {
  final String title;
  final String? ref;
  const Citation(this.title, {this.ref});
}

class Confirm {
  final String id;
  final String actionKind; // send_email | payment | delete | calendar_write ...
  final String summary;
  final Map<String, dynamic> preview;
  final bool editable;
  const Confirm({
    required this.id,
    required this.actionKind,
    required this.summary,
    this.preview = const {},
    this.editable = true,
  });
}

/// 管家对用户的统一回复（无论内部几个专员参与，一个声音）。
class ManagerReply {
  final String text;
  final List<AgentId> usedAgents;
  final List<Citation> citations;
  final Confirm? pendingConfirm;
  const ManagerReply({
    required this.text,
    this.usedAgents = const [],
    this.citations = const [],
    this.pendingConfirm,
  });

  bool get needsConfirm => pendingConfirm != null;
}

// ─── 唤醒 ───────────────────────────────────────────────
enum WakeSource { device, hotword, schedule, incomingCall, geofence, push }

class WakeEvent {
  final WakeSource source;
  final String sourceId;
  final String? utterance; // 已带的语音/文本意图（如设备端 STT 结果）
  final Map<String, dynamic> payload;
  const WakeEvent({
    required this.source,
    required this.sourceId,
    this.utterance,
    this.payload = const {},
  });
}

/// 自治触发上下文（调度引擎 → 专员 onTrigger）。
class TriggerContext {
  final String kind; // "subscription:news_daily" | "reminder" ...
  final String source;
  final Map<String, dynamic> params;
  const TriggerContext({required this.kind, required this.source, this.params = const {}});
}
