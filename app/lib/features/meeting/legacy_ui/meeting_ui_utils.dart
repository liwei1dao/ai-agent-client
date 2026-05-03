import 'package:flutter/material.dart';

/// 1:1 镜像 deepvoice_client_liwei
/// `lib/modules/meeting/utils/meeting_ui_utils.dart`，让源项目 view
/// 代码无须改 import 就能直接复用。
class MeetingUIUtils {
  static Color getBackgroundColor(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF121212) : Colors.grey[50]!;

  static Color getCardColor(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF2D2D2D) : Colors.white;

  static Color getTranslucentWhite(double alpha) =>
      Colors.white.withValues(alpha: alpha);

  static Color getTranslucentBlack(double alpha) =>
      Colors.black.withValues(alpha: alpha);

  static Color getTextColor(bool isDarkMode) =>
      isDarkMode ? Colors.white : Colors.grey[800]!;

  static Color getSecondaryTextColor(bool isDarkMode) =>
      isDarkMode ? Colors.grey[400]! : Colors.grey[600]!;

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

  static Color getButtonColor(bool isDarkMode) =>
      isDarkMode ? const Color(0xFF0066CC) : Colors.blue;

  static Color getColorWithAlpha(Color color, double alpha) =>
      color.withValues(alpha: alpha);

  static Color getDisabledColor(Color color, bool isEnabled) =>
      isEnabled ? color : color.withValues(alpha: 0.5);
}
