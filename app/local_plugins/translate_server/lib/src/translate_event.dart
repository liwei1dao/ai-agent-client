import 'package:flutter/foundation.dart';

/// 字幕角色：双向翻译两侧 + 单向翻译"媒体"。
enum SubtitleRole {
  /// 戴耳机的本机用户
  user,

  /// 通话对端 / 面对面对方
  peer,

  /// 系统媒体音视频翻译时的"内容源"
  media,
}

/// 文本阶段（与 §3.1 STT 文本约束语义对齐）。
enum SubtitleStage {
  /// 流式覆盖：UI 应整体替换该 role 的当前句
  partial,

  /// 一句结束：UI 累加到该 role 的提交文本
  finalized,
}

@immutable
class TranslateSubtitleEvent {
  const TranslateSubtitleEvent({
    required this.sessionId,
    required this.role,
    required this.stage,
    required this.sourceText,
    this.translatedText,
    this.sourceLanguage,
    this.destLanguage,
  });

  final String sessionId;
  final SubtitleRole role;
  final SubtitleStage stage;

  /// 识别原文（partial 阶段为累计快照；final 阶段为整句定稿）。
  final String sourceText;

  /// 翻译后的目标语文本；可能为 null（agent 还没出译文时）。
  final String? translatedText;

  final String? sourceLanguage;
  final String? destLanguage;
}

@immutable
class TranslateErrorEvent {
  const TranslateErrorEvent({
    required this.sessionId,
    required this.code,
    this.message,
    this.role,
    this.fatal = false,
  });

  final String sessionId;
  final String code;
  final String? message;

  /// 错误来源（哪条 leg / 设备 / 容器自身）。null = 容器级。
  final SubtitleRole? role;

  /// 是否致命：致命错误后 session 会自动 stop（state→stopping→stopped/error）。
  /// 非致命错误仅作日志/UI 提示，session 继续 active。
  final bool fatal;
}

enum TranslationServerEventType {
  sessionStarted,
  sessionStopped,
  error,
}

@immutable
class TranslationServerEvent {
  const TranslationServerEvent({
    required this.type,
    this.sessionId,
    this.errorCode,
    this.errorMessage,
  });

  final TranslationServerEventType type;
  final String? sessionId;
  final String? errorCode;
  final String? errorMessage;
}
