import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
// import 'package:app_settings/app_settings.dart';
// 使用 permission_handler.openAppSettings 代替
import 'logger.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// 权限请求工具类
///
/// 提供统一的权限请求流程处理：
/// 1. 初始权限状态检查
/// 2. 权限解释横幅显示（悬浮在UI顶部的解释性UI）
/// 3. 权限请求执行
/// 4. 永久拒绝后的设置引导
/// 5. 智能拒绝次数统计和熔断机制
///
/// 使用单例模式：`PermissionUtil.instance`

class PermissionUtil {
  /// 单例实例
  static final PermissionUtil instance = PermissionUtil._();

  /// 私有构造函数
  PermissionUtil._();

  /// 引入 get_storage 用于持久化权限拒绝次数
  final _storage = GetStorage();

  /// 权限拒绝次数阈值（达到此次数后视为永久拒绝）
  static const int _denialThreshold = 5;

  /// 获取权限拒绝次数的存储键
  String _getDenialCountKey(Permission permission) {
    return 'permission_denial_count_${permission.toString()}';
  }

  /// 重置指定权限的拒绝次数
  ///
  /// 在某些场景下可能需要手动重置拒绝次数，比如用户主动要求重新请求权限
  Future<void> resetDenialCount(Permission permissionType) async {
    await _storage.remove(_getDenialCountKey(permissionType));
    Logger.d('PermissionUtil', '已重置 ${permissionType.toString()} 的拒绝次数');
  }

  /// 获取指定权限的拒绝次数
  int getDenialCount(Permission permissionType) {
    return _storage.read<int>(_getDenialCountKey(permissionType)) ?? 0;
  }

  /// 请求指定权限
  ///
  /// 参数：
  /// [context]: BuildContext，用于UI显示和导航
  /// [permissionType]: 要请求的权限类型(Permission.microphone等)
  /// [permissionName]: 权限的用户友好名称（如"麦克风"、"定位"）
  /// [explanationText]: 权限用途的详细解释文本
  /// [permanentDenialText]: 永久拒绝后引导用户去设置的文案
  /// [settingsButtonText]: "去设置"按钮的文本（可选，默认"前往设置"）
  /// [cancelButtonText]: "取消"按钮的文本（可选，默认"取消"）
  ///
  /// 返回值：`Future<bool>` 权限是否最终授予
  Future<bool> requestPermission({
    required Permission permissionType,
    required String permissionName,
    required String explanationText,
    required String permanentDenialText,
    String? settingsButtonText,
    String? cancelButtonText,
  }) async {
    // 使用翻译键作为默认值
    final String finalSettingsButtonText =
        settingsButtonText ?? 'goToSettings'.tr;
    final String finalCancelButtonText = cancelButtonText ?? 'cancel'.tr;
    bool isOverlayShown = false;

    try {
      // 检查初始权限状态
      PermissionStatus status = await permissionType.status;
      Logger.d('PermissionUtil', '初始权限状态 [$permissionName]: $status');

      // 1. <--- 已授权处理 --->（包括授予状态和临时通知权限）
      if (status.isGranted) {
        Logger.i('PermissionUtil', '$permissionName 权限已授予或临时授予');
        // 如果已经授权，清零之前的拒绝记录，以防用户在设置中开启后又关闭
        await resetDenialCount(permissionType); // 清零拒绝记录
        return true;
      }

      // 2. <--- 熔断机制：检查我们自己的拒绝次数 --->
      final denialCount = getDenialCount(permissionType);
      Logger.d('PermissionUtil', '$permissionName 当前拒绝次数: $denialCount');
      // 如果拒绝次数达到阈值或系统返回了 permanentlyDenied，直接视为永久拒绝
      if (status.isPermanentlyDenied || denialCount >= _denialThreshold) {
        Logger.w('PermissionUtil',
            '$permissionName 已被系统永久拒绝或自定义计数达到阈值($denialCount)，触发设置引导');
        await _showPermanentDenialDialog(
          permissionName: permissionName,
          permanentDenialText: permanentDenialText,
          settingsButtonText: finalSettingsButtonText,
          cancelButtonText: finalCancelButtonText,
        );
        // 引导用户后，返回false，因为权限当前未被授予
        return false;
      }

      // 3. <--- 发起正常的权限请求 (此时 status 必然是 denied 或受限) --->
      _showExplanationOverlay(
        permissionName: permissionName,
        explanationText: explanationText,
      );
      isOverlayShown = true;

      final PermissionStatus newStatus = await permissionType.request();
      Logger.d('PermissionUtil', '请求后 $permissionName 的新权限状态: $newStatus');

      _hideExplanationOverlay();
      isOverlayShown = false;

      // 4. <--- 处理请求后的结果 --->
      if (newStatus.isGranted) {
        Logger.i('PermissionUtil', '$permissionName 权限在请求后被授予');
        await resetDenialCount(permissionType); // 授权成功，清零
        return true;
      }

      if (newStatus.isPermanentlyDenied) {
        Logger.w('PermissionUtil', '$permissionName 权限在请求后被系统永久拒绝');
        await _showPermanentDenialDialog(
          permissionName: permissionName,
          permanentDenialText: permanentDenialText,
          settingsButtonText: finalSettingsButtonText,
          cancelButtonText: finalCancelButtonText,
        );
        return false;
      }

      if (newStatus.isDenied) {
        Logger.w('PermissionUtil', '$permissionName 权限被拒绝，增加拒绝计数');
        await _storage.write(
            _getDenialCountKey(permissionType), denialCount + 1);
      }

      // 所有未授权的情况最终都返回 false
      return false;
    } catch (e, stackTrace) {
      Logger.e('PermissionUtil', '请求 $permissionName 权限失败: $e', e, stackTrace);
      if (isOverlayShown) {
        _hideExplanationOverlay();
      }
      return false;
    } finally {
      // 确保在异常或正常流程结束时都隐藏解释横幅
      if (isOverlayShown) {
        _hideExplanationOverlay();
        Logger.d('PermissionUtil', '在 finally 块中关闭权限说明弹窗');
      }
    }
  }

  /// 显示权限解释横幅（漂浮在UI顶部的说明性UI）
  ///
  /// 在请求权限前显示，向用户解释为什么需要这个权限
  void _showExplanationOverlay({
    required String permissionName,
    required String explanationText,
  }) {
    // 获取当前主题模式
    final context = Get.context;
    final isDarkMode = context != null
        ? Theme.of(context).brightness == Brightness.dark
        : false;

    Get.dialog(
      Stack(
        children: [
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: Material(
              borderRadius: BorderRadius.circular(12),
              elevation: 8,
              color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[300],
              shadowColor: Colors.black.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'permissionUtilNeed'.tr +
                          permissionName +
                          'permissionUtilPermission'.tr,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      explanationText,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      // 防止用户通过点击背景关闭解释横幅
      //barrierDismissible: false,
    );
  }

  /// 隐藏权限解释横幅
  void _hideExplanationOverlay() {
    if (Get.isDialogOpen ?? false) {
      Get.back();
      Logger.d('PermissionUtil', '权限说明叠加层已移除');
    }
  }

  /// 显示永久拒绝后的设置引导对话框
  ///
  /// 在权限被永久拒绝时调用，提示用户前往设置手动开启权限
  Future<void> _showPermanentDenialDialog({
    required String permissionName,
    required String permanentDenialText,
    required String settingsButtonText,
    required String cancelButtonText,
  }) async {
    Logger.i('PermissionUtil', '显示永久拒绝对话框 ($permissionName)');

    // 获取当前主题模式
    final context = Get.context;
    final isDarkMode = context != null
        ? Theme.of(context).brightness == Brightness.dark
        : false;

    bool? userChoice = await Get.dialog(
      AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
        title: Text(
          'permissionUtilNeed'.tr +
              permissionName +
              'permissionUtilPermission'.tr,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          permanentDenialText,
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Logger.d('PermissionUtil', '用户取消设置 ($permissionName)');
              Get.back(result: false);
            },
            style: TextButton.styleFrom(
              foregroundColor: isDarkMode ? Colors.white70 : Colors.grey[700],
            ),
            child: Text(cancelButtonText),
          ),
          ElevatedButton(
            onPressed: () {
              Logger.d('PermissionUtil', '用户同意前往设置 ($permissionName)');
              Get.back(result: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  isDarkMode ? const Color(0xFF0066CC) : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text(settingsButtonText),
          ),
        ],
      ),
      barrierDismissible: false,
    );

    if (userChoice == true) {
      openAppSettings();
    }
  }

  // 移除了多余的_showRestrictedPermissionDialog，因为永久拒绝流程已能覆盖
}
