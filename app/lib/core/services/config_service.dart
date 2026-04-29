import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart' as env;

/// 杰理设备链接方式偏好（仅 Android）。
///
/// 与 `BluetoothConstant.PROTOCOL_TYPE_*` 对应：
/// - [auto]：不下发 connectWay，沿用扫描结果（设备广播声明的偏好）；
/// - [ble]：强制 BLE（PROTOCOL_TYPE_BLE = 0）；
/// - [spp]：强制 SPP/EDR（PROTOCOL_TYPE_SPP = 1）。
enum JieliConnectWay {
  auto,
  ble,
  spp;

  /// 对应的 SDK 协议类型整型；[auto] 返回 null（不下发）。
  int? get protocolTypeValue => switch (this) {
        JieliConnectWay.auto => null,
        JieliConnectWay.ble => 0,
        JieliConnectWay.spp => 1,
      };

  String get persistKey => name; // 'auto' / 'ble' / 'spp'

  static JieliConnectWay fromKey(String? key) => switch (key) {
        'ble' => JieliConnectWay.ble,
        'spp' => JieliConnectWay.spp,
        _ => JieliConnectWay.auto,
      };
}

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
    this.deviceVendor,
    this.jieliConnectWay = JieliConnectWay.auto,
    this.defaultChatAgentId,
    this.defaultTranslateAgentId,
    this.defaultCallUplinkAgentId,
    this.defaultCallDownlinkAgentId,
    this.defaultCallUserLanguage,
    this.defaultCallPeerLanguage,
    this.lastDeviceId,
    this.lastDeviceName,
  });

  final ThemeMode themeMode;
  final int historyMessageCount;
  final PolychatConfig polychat;
  final AudioOutputMode audioOutputMode;

  /// 当前选择的设备厂商 key（与 DevicePlugin.vendorKey 一致）；未选为 null。
  final String? deviceVendor;

  /// 杰理设备链接方式偏好（仅在 [deviceVendor] == 'jieli' 时生效）。
  final JieliConnectWay jieliConnectWay;

  /// 设备唤醒后默认启动的聊天 agent id。
  final String? defaultChatAgentId;

  /// 设备翻译键默认启动的翻译 agent id。
  final String? defaultTranslateAgentId;

  /// 通话翻译默认 agent（uplink = 用户说→对方听）。
  final String? defaultCallUplinkAgentId;

  /// 通话翻译默认 agent（downlink = 对方说→用户听）。
  final String? defaultCallDownlinkAgentId;

  /// 通话翻译默认用户侧语言（IETF BCP-47 / ISO-639）。
  final String? defaultCallUserLanguage;

  /// 通话翻译默认对方侧语言。
  final String? defaultCallPeerLanguage;

  /// 上次成功连接过的设备 deviceId（用于自动重连）。
  final String? lastDeviceId;

  /// 上次成功连接过的设备显示名（重连时回填到 connect options.extra.name）。
  final String? lastDeviceName;

  AppConfig copyWith({
    ThemeMode? themeMode,
    int? historyMessageCount,
    PolychatConfig? polychat,
    AudioOutputMode? audioOutputMode,
    Object? deviceVendor = _unset,
    JieliConnectWay? jieliConnectWay,
    Object? defaultChatAgentId = _unset,
    Object? defaultTranslateAgentId = _unset,
    Object? defaultCallUplinkAgentId = _unset,
    Object? defaultCallDownlinkAgentId = _unset,
    Object? defaultCallUserLanguage = _unset,
    Object? defaultCallPeerLanguage = _unset,
    Object? lastDeviceId = _unset,
    Object? lastDeviceName = _unset,
  }) =>
      AppConfig(
        themeMode: themeMode ?? this.themeMode,
        historyMessageCount: historyMessageCount ?? this.historyMessageCount,
        polychat: polychat ?? this.polychat,
        audioOutputMode: audioOutputMode ?? this.audioOutputMode,
        deviceVendor: identical(deviceVendor, _unset)
            ? this.deviceVendor
            : deviceVendor as String?,
        jieliConnectWay: jieliConnectWay ?? this.jieliConnectWay,
        defaultChatAgentId: identical(defaultChatAgentId, _unset)
            ? this.defaultChatAgentId
            : defaultChatAgentId as String?,
        defaultTranslateAgentId: identical(defaultTranslateAgentId, _unset)
            ? this.defaultTranslateAgentId
            : defaultTranslateAgentId as String?,
        defaultCallUplinkAgentId: identical(defaultCallUplinkAgentId, _unset)
            ? this.defaultCallUplinkAgentId
            : defaultCallUplinkAgentId as String?,
        defaultCallDownlinkAgentId: identical(defaultCallDownlinkAgentId, _unset)
            ? this.defaultCallDownlinkAgentId
            : defaultCallDownlinkAgentId as String?,
        defaultCallUserLanguage: identical(defaultCallUserLanguage, _unset)
            ? this.defaultCallUserLanguage
            : defaultCallUserLanguage as String?,
        defaultCallPeerLanguage: identical(defaultCallPeerLanguage, _unset)
            ? this.defaultCallPeerLanguage
            : defaultCallPeerLanguage as String?,
        lastDeviceId: identical(lastDeviceId, _unset)
            ? this.lastDeviceId
            : lastDeviceId as String?,
        lastDeviceName: identical(lastDeviceName, _unset)
            ? this.lastDeviceName
            : lastDeviceName as String?,
      );
}

const Object _unset = Object();

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

    // PolyChat 默认值来自 .env，SharedPreferences 有值则覆盖。
    final envCfg = env.AppConfig.instance;
    state = AppConfig(
      themeMode: themeMode,
      historyMessageCount: prefs.getInt('history_message_count') ?? 20,
      polychat: PolychatConfig(
        baseUrl: prefs.getString('polychat_base_url') ??
            prefs.getString('voitrans_base_url') ??
            envCfg.polychatBaseUrl,
        appId: prefs.getString('polychat_app_id') ??
            prefs.getString('voitrans_app_id') ??
            envCfg.polychatAppId,
        appSecret: prefs.getString('polychat_app_secret') ??
            prefs.getString('voitrans_app_secret') ??
            envCfg.polychatAppSecret,
      ),
      audioOutputMode: audioOutputMode,
      deviceVendor: prefs.getString('device_vendor'),
      jieliConnectWay:
          JieliConnectWay.fromKey(prefs.getString('jieli_connect_way')),
      defaultChatAgentId: prefs.getString('default_chat_agent_id'),
      defaultTranslateAgentId: prefs.getString('default_translate_agent_id'),
      defaultCallUplinkAgentId: prefs.getString('default_call_uplink_agent_id'),
      defaultCallDownlinkAgentId:
          prefs.getString('default_call_downlink_agent_id'),
      defaultCallUserLanguage: prefs.getString('default_call_user_language'),
      defaultCallPeerLanguage: prefs.getString('default_call_peer_language'),
      lastDeviceId: prefs.getString('last_device_id'),
      lastDeviceName: prefs.getString('last_device_name'),
    );
  }

  Future<void> setLastDevice({String? id, String? name}) async {
    state = state.copyWith(lastDeviceId: id, lastDeviceName: name);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('last_device_id');
    } else {
      await prefs.setString('last_device_id', id);
    }
    if (name == null) {
      await prefs.remove('last_device_name');
    } else {
      await prefs.setString('last_device_name', name);
    }
  }

  Future<void> setDeviceVendor(String? vendor) async {
    state = state.copyWith(deviceVendor: vendor);
    final prefs = await SharedPreferences.getInstance();
    if (vendor == null) {
      await prefs.remove('device_vendor');
    } else {
      await prefs.setString('device_vendor', vendor);
    }
  }

  Future<void> setJieliConnectWay(JieliConnectWay way) async {
    state = state.copyWith(jieliConnectWay: way);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jieli_connect_way', way.persistKey);
  }

  Future<void> setDefaultChatAgentId(String? id) async {
    state = state.copyWith(defaultChatAgentId: id);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('default_chat_agent_id');
    } else {
      await prefs.setString('default_chat_agent_id', id);
    }
  }

  Future<void> setDefaultTranslateAgentId(String? id) async {
    state = state.copyWith(defaultTranslateAgentId: id);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove('default_translate_agent_id');
    } else {
      await prefs.setString('default_translate_agent_id', id);
    }
  }

  Future<void> setDefaultCallUplinkAgentId(String? id) =>
      _setOptionalString('default_call_uplink_agent_id', id, (v) =>
          state.copyWith(defaultCallUplinkAgentId: v));

  Future<void> setDefaultCallDownlinkAgentId(String? id) =>
      _setOptionalString('default_call_downlink_agent_id', id, (v) =>
          state.copyWith(defaultCallDownlinkAgentId: v));

  Future<void> setDefaultCallUserLanguage(String? lang) =>
      _setOptionalString('default_call_user_language', lang, (v) =>
          state.copyWith(defaultCallUserLanguage: v));

  Future<void> setDefaultCallPeerLanguage(String? lang) =>
      _setOptionalString('default_call_peer_language', lang, (v) =>
          state.copyWith(defaultCallPeerLanguage: v));

  Future<void> _setOptionalString(
    String key,
    String? value,
    AppConfig Function(String?) apply,
  ) async {
    state = apply(value);
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
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
