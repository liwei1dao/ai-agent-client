import 'package:flutter/foundation.dart';

import 'device_info.dart';

// ---------------------------------------------------------------------------
// DevicePlugin 侧（厂商插件 → 容器）
// ---------------------------------------------------------------------------

/// 厂商插件向容器派发的事件类型。
///
/// 命名约定与 §2.1 / §5.x 一致，状态变更以"已发生"语义命名。
enum DevicePluginEventType {
  pluginReady,
  pluginDisposed,
  bluetoothStateChanged,
  scanStarted,
  scanStopped,
  deviceDiscovered,
  bondStateChanged,
  connectionStateChanged,
  deviceInfoUpdated,
  wakeTriggered,
  customEvent,
  error,
}

@immutable
class DevicePluginEvent {
  const DevicePluginEvent({
    required this.type,
    this.deviceId,
    this.discovered,
    this.connectionState,
    this.deviceInfo,
    this.bluetoothEnabled,
    this.bondState,
    this.wake,
    this.customKey,
    this.customPayload,
    this.errorCode,
    this.errorMessage,
  });

  final DevicePluginEventType type;
  final String? deviceId;

  // deviceDiscovered
  final DiscoveredDevice? discovered;

  // connectionStateChanged
  final DeviceConnectionState? connectionState;

  // deviceInfoUpdated
  final DeviceInfo? deviceInfo;

  // bluetoothStateChanged
  final bool? bluetoothEnabled;

  // bondStateChanged：'none' | 'bonding' | 'bonded'
  final String? bondState;

  // wakeTriggered
  final DeviceWakeEvent? wake;

  // customEvent：厂商私有事件，业务层一般忽略
  final String? customKey;
  final Map<String, Object?>? customPayload;

  // error
  final String? errorCode;
  final String? errorMessage;
}

// ---------------------------------------------------------------------------
// DeviceSession 侧（连接后，按 deviceId 维度的事件）
// ---------------------------------------------------------------------------

/// 单设备会话事件。
enum DeviceSessionEventType {
  /// 连接状态变化（connecting → linkConnected → ready / disconnecting / disconnected）
  connectionStateChanged,

  /// 设备信息更新（电量、固件版本…）
  deviceInfoUpdated,

  /// 通用语义事件——按键、佩戴、ANC 切换等。
  /// 由厂商插件把 RCSP / GATT 通知翻译为统一的 [DeviceFeatureEvent.key]。
  feature,

  /// RSSI 周期上报
  rssiUpdated,

  /// 厂商私有原始通知（不要在业务层直接消费）
  raw,

  error,
}

@immutable
class DeviceSessionEvent {
  const DeviceSessionEvent({
    required this.type,
    required this.deviceId,
    this.connectionState,
    this.deviceInfo,
    this.feature,
    this.rssi,
    this.raw,
    this.errorCode,
    this.errorMessage,
  });

  final DeviceSessionEventType type;
  final String deviceId;

  final DeviceConnectionState? connectionState;
  final DeviceInfo? deviceInfo;
  final DeviceFeatureEvent? feature;
  final int? rssi;
  final Map<String, Object?>? raw;

  final String? errorCode;
  final String? errorMessage;
}

/// 通用语义事件。`key` 命名空间：
/// - `common.<name>`：跨厂商通用（`battery`, `wear.on`, `wear.off`,
///   `key.click`, `key.double_click`, `key.long_press`, `anc.changed`...)
/// - `<vendor>.<name>`：厂商私有（业务层若要消费需注明强耦合）
@immutable
class DeviceFeatureEvent {
  const DeviceFeatureEvent({required this.key, this.data = const {}});
  final String key;
  final Map<String, Object?> data;
}

// ---------------------------------------------------------------------------
// 设备主动唤醒（→ DeviceManager.agentTriggers）
// ---------------------------------------------------------------------------

/// 触发原因：决定路由器启动哪个 agent。
enum WakeReason {
  /// 长按 / 单击 PTT 键
  ptt,

  /// 设备端语音唤醒（"小艺小艺"等）
  voiceWake,

  /// 翻译键
  translateKey,

  /// 挂断键 / 取消
  hangup,
}

@immutable
class DeviceWakeEvent {
  const DeviceWakeEvent({
    required this.deviceId,
    required this.reason,
    this.payload = const {},
  });

  final String deviceId;
  final WakeReason reason;

  /// 厂商扩展字段（按下时长、是否长按等）
  final Map<String, Object?> payload;
}

// ---------------------------------------------------------------------------
// DeviceManager 侧（容器对外的聚合事件）
// ---------------------------------------------------------------------------

enum DeviceManagerEventType {
  managerReady,
  vendorChanged,
  bluetoothStateChanged,
  scanStarted,
  scanStopped,
  deviceDiscovered,
  activeSessionChanged,
  sessionEvent,

  /// 整个 active session 的最新完整快照（任何字段变化都重发）。Flutter 侧
  /// 直接 mirror，没有自己的 state diff 逻辑——一切以最近一次快照为准。
  snapshotUpdated,
  error,
}

@immutable
class DeviceManagerEvent {
  const DeviceManagerEvent({
    required this.type,
    this.vendorKey,
    this.bluetoothEnabled,
    this.discovered,
    this.activeDeviceId,
    this.sessionEvent,
    this.sessionSnapshot,
    this.errorCode,
    this.errorMessage,
  });

  final DeviceManagerEventType type;

  final String? vendorKey;
  final bool? bluetoothEnabled;
  final DiscoveredDevice? discovered;

  /// activeSessionChanged 时为新 active deviceId；断开时为 null
  final String? activeDeviceId;

  /// sessionEvent 时携带，包含具体语义事件
  final DeviceSessionEvent? sessionEvent;

  /// 整个 active session 的最新完整快照——native 在 snapshotUpdated /
  /// activeSessionChanged / sessionEvent / vendorChanged 时都会附带，null 表示
  /// 当前没有 active session。Dart 直接以此覆盖缓存。
  final Map<String, Object?>? sessionSnapshot;

  final String? errorCode;
  final String? errorMessage;
}

/// 设备主动触发 agent 的事件（由 [DeviceManager.agentTriggers] 派发）。
@immutable
class DeviceAgentTrigger {
  const DeviceAgentTrigger({
    required this.deviceId,
    required this.kind,
    this.payload = const {},
  });

  final String deviceId;

  /// 'chat' | 'translate' | 'stop'
  final DeviceAgentTriggerKind kind;

  final Map<String, Object?> payload;
}

enum DeviceAgentTriggerKind { chat, translate, stop }
