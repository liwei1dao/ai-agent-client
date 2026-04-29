import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_capability.dart';
import 'device_event.dart';
import 'device_info.dart';
import 'device_session.dart';

/// 厂商插件传入的初始化配置。`vendorKey` / `extra` 字段由具体厂商插件文档约定。
@immutable
class DevicePluginConfig {
  const DevicePluginConfig({this.appKey, this.appSecret, this.extra = const {}});

  final String? appKey;
  final String? appSecret;
  final Map<String, Object?> extra;
}

/// 配置 schema（用于 [DeviceManager] 在设置界面动态生成厂商配置表单）。
@immutable
class DevicePluginConfigField {
  const DevicePluginConfigField({
    required this.key,
    required this.label,
    this.required = false,
    this.secret = false,
    this.defaultValue,
    this.helpText,
  });

  final String key;
  final String label;
  final bool required;

  /// 是否敏感字段（密码框 + 不在 UI 明文展示）。
  final bool secret;
  final Object? defaultValue;
  final String? helpText;
}

@immutable
class DevicePluginConfigSchema {
  const DevicePluginConfigSchema({required this.fields});
  final List<DevicePluginConfigField> fields;
  static const empty = DevicePluginConfigSchema(fields: []);
}

/// 厂商插件抽象——每家芯片/SDK 一份实现。
///
/// 容器层 (`DeviceManager`) 通过工厂注册 [DevicePlugin]；同一时刻
/// **最多一个** plugin 处于 `initialized` 状态（多 SDK 并存大概率冲突蓝牙栈）。
///
/// 生命周期与铁律见 §2.1：
/// - `initialize` 幂等：重复调用先释放旧资源；
/// - `dispose` 必须释放**所有**原生资源 + close 事件流；
/// - `dispose` 后任何方法抛 `StateError`。
abstract class DevicePlugin {
  /// 厂商唯一键：`jieli` / `bes` / `qcc` / `bluetrum` / `mock` ...
  String get vendorKey;

  /// 展示用名称。
  String get displayName;

  /// 该厂商插件支持的能力集合。`micUplink` / `connect` / `scan` 是事实必备项。
  Set<DeviceCapability> get capabilities;

  /// 配置 schema：UI 据此渲染设置表单。
  DevicePluginConfigSchema get configSchema => DevicePluginConfigSchema.empty;

  /// 初始化 SDK。失败抛 [DeviceException]，容器据此禁用该厂商。
  Future<void> initialize(DevicePluginConfig config);

  /// 扫描相关。
  Future<void> startScan({DeviceScanFilter? filter, Duration? timeout});
  Future<void> stopScan();
  Future<bool> isScanning();

  /// 已配对设备快照（含历史/系统配对，但**不一定**当前可连）。
  Future<List<DiscoveredDevice>> bondedDevices();

  /// 建立会话。
  ///
  /// 实现要求：
  /// 1. 完成"链路 + 协议握手"两段后再 resolve；
  ///    握手未完成不要返回 [DeviceSession]，否则上层 ready 的语义被破坏。
  /// 2. 失败抛 [DeviceException]，code 取自 [DeviceErrorCode]：
  ///    `connect_timeout` / `connect_failed` / `handshake_failed`。
  Future<DeviceSession> connect(
    String deviceId, {
    DeviceConnectOptions? options,
  });

  /// 当前 active session（最多一个）；未连接为 null。
  DeviceSession? get activeSession;

  /// 全局事件流：扫描/连接/蓝牙开关/错误等。
  Stream<DevicePluginEvent> get eventStream;

  /// 释放 SDK + 断开所有 session + close stream。
  Future<void> dispose();
}

/// 厂商插件工厂。容器层通过 `registerVendor(factory)` 注册；
/// `useVendor(key)` 时调用 [createPlugin] 创建实例。
typedef DevicePluginFactory = DevicePlugin Function();
