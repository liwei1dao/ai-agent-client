import 'package:flutter/material.dart';

/// 会议模块UI工具类
/// 提供统一的颜色和样式方法，确保UI风格一致性
class MeetingUIUtils {
  /// 获取背景颜色
  static Color getBackgroundColor(bool isDarkMode) {
    return isDarkMode ? const Color(0xFF121212) : Colors.grey[50]!;
  }

  /// 获取卡片背景颜色
  static Color getCardColor(bool isDarkMode) {
    return isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;
  }

  /// 获取半透明白色
  static Color getTranslucentWhite(double alpha) {
    return Colors.white.withValues(alpha: alpha);
  }

  /// 获取半透明黑色
  static Color getTranslucentBlack(double alpha) {
    return Colors.black.withValues(alpha: alpha);
  }

  /// 获取主文本颜色
  static Color getTextColor(bool isDarkMode) {
    return isDarkMode ? Colors.white : Colors.grey[800]!;
  }

  /// 获取次要文本颜色
  static Color getSecondaryTextColor(bool isDarkMode) {
    return isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;
  }

  /// 获取卡片阴影
  static List<BoxShadow> getCardShadow(bool isDarkMode) {
    if (isDarkMode) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.5),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.05),
          blurRadius: 0,
          offset: const Offset(0, -0.5),
        ),
      ];
    }
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.05),
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];
  }

  /// 获取按钮颜色
  static Color getButtonColor(bool isDarkMode) {
    return isDarkMode ? const Color(0xFF0066CC) : Colors.blue;
  }

  /// 获取带透明度的颜色
  static Color getColorWithAlpha(Color color, double alpha) {
    return color.withValues(alpha: alpha);
  }

  /// 获取禁用状态的颜色
  static Color getDisabledColor(Color color, bool isEnabled) {
    return isEnabled ? color : color.withValues(alpha: 0.5);
  }
}
