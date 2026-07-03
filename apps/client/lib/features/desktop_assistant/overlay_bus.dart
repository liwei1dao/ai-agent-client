import 'dart:async';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 主 app 侧的悬浮窗消息总线（单例）。
///
/// `FlutterOverlayWindow.overlayListener` 底层是**单订阅** `StreamController`，
/// 整个 isolate 只能 `.listen` 一次（再次 listen 抛 "Stream has already been
/// listened to"）。但主 app 里有多个消费者需要监听浮窗消息（[App] 处理形象 key /
/// `ready`、[AssistantScreen] 处理会话状态同步）。本总线**只订阅一次**底层流，
/// 再以 broadcast 形式 fan-out，所有消费者订阅 [stream] 即可。
///
/// 仅主 isolate 使用；overlay isolate 有独立的 `overlayListener`，自己单订阅即可。
class OverlayBus {
  OverlayBus._();
  static final OverlayBus instance = OverlayBus._();

  final StreamController<dynamic> _out = StreamController<dynamic>.broadcast();
  bool _wired = false;

  /// 浮窗（overlay isolate）发来的消息广播流；多消费者可同时订阅。
  Stream<dynamic> get stream {
    if (!_wired) {
      _wired = true;
      FlutterOverlayWindow.overlayListener.listen(_out.add);
    }
    return _out.stream;
  }
}
