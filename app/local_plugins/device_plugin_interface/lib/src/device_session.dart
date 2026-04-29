import 'dart:async';

import 'device_capability.dart';
import 'device_event.dart';
import 'device_info.dart';

/// 已连接设备的会话句柄。生命周期：
///
/// ```
/// connecting → linkConnected → ready → (业务调用) → disconnecting → disconnected
/// ```
///
/// 铁律：
/// 1. `disconnected` 之后任何方法必须抛 `StateError`；
/// 2. `eventStream` 必须用 `StreamController.broadcast()`，`disconnect` 时关闭；
/// 3. 同一时刻最多一个 active [DeviceAudioSource] + 一个 active [DeviceAudioSink]，
///    重复 open 抛 `DeviceException('device.audio_busy')`；
/// 4. `invokeFeature` / `read*` / `write*` 在状态非 `ready` 时抛
///    `DeviceException('device.no_active_session')`，禁止静默排队。
abstract class DeviceSession {
  String get deviceId;
  String get vendor;

  DeviceConnectionState get state;
  DeviceInfo get info;
  Set<DeviceCapability> get capabilities;

  /// 会话事件流（连接态、电量、按键、佩戴...）。
  Stream<DeviceSessionEvent> get eventStream;

  // -------- 通用查询 --------

  Future<int> readRssi();

  Future<int?> readBattery();

  /// 强制刷新 [DeviceInfo]（电量/固件版本/序列号）。
  Future<DeviceInfo> refreshInfo();

  // -------- 厂商私有特性 --------

  /// 调用厂商私有 feature。`featureKey` 形如：
  /// - `common.battery.subscribe`
  /// - `jieli.translation.start`
  /// - `bes.eq.set`
  ///
  /// 返回 `Map<String, Object?>` 或 throw [DeviceException]。
  Future<Map<String, Object?>> invokeFeature(
    String featureKey, [
    Map<String, Object?> args = const {},
  ]);

  // -------- 关闭 --------

  Future<void> disconnect();
}
