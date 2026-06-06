import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' show RiveAnimation;

import '../desktop_assistant_avatars.dart';

/// 桌面悬浮助理形象，跑在 `flutter_overlay_window` 的**独立 overlay isolate**。
///
/// 该 isolate 由独立 FlutterEngine 运行、读不到 SharedPreferences，所以当前形象
/// 由主 app 通过 `FlutterOverlayWindow.shareData(avatarKey)` 推送，这里用
/// [desktopAssistantAvatarByKey] 解析成 Lottie 资源。点击拉起 app 走
/// [_nativeChannel]（handler 由 MainActivity 注册到 cached overlay engine）。
class DesktopAssistantOverlay extends StatefulWidget {
  const DesktopAssistantOverlay({super.key});

  @override
  State<DesktopAssistantOverlay> createState() =>
      _DesktopAssistantOverlayState();
}

class _DesktopAssistantOverlayState extends State<DesktopAssistantOverlay> {
  static const _nativeChannel =
      MethodChannel('desktop_assistant/overlay_native');

  String _avatarKey = kDesktopAssistantAvatars.first.key;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    // 主 app 推送形象 key；收到即切换。
    _sub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String && event.isNotEmpty && mounted) {
        setState(() => _avatarKey = event);
      }
    });
    // 通知主 app overlay 已就绪 → 主 app 回推当前形象。
    FlutterOverlayWindow.shareData('ready');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onTap() async {
    try {
      await _nativeChannel.invokeMethod('launchApp');
    } catch (_) {
      // overlay engine 上的 channel 尚未就绪时静默忽略。
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = desktopAssistantAvatarByKey(_avatarKey);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: GestureDetector(
            onTap: _onTap,
            child: Container(
              width: 108,
              height: 108,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  // 品牌色光晕，让形象在任何壁纸上都醒目。
                  BoxShadow(
                      color: Color(0x556C5CE7),
                      blurRadius: 20,
                      spreadRadius: 1),
                  BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: ClipOval(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: avatar.isRive
                      ? RiveAnimation.asset(avatar.asset, fit: BoxFit.contain)
                      : Lottie.asset(
                          avatar.asset,
                          fit: BoxFit.contain,
                          repeat: true,
                          // 资源加载失败时给个可见兜底，避免空白圆。
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.smart_toy,
                              size: 48,
                              color: Color(0xFF6C5CE7)),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
