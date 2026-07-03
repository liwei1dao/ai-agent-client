import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // Brand tokens — identical across light & dark.
  static const primary = Color(0xFF6C63FF);
  static const primaryDark = Color(0xFF4A42D9);
  static const translateAccent = Color(0xFF0EA5E9);
  static const success = Color(0xFF10B981);
  static const danger = Color(0xFFEF4444);
  static const warning = Color(0xFFF59E0B);

  // Semantic tokens — light palette values kept as static consts for backward
  // compatibility with `const` call sites. Prefer `AppTheme.of(context).xxx`
  // in new code so values flip correctly in dark mode.
  static const primaryLight = Color(0xFFEEF0FF);
  static const bgColor = Color(0xFFF0F2F8);
  static const text1 = Color(0xFF1A1A2E);
  static const text2 = Color(0xFF6B7280);
  static const borderColor = Color(0xFFE5E7EB);

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.light;

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: b)
        .copyWith(surface: c.surface);
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.surface,
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: c.surface,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        foregroundColor: c.text1,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: c.text1,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: c.primaryTint,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: primary);
          }
          return TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: c.text2);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return IconThemeData(color: c.text2, size: 24);
        }),
        elevation: 0,
        height: 68,
      ),
      dividerTheme: DividerThemeData(color: c.border, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.bg,
        hintStyle: TextStyle(color: c.text2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: c.text1),
        bodyMedium: TextStyle(color: c.text1),
        bodySmall: TextStyle(color: c.text2),
        labelLarge: TextStyle(color: c.text1),
        titleMedium: TextStyle(color: c.text1),
        titleSmall: TextStyle(color: c.text1),
      ),
      iconTheme: IconThemeData(color: c.text1),
      listTileTheme: ListTileThemeData(
        iconColor: c.text2,
        textColor: c.text1,
      ),
      extensions: [c],
    );
  }
}

/// Semantic colors that adapt to the current brightness.
/// Access via `AppTheme.of(context)` or `context.appColors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.primaryTint,
    required this.text1,
    required this.text2,
    required this.border,
    required this.logBg,
    required this.logText,
    required this.logMuted,
  });

  /// Page/scaffold background.
  final Color bg;

  /// Card, sheet, app bar background.
  final Color surface;

  /// Secondary surface (hover/pressed tint, subtle fills).
  final Color surfaceAlt;

  /// Tinted primary surface (selected chip, indicator).
  final Color primaryTint;

  /// Primary text.
  final Color text1;

  /// Secondary/muted text.
  final Color text2;

  /// Hairline borders and dividers.
  final Color border;

  /// Log/terminal viewer background.
  final Color logBg;

  /// Log/terminal viewer default text.
  final Color logText;

  /// Log/terminal viewer muted text (empty state).
  final Color logMuted;

  static const light = AppColors(
    bg: Color(0xFFF0F2F8),
    surface: Colors.white,
    surfaceAlt: Color(0xFFF7F8FC),
    primaryTint: Color(0xFFEEF0FF),
    text1: Color(0xFF1A1A2E),
    text2: Color(0xFF6B7280),
    border: Color(0xFFE5E7EB),
    logBg: Color(0xFF1A1A2E),
    logText: Color(0xB3FFFFFF),
    logMuted: Color(0x61FFFFFF),
  );

  static const dark = AppColors(
    bg: Color(0xFF0F1115),
    surface: Color(0xFF1A1D23),
    surfaceAlt: Color(0xFF22262E),
    primaryTint: Color(0xFF2A2548),
    text1: Color(0xFFF1F5F9),
    text2: Color(0xFF94A3B8),
    border: Color(0xFF2A2F37),
    logBg: Color(0xFF0A0B10),
    logText: Color(0xE6FFFFFF),
    logMuted: Color(0x80FFFFFF),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? primaryTint,
    Color? text1,
    Color? text2,
    Color? border,
    Color? logBg,
    Color? logText,
    Color? logMuted,
  }) =>
      AppColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        primaryTint: primaryTint ?? this.primaryTint,
        text1: text1 ?? this.text1,
        text2: text2 ?? this.text2,
        border: border ?? this.border,
        logBg: logBg ?? this.logBg,
        logText: logText ?? this.logText,
        logMuted: logMuted ?? this.logMuted,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      text1: Color.lerp(text1, other.text1, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      border: Color.lerp(border, other.border, t)!,
      logBg: Color.lerp(logBg, other.logBg, t)!,
      logText: Color.lerp(logText, other.logText, t)!,
      logMuted: Color.lerp(logMuted, other.logMuted, t)!,
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get appColors => AppTheme.of(this);
}
