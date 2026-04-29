import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:translate_server/translate_server.dart';

/// 复合翻译场景容器（通话翻译 / 面对面 / 音视频）。
///
/// 架构：编排器全部在 native（`translate_server` 插件 Android module）；
/// 这里只是 Dart facade —— 通过 `MethodChannelTranslateServer` 转发命令、
/// 订阅 EventChannel 字幕/状态/错误事件。
final translateServerProvider = Provider<TranslateServer>((ref) {
  final server = MethodChannelTranslateServer();
  ref.onDispose(() => server.dispose());
  return server;
});

/// 当前 active 复合翻译会话（任一种）；UI 据此显示"通话翻译进行中"等。
final activeTranslationSessionProvider =
    StreamProvider<TranslationSession?>((ref) async* {
  final server = ref.watch(translateServerProvider);
  yield server.activeSession;
  await for (final evt in server.eventStream) {
    if (evt.type == TranslationServerEventType.sessionStarted ||
        evt.type == TranslationServerEventType.sessionStopped) {
      yield server.activeSession;
    }
  }
});
