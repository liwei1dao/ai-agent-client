import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import 'logger.dart';

/// 悬浮窗权限场景
enum OverlayPermissionScene {
  translationFloatingWindow,
  recordingFloatingBar,
}

/// 悬浮窗权限管理工具类 — 不再依赖自定义 MethodChannel，统一走
/// `permission_handler` 的 `Permission.systemAlertWindow`：
///
/// - Android: SYSTEM_ALERT_WINDOW（手动跳到系统授权页）
/// - iOS: 不需要权限，直接返回 true
class OverlayPermissionUtil {
  static bool _isRequestDialogShowing = false;
  static DateTime? _lastRequestDialogAt;
  static const Duration _requestDialogCooldown = Duration(seconds: 20);

  /// 跳转系统悬浮窗权限页面（Android 才有意义）
  static Future<bool> openOverlayPermissionSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.systemAlertWindow.request();
      return status.isGranted;
    } catch (e) {
      Logger.error('跳转悬浮窗权限设置失败: $e');
      return false;
    }
  }

  /// 检查是否有悬浮窗权限
  static Future<bool> hasOverlayPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.systemAlertWindow.status;
      Logger.info('检查悬浮窗权限: $status');
      return status.isGranted;
    } catch (e) {
      Logger.error('检查悬浮窗权限失败: $e');
      return false;
    }
  }

  /// 弹引导对话框 → 跳系统设置 → 回来重新检查权限
  static Future<bool> requestOverlayPermission({
    OverlayPermissionScene scene =
        OverlayPermissionScene.translationFloatingWindow,
  }) async {
    if (!Platform.isAndroid) return true;
    if (await hasOverlayPermission()) return true;

    final desc = switch (scene) {
      OverlayPermissionScene.translationFloatingWindow =>
        '为了在通话或音视频翻译时显示翻译结果，需要悬浮窗权限。这样您就可以在使用其他应用时看到实时翻译。',
      OverlayPermissionScene.recordingFloatingBar =>
        '为了在录音过程中显示录音悬浮条（计时/暂停/继续），需要悬浮窗权限。',
    };

    final now = DateTime.now();
    if (_isRequestDialogShowing) return false;
    final lastAt = _lastRequestDialogAt;
    if (lastAt != null && now.difference(lastAt) < _requestDialogCooldown) {
      return false;
    }

    _isRequestDialogShowing = true;
    _lastRequestDialogAt = now;
    bool? userAgreed;
    try {
      userAgreed = await Get.dialog<bool>(
        AlertDialog(
          title: const Text('需要悬浮窗权限'),
          content: Text(desc),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Get.back(result: true),
              child: const Text('去设置'),
            ),
          ],
        ),
        barrierDismissible: false,
      );
    } finally {
      _isRequestDialogShowing = false;
    }

    if (userAgreed != true) return false;

    try {
      final opened = await openOverlayPermissionSettings();
      if (!opened) return false;
      // 等待用户在系统页面完成操作后回到 App
      await Future.delayed(const Duration(seconds: 1));
      return await hasOverlayPermission();
    } catch (e) {
      Logger.error('请求悬浮窗权限失败: $e');
      return false;
    }
  }
}
