import 'dart:async';

import 'translate_event.dart';
import 'translate_request.dart';
import 'translate_session.dart';

/// 复合翻译场景容器。
///
/// 三种业务**互斥**：[activeSession] 至多一个；新 start 调用会先 stop 旧 session。
/// 通话翻译当前实现完整闭环；面对面 / 音视频 留接口位，调用现版本会抛
/// `translate.not_implemented`。
abstract class TranslateServer {
  TranslationSession? get activeSession;
  TranslationKind? get activeKind;

  /// 容器级事件流（session 启停、容器错误等）。
  Stream<TranslationServerEvent> get eventStream;

  /// 通话翻译：双向 + 2 agent + 耳机 RCSP 翻译通道。
  /// 失败抛 [TranslateException]（参见 [TranslateErrorCode]）。
  Future<CallTranslationSession> startCallTranslation(
    CallTranslationRequest request,
  );

  /// 面对面翻译（占位，待硬件方案确认后实现）。
  Future<FaceToFaceTranslationSession> startFaceToFaceTranslation(
    FaceToFaceTranslationRequest request,
  );

  /// 音视频翻译（占位，待系统媒体回采实现后落地）。
  Future<AudioTranslationSession> startAudioTranslation(
    AudioTranslationRequest request,
  );

  Future<void> dispose();
}
