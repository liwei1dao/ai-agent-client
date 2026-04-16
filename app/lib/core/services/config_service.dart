import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 音频播报输出模式
enum AudioOutputMode {
  /// 听筒
  earpiece,

  /// 扬声器
  speaker,

  /// 自动（有耳机走系统路由，无耳机走扬声器）
  auto,
}

/// PolyChat 平台连接参数
class PolychatConfig {
  const PolychatConfig({
    this.baseUrl = '',
    this.appId = '',
    this.appSecret = '',
  });

  final String baseUrl;
  final String appId;
  final String appSecret;

  bool get isConfigured =>
      baseUrl.isNotEmpty && appId.isNotEmpty && appSecret.isNotEmpty;
}

/// 全局配置状态
class AppConfig {
  const AppConfig({
    this.themeMode = ThemeMode.light,
    this.historyMessageCount = 20,
    this.polychat = const PolychatConfig(),
    this.audioOutputMode = AudioOutputMode.auto,
  });

  final ThemeMode themeMode;
  final int historyMessageCount;
  final PolychatConfig polychat;
  final AudioOutputMode audioOutputMode;

  AppConfig copyWith({
    ThemeMode? themeMode,
    int? historyMessageCount,
    PolychatConfig? polychat,
    AudioOutputMode? audioOutputMode,
  }) =>
      AppConfig(
        themeMode: themeMode ?? this.themeMode,
        historyMessageCount: historyMessageCount ?? this.historyMessageCount,
        polychat: polychat ?? this.polychat,
        audioOutputMode: audioOutputMode ?? this.audioOutputMode,
      );
}

final configServiceProvider =
    StateNotifierProvider<ConfigService, AppConfig>((ref) {
  return ConfigService();
});

class ConfigService extends StateNotifier<AppConfig> {
  ConfigService() : super(const AppConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? ThemeMode.light.index;
    final themeMode = (themeIndex >= 0 && themeIndex < ThemeMode.values.length)
        ? ThemeMode.values[themeIndex]
        : ThemeMode.light;

    final audioModeIndex = prefs.getInt('audio_output_mode') ?? AudioOutputMode.auto.index;
    final audioOutputMode = audioModeIndex < AudioOutputMode.values.length
        ? AudioOutputMode.values[audioModeIndex]
        : AudioOutputMode.auto;

    state = AppConfig(
      themeMode: themeMode,
      historyMessageCount: prefs.getInt('history_message_count') ?? 20,
      polychat: PolychatConfig(
        baseUrl: prefs.getString('polychat_base_url') ?? prefs.getString('voitrans_base_url') ?? '',
        appId: prefs.getString('polychat_app_id') ?? prefs.getString('voitrans_app_id') ?? '',
        appSecret: prefs.getString('polychat_app_secret') ?? prefs.getString('voitrans_app_secret') ?? '',
      ),
      audioOutputMode: audioOutputMode,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setHistoryMessageCount(int count) async {
    state = state.copyWith(historyMessageCount: count);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('history_message_count', count);
  }

  Future<void> setPolychatConfig(PolychatConfig config) async {
    state = state.copyWith(polychat: config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('polychat_base_url', config.baseUrl);
    await prefs.setString('polychat_app_id', config.appId);
    await prefs.setString('polychat_app_secret', config.appSecret);
  }

  Future<void> setAudioOutputMode(AudioOutputMode mode) async {
    state = state.copyWith(audioOutputMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('audio_output_mode', mode.index);
  }
}
