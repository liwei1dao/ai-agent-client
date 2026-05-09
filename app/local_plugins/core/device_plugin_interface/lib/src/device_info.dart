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
///
/// **电量字段约定**（重要，UI 渲染依赖）：
/// - 单一电量设备（眼镜 / 手环 / 单耳设备）只填 [batteryLeft]，其余两个为 null；
/// - TWS 双耳耳机填 [batteryLeft] + [batteryRight]，带充电盒再加 [batteryCase]；
/// - 充电状态按位置独立给：左/右/仓任一可独立处于充电态（如左耳在仓里充、右耳
///   在用）。设备 / SDK 不支持上报充电态时三个字段都默认 false。
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
    this.batteryLeft,
    this.batteryRight,
    this.batteryCase,
    this.chargingLeft = false,
    this.chargingRight = false,
    this.chargingCase = false,
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

  /// 左耳 / 单设备主体电量。0..100；未知或无该位置 = null。
  final int? batteryLeft;

  /// 右耳电量；仅 TWS 双耳设备使用，其余 null。
  final int? batteryRight;

  /// 电仓电量；仅带充电盒的耳机使用，其余 null。
  final int? batteryCase;

  /// 左耳 / 单设备是否在充电。
  final bool chargingLeft;

  /// 右耳是否在充电。
  final bool chargingRight;

  /// 电仓是否在充电（接通外部电源）。
  final bool chargingCase;

  final Map<String, Object?> metadata;

  DeviceInfo copyWith({
    String? name,
    String? firmwareVersion,
    String? hardwareVersion,
    String? serialNumber,
    String? manufacturer,
    String? model,
    int? batteryLeft,
    int? batteryRight,
    int? batteryCase,
    bool? chargingLeft,
    bool? chargingRight,
    bool? chargingCase,
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
      batteryLeft: batteryLeft ?? this.batteryLeft,
      batteryRight: batteryRight ?? this.batteryRight,
      batteryCase: batteryCase ?? this.batteryCase,
      chargingLeft: chargingLeft ?? this.chargingLeft,
      chargingRight: chargingRight ?? this.chargingRight,
      chargingCase: chargingCase ?? this.chargingCase,
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
///
/// - [namePrefix]：设备名前缀（单串，跨厂商）；与 [nameList] 同时存在时各厂商
///   实现可自行选择优先级，杰里实现优先 [nameList]。
/// - [nameList]：设备名命中列表（精确匹配）；空 = 不按名过滤。
/// - [serviceUuids]：UUID 命中列表；杰理实现按 `BleScanMessage.flagContent`
///   做忽略大小写的 contains 匹配。
@immutable
class DeviceScanFilter {
  const DeviceScanFilter({
    this.namePrefix,
    this.nameList,
    this.serviceUuids,
    this.vendor,
    this.minRssi,
    this.skipUnnamed,
  });

  final String? namePrefix;
  final List<String>? nameList;
  final List<String>? serviceUuids;
  final String? vendor;
  final int? minRssi;

  /// 是否跳过没有 `name` 的广播（环境 BLE 噪声过滤）；`null` = 由实现选默认。
  /// 杰理实现默认 `true`。
  final bool? skipUnnamed;
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
