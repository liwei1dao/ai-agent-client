import 'dart:async';

import 'assistant_event.dart';
import 'assistant_request.dart';
import 'assistant_session.dart';

/// AI 助理场景容器。
///
/// 同一时刻**至多一个** [activeSession]；新 start 调用时若已有 active 会抛
/// `assistant.session_busy`，调用方应先 stop 旧 session 再启动。
abstract class AssistantServer {
  AssistantSession? get activeSession;

  /// 容器级事件流（session 启停、容器错误等）。
  Stream<AssistantServerEvent> get eventStream;

  /// 启动 AI 助理会话：单 chat agent + 耳机 RCSP PCM 通道。
  /// 失败抛 [AssistantException]（参见 [AssistantErrorCode]）。
  Future<AssistantSession> startAssistant(AssistantRequest request);

  Future<void> dispose();
}
