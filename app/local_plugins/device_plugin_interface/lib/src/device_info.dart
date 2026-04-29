import 'package:flutter/foundation.dart';

/// 扫描时发现的设备（尚未连接）。
@immutable
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.id,
    required this.name,
    this.rssi,
    this.vendor,
    this.metadata = const {},
  });

  /// 厂商插件不透明 ID。
  /// - 杰里：BLE MAC（与 [metadata]['edrAddr'] 一同标识真实设备）
  /// - BLE 通用：MAC（Android）/ CBPeripheral.identifier（iOS）
  ///
  /// **业务层只把它当字符串用**，不要解析或假设格式。
  final String id;

  /// 广播名/友好名。
  final String name;

  /// 信号强度（dBm），未知为 null。
  final int? rssi;

  /// 来源厂商插件 [DevicePlugin.vendorKey]。
  final String? vendor;

  /// 厂商相关的扩展字段（edrAddr / deviceType / advertisementData / serviceUuids 等）。
  /// key 由具体厂商插件文档约定。
  final Map<String, Object?> metadata;

  @override
  String toString() => 'DiscoveredDevice($name, $id, rssi=$rssi)';
}

/// 已连接设备的信息快照。
@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.vendor,
    this.firmwareVersion,
    this.hardwareVersion,
    this.serialNumber,
    this.manufacturer,
    this.model,
    this.batteryPercent,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final String vendor;

  final String? firmwareVersion;
  final String? hardwareVersion;
  final String? serialNumber;
  final String? manufacturer;
  final String? model;

  /// 0..100；未知为 null。
  final int? batteryPercent;

  final Map<String, Object?> metadata;

  DeviceInfo copyWith({
    String? name,
    String? firmwareVersion,
    String? hardwareVersion,
    String? serialNumber,
    String? manufacturer,
    String? model,
    int? batteryPercent,
    Map<String, Object?>? metadata,
  }) {
    return DeviceInfo(
      id: id,
      vendor: vendor,
      name: name ?? this.name,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      hardwareVersion: hardwareVersion ?? this.hardwareVersion,
      serialNumber: serialNumber ?? this.serialNumber,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      metadata: metadata ?? this.metadata,
    );
  }
}

/// 连接状态机（细化以容纳"链路通了但 RCSP 协议尚未握手"的中间态）。
enum DeviceConnectionState {
  disconnected,

  /// 已发起连接，链路（ACL/GATT/SPP）尚未建立
  connecting,

  /// 蓝牙链路已建立，等待厂商私有协议握手（如杰里 RCSP init、GATT 服务发现等）
  linkConnected,

  /// 协议握手完成，业务可调用 read/write/feature
  ready,

  /// 已发起断开，等待对端确认
  disconnecting,
}

/// 扫描过滤条件。所有字段均可选；`null` 表示不过滤。
@immutable
class DeviceScanFilter {
  const DeviceScanFilter({
    this.namePrefix,
    this.serviceUuids,
    this.vendor,
    this.minRssi,
  });

  final String? namePrefix;
  final List<String>? serviceUuids;
  final String? vendor;
  final int? minRssi;
}

/// 连接选项。
@immutable
class DeviceConnectOptions {
  const DeviceConnectOptions({
    this.timeout = const Duration(seconds: 15),
    this.extra = const {},
  });

  final Duration timeout;

  /// 厂商私有连接参数（如杰里的 connectWay/deviceType）。
  final Map<String, Object?> extra;
}
