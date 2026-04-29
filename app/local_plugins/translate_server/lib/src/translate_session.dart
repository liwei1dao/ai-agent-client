import 'dart:async';

import 'translate_event.dart';

enum TranslationKind { call, faceToFace, audio }

enum TranslationSessionState {
  starting,
  active,
  stopping,
  stopped,
  error,
}

/// 三种业务共用的会话基类。子类只是个语义标签（[kind]），
/// 真正的差异都在 native 编排器里。
abstract class TranslationSession {
  String get sessionId;
  TranslationKind get kind;
  TranslationSessionState get state;

  /// 创建时间（UTC ms）。
  int get startedAtMs;

  /// 字幕流（含 user / peer / media 三种 role）。**broadcast** 流——晚订阅会丢历史事件，
  /// 用 [latestSubtitleByRole] 拿快照即可补上。
  Stream<TranslateSubtitleEvent> get subtitles;

  /// 错误流。错误**不**自动关闭 session，除非 fatal == true（致命错误后 session
  /// 会自动 stop，state→stopping→stopped/error）。
  Stream<TranslateErrorEvent> get errors;

  /// 状态变化流。
  Stream<TranslationSessionState> get stateStream;

  /// 该 role 最近一次 subtitle 快照；用于 UI 晚加载时重建当前文本状态。
  TranslateSubtitleEvent? latestSubtitleByRole(SubtitleRole role);

  /// 仅订阅指定 role 的字幕。
  Stream<TranslateSubtitleEvent> subtitlesOf(SubtitleRole role) =>
      subtitles.where((e) => e.role == role);

  Future<void> stop();
}

/// 通话翻译会话——双向 + 2 agent + 耳机 RCSP。
abstract class CallTranslationSession extends TranslationSession {
  @override
  TranslationKind get kind => TranslationKind.call;

  /// 两条 leg 的 agent 类型（`ast-translate` / `translate`）。
  String get uplinkAgentType;
  String get downlinkAgentType;

  String get userLanguage;
  String get peerLanguage;
}

/// 面对面翻译会话（占位）。
abstract class FaceToFaceTranslationSession extends TranslationSession {
  @override
  TranslationKind get kind => TranslationKind.faceToFace;
}

/// 音视频翻译会话（占位）。
abstract class AudioTranslationSession extends TranslationSession {
  @override
  TranslationKind get kind => TranslationKind.audio;
}
