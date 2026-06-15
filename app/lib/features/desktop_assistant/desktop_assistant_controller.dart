import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:agents_server/agents_server.dart';

import 'overlay/overlay_assistant_session.dart';

/// 桌面悬浮助理的显示控制器（仅 Android）。
///
/// 封装 `flutter_overlay_window` 的权限检查与 show/close。浮窗的**常驻保活**由
/// flutter_overlay_window 自带的 OverlayService（specialUse 前台服务）负责——划掉
/// app 后进程仍由它钉住，浮窗常驻（国产 ROM 需配合自启动/电池白名单，见
/// [openKeepAliveSettings]）。
///
/// ⚠️ 历史教训（2026-06-15 回归修复）：曾额外用 agents_server 的
/// acquireRuntime('overlay') 再起一个前台服务想"加强"保活，反而触发
/// startForegroundService 的「5s 内必须 startForeground」契约——一旦该服务
/// startForeground 失败，系统连同 OverlayService 一起把**整个进程**杀掉，浮窗反而
/// 消失。故移除该引用，回归纯 OverlayService 保活。桌宠「对话中」的后台存活由
/// createAgent 自动挂的 microphone 前台服务负责，与浮窗保活相互独立。
class DesktopAssistantController {
  const DesktopAssistantController();

  /// 与 MainActivity 同名的 channel（跳系统「自启动 / 后台运行」设置页用）。
  static const _navChannel = MethodChannel('desktop_assistant/nav');

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  /// 悬浮窗边长（**物理像素**）。
  ///
  /// flutter_overlay_window 0.5.0 创建窗口时把 width/height 直接塞进
  /// WindowManager.LayoutParams（物理像素），只有 resizeOverlay 才做 dp 转换，
  /// 所以这里要自己按屏宽换算，否则高分屏上浮窗会缩成小按钮。
  /// 取屏宽 38%（约 130dp 的"桌宠"体量），夹在 340~600px 之间防极端屏幕。
  static int _windowSizePx() {
    final view = ui.PlatformDispatcher.instance.implicitView;
    final screenW = view?.physicalSize.width ?? 0;
    final base = screenW > 0 ? screenW * 0.38 : 420.0;
    return base.round().clamp(340, 600).toInt();
  }

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
    final sizePx = _windowSizePx();
    try {
      await FlutterOverlayWindow.showOverlay(
        height: sizePx,
        width: sizePx,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        // auto：松手后自动吸附到最近的左/右屏幕边缘并完整可见（角色宽 < window
        // 宽，贴边后角色仍完整露出），避免 none 模式下被拖到屏幕外卡死抓不回来。
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
    // 桌宠可能正处于对话中：closeOverlay 直接销毁 overlay engine，不会走它的
    // dispose，这里按固定 sessionId 防御性收尾，避免 agent 泄漏在前台服务里。
    // stopAgent 已含 release（native deleteAgent==stopAgent），单次即可。
    try {
      await AgentsServerBridge()
          .stopAgent(OverlayAssistantSession.sessionId);
    } catch (_) {}
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  /// 引导用户开启后台保活白名单（国产 ROM 划掉 app 后浮窗仍在的关键）。
  /// 先请求电池优化白名单（标准 API），再跳厂商「自启动」管理页（native 适配，
  /// 失败回退应用详情页）。任一步失败都静默吞掉，不影响其余步骤。
  Future<void> openKeepAliveSettings() async {
    if (!_supported) return;
    try {
      if (!await Permission.ignoreBatteryOptimizations.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {}
    try {
      await _navChannel.invokeMethod('openKeepAliveSettings');
    } catch (_) {}
  }
}
