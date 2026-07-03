import 'package:assistant_server/assistant_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// AI 助理场景容器。
///
/// 架构：编排器全部在 native（`assistant_server` 插件 Android module）；
/// 这里只是 Dart facade —— 通过 `MethodChannelAssistantServer` 转发命令、
/// 订阅 EventChannel 消息/状态/错误事件。
final assistantServerProvider = Provider<AssistantServer>((ref) {
  final server = MethodChannelAssistantServer();
  ref.onDispose(() => server.dispose());
  return server;
});

/// 当前 active 助理会话；UI 据此显示"AI 助理通话中"等。
final activeAssistantSessionProvider =
    StreamProvider<AssistantSession?>((ref) async* {
  final server = ref.watch(assistantServerProvider);
  yield server.activeSession;
  await for (final evt in server.eventStream) {
    if (evt.type == AssistantServerEventType.sessionStarted ||
        evt.type == AssistantServerEventType.sessionStopped) {
      yield server.activeSession;
    }
  }
});
