import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:agents_server/agents_server.dart';

/// 桌面悬浮助理的显示控制器（仅 Android）。
///
/// 封装 `flutter_overlay_window` 的权限检查与 show/close。浮窗的**常驻保活**挂在
/// agents_server 的宿主前台服务上：显示时 acquireRuntime('overlay') 登记一个保活引用，
/// 使进程在划掉 app 后仍存活（浮窗 + AI 一起活）；隐藏时 releaseRuntime 注销。
/// 注意：flutter_overlay_window 自带的 OverlayService 与主 app 同进程，单靠它在
/// 国产 ROM 上划掉即被杀，故改由宿主服务统一保活。
class DesktopAssistantController {
  const DesktopAssistantController();

  /// 运行时保活引用 tag，对应原生 `AgentsServerService.REF_OVERLAY`。
  static const _overlayRefTag = 'overlay';

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
    // 先登记保活引用，让宿主前台服务把进程钉住（划掉 app 后浮窗仍在）。幂等。
    await AgentsServerBridge().acquireRuntime(_overlayRefTag);
    if (await FlutterOverlayWindow.isActive()) return;
    try {
      await FlutterOverlayWindow.showOverlay(
        height: 150,
        width: 150,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        // auto：松手后自动吸附到最近的左/右屏幕边缘并完整可见（球宽 < window 宽，
        // 贴边后仍整圆露出），避免 none 模式下被拖到屏幕外卡死抓不回来。
        positionGravity: PositionGravity.auto,
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
    // 注销保活引用；若已无其它持有者（活跃 agent 等），宿主服务自行退前台并停止。
    await AgentsServerBridge().releaseRuntime(_overlayRefTag);
  }
}
