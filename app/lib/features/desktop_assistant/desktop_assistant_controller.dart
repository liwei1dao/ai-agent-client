import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 桌面悬浮助理的显示控制器（仅 Android）。
///
/// 封装 `flutter_overlay_window` 的权限检查与 show/close。悬浮窗的常驻保活由
/// 插件自带的 OverlayService（前台服务）负责——app 切后台/划掉进程后仍存在。
class DesktopAssistantController {
  const DesktopAssistantController();

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// 悬浮窗权限（SYSTEM_ALERT_WINDOW）是否已授予。
  Future<bool> isPermissionGranted() async {
    if (!_supported) return false;
    return FlutterOverlayWindow.isPermissionGranted();
  }

  /// 跳系统设置请求悬浮窗权限，返回授予结果。
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    final r = await FlutterOverlayWindow.requestPermission();
    return r ?? false;
  }

  /// 显示悬浮助理（幂等）。无权限或非 Android 时静默跳过。
  Future<void> enable() async {
    if (!_supported) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) return;
    if (await FlutterOverlayWindow.isActive()) return;
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 150,
        width: 150,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        // none：停在初始/拖动位置，不自动吸附到屏幕边缘外（避免只露半个圆）。
        positionGravity: PositionGravity.none,
        overlayTitle: '桌面助理',
        overlayContent: '点击与 AI 助理对话',
        visibility: NotificationVisibility.visibilityPublic,
      );
    } catch (_) {
      // 权限被运行时撤销等情况下 showOverlay 会抛，吞掉避免影响主流程。
    }
  }

  /// 关闭悬浮助理（幂等）。
  Future<void> disable() async {
    if (!_supported) return;
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }
}
