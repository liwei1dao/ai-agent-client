import 'package:flutter/foundation.dart';

/// 对话角色：双向（user 提问 / assistant 回复）。
enum AssistantRole {
  /// 戴耳机的本机用户（语音输入）
  user,

  /// AI 助理回复
  assistant,
}

/// 文本阶段（与翻译 server 的 SubtitleStage 语义一致）。
enum AssistantMessageStage {
  /// 流式覆盖：UI 应整体替换该 role 当前句
  partial,

  /// 一句结束：UI 累加到该 role 的提交文本
  finalized,
}

@immutable
class AssistantMessageEvent {
  const AssistantMessageEvent({
    required this.sessionId,
    required this.role,
    required this.stage,
    required this.text,
    this.requestId,
  });

  final String sessionId;
  final AssistantRole role;
  final AssistantMessageStage stage;

  /// 该角色的文本：
  /// - role=user/partial：STT 进行中的源文累计快照（无 requestId）
  /// - role=user/final：STT 一句源文定稿（带 requestId）
  /// - role=assistant/partial：LLM 流式增量 token（带 requestId）
  /// - role=assistant/final：LLM 完整回复（带 requestId）
  final String text;

  /// 同一对话回合标识：STT finalResult / LLM firstToken / LLM done 共享同一 requestId，
  /// UI 据此把"用户提问 + AI 回复"配成一对气泡，避免按到达顺序错位。
  final String? requestId;
}

@immutable
class AssistantErrorEvent {
  const AssistantErrorEvent({
    required this.sessionId,
    required this.code,
    this.message,
    this.role,
    this.fatal = false,
  });

  final String sessionId;
  final String code;
  final String? message;

  /// 错误来源（user 侧 STT / assistant 侧 LLM-TTS / 容器自身=null）。
  final AssistantRole? role;

  /// 是否致命：致命错误后 session 自动 stop（state→stopping→stopped/error）。
  final bool fatal;
}

enum AssistantServerEventType {
  sessionStarted,
  sessionStopped,
  error,
}

@immutable
class AssistantServerEvent {
  const AssistantServerEvent({
    required this.type,
    this.sessionId,
    this.errorCode,
    this.errorMessage,
  });

  final AssistantServerEventType type;
  final String? sessionId;
  final String? errorCode;
  final String? errorMessage;
}
