import 'dart:async';

import 'device_capability.dart';
import 'device_event.dart';
import 'device_info.dart';
import 'device_plugin.dart';
import 'device_session.dart';

/// 容器层入口（业务层只见此一个）。
///
/// 单设备模型：
/// - `activeSession` 至多一个；切换厂商或连接新设备会先断开旧 session；
/// - 唤醒/翻译键事件统一从 [agentTriggers] 派发；
/// - 音频通道（耳机麦/扬声器）一律由 native 内部管理，Flutter 不直接持有。
///
/// 所有方法在 `dispose` 后必须抛 `StateError`。
abstract class DeviceManager {
  // ---------- 厂商管理 ----------

  /// 已注册的厂商（在 app 启动时由各 plugin 主动 register）。
  Map<String, DevicePluginDescriptor> get registeredVendors;

  /// 注册厂商工厂。`replace=false` 时同 key 重复注册抛 [DeviceException]。
  void registerVendor(
    DevicePluginDescriptor descriptor, {
    bool replace = false,
  });

  /// 当前激活的厂商 key；未选择为 null。
  String? get activeVendor;

  /// 当前激活厂商的能力集合（便于 UI 一行判断）；无 active 时空集合。
  Set<DeviceCapability> get activeCapabilities;

  /// 切换厂商。流程（原子操作）：
  ///
  /// 1. `stopScan()`
  /// 2. 断开 [activeSession]（若有）
  /// 3. dispose 旧 plugin
  /// 4. 创建并 initialize 新 plugin
  /// 5. 派发 `vendorChanged`
  ///
  /// 切换中所有 scan/connect 调用抛 `DeviceException('device.vendor_switching')`。
  Future<void> useVendor(String vendorKey, DevicePluginConfig config);

  /// 清空当前 vendor —— 断开 active session、dispose 旧 plugin，
  /// 派发 `vendorChanged(vendorKey=null)`。无 active vendor 时 no-op。
  Future<void> clearVendor();

  // ---------- 扫描 / 连接 ----------

  Future<void> startScan({DeviceScanFilter? filter, Duration? timeout});
  Future<void> stopScan();

  /// 当前蓝牙开关状态。仅由 native 实现真实查询，pure-Dart 默认返回 true。
  Future<bool> isBluetoothEnabled();

  /// 已配对设备（来自 active plugin）。
  Future<List<DiscoveredDevice>> bondedDevices();

  /// 连接设备。如果当前已有 active session，先断开旧的再连新的，
  /// 并派发 `activeSessionChanged`。
  Future<DeviceSession> connect(
    String deviceId, {
    DeviceConnectOptions? options,
  });

  /// 断开当前 session（无 session 时 no-op）。
  Future<void> disconnect();

  /// 当前 active session；未连接为 null。
  DeviceSession? get activeSession;

  // ---------- agent 协调 ----------

  /// 设备主动触发 agent 的事件（PTT/语音唤醒/翻译键）。
  /// 由 `agents_server` 中的 `DeviceAgentRouter` 监听。
  Stream<DeviceAgentTrigger> get agentTriggers;

  /// 容器全局事件流：扫描结果、连接状态、active session 变更等。
  Stream<DeviceManagerEvent> get eventStream;

  // ---------- 生命周期 ----------

  Future<void> initialize();
  Future<void> dispose();
}

/// 厂商描述符（用于注册表 / 设置 UI 列表）。
class DevicePluginDescriptor {
  DevicePluginDescriptor({
    required this.vendorKey,
    required this.displayName,
    required this.factory,
    this.configSchema = DevicePluginConfigSchema.empty,
    this.declaredCapabilities = const {},
  });

  final String vendorKey;
  final String displayName;
  final DevicePluginFactory factory;
  final DevicePluginConfigSchema configSchema;

  /// 能力声明的"广告版"——容器在 plugin 未 initialize 前用它做 UI 引导。
  /// 真实可用能力以 [DevicePlugin.capabilities] 为准。
  final Set<DeviceCapability> declaredCapabilities;
}
