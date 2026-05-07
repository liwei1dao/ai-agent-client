import 'dart:async';

import 'assistant_event.dart';

enum AssistantSessionState {
  starting,
  active,
  stopping,
  stopped,
  error,
}

/// 一个活跃的 AI 助理会话。
abstract class AssistantSession {
  String get sessionId;
  AssistantSessionState get state;

  /// 创建时间（UTC ms）。
  int get startedAtMs;

  /// agent 类型（当前为 `chat`）。
  String get agentType;

  /// 用户语言标签。
  String get userLanguage;

  /// 对话消息流。**broadcast** 流——晚订阅会丢历史事件，
  /// 用 [latestMessageByRole] 拿快照即可补上。
  Stream<AssistantMessageEvent> get messages;

  /// 错误流。错误**不**自动关闭 session，除非 fatal == true（致命错误后 session
  /// 会自动 stop，state→stopping→stopped/error）。
  Stream<AssistantErrorEvent> get errors;

  /// 状态变化流。
  Stream<AssistantSessionState> get stateStream;

  /// 该 role 最近一次 message 快照；用于 UI 晚加载时重建当前文本状态。
  AssistantMessageEvent? latestMessageByRole(AssistantRole role);

  /// 仅订阅指定 role 的消息。
  Stream<AssistantMessageEvent> messagesOf(AssistantRole role) =>
      messages.where((e) => e.role == role);

  Future<void> stop();
}
