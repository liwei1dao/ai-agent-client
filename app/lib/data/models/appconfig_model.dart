import 'package:json_annotation/json_annotation.dart';
import 'package:get/get.dart';

part 'appconfig_model.g.dart'; // 生成的文件名

@JsonSerializable()
class UserGetAppConfigResp {
  final Map<String, String> env;
  final List<DBAgent> agents;
  final Map<String, DBMCPServer> mcps;
  final List<DBProduct> products;

  UserGetAppConfigResp(
      {required this.env,
      required this.agents,
      required this.mcps,
      required this.products});

  factory UserGetAppConfigResp.fromJson(Map<String, dynamic> json) =>
      _$UserGetAppConfigRespFromJson(json);
  Map<String, dynamic> toJson() => _$UserGetAppConfigRespToJson(this);
}

@JsonSerializable()
class DBAgent {
  final String id;
  final String name;
  final String avatarUrl;
  final String description;
  final String tag;
  final bool isOnline;
  final String voice;
  final String? welcomeMessage;
  final String? voiceWelcomeMessage;
  final String? systemPrompt;
  final String? tools;

  DBAgent({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.description,
    required this.tag,
    required this.isOnline,
    required this.voice,
    required this.welcomeMessage,
    required this.voiceWelcomeMessage,
    required this.systemPrompt,
    required this.tools,
  });

  factory DBAgent.fromJson(Map<String, dynamic> json) =>
      _$DBAgentFromJson(json);
  Map<String, dynamic> toJson() => _$DBAgentToJson(this);
}

@JsonSerializable()
class DBMCPServer {
  final String servername;
  final String url;
  final int type;
  final String tools;
  DBMCPServer({
    required this.servername,
    required this.url,
    required this.type,
    required this.tools,
  });

  factory DBMCPServer.fromJson(Map<String, dynamic> json) =>
      _$DBMCPServerFromJson(json);
  Map<String, dynamic> toJson() => _$DBMCPServerToJson(this);
}

@JsonSerializable()
class DBProduct {
  final int id;
  final int factoryid;
  final int devicetype;
  final String devicename;
  final String? productimage;
  final String scanuuid;
  final String? version;
  bool? isforceupdate;
  final bool? iscontinuouschat;
  final bool? wakeupenable; //该产品是否拥有唤醒开关控制
  final bool? broadcastpeertranslate; //通话翻译是否本地播报对方翻译内容
  final String? updatedescription;
  final String? updatepackageaddress;

  DBProduct({
    required this.id,
    required this.factoryid,
    required this.devicetype,
    required this.devicename,
    required this.productimage,
    required this.scanuuid,
    required this.version,
    required this.isforceupdate, //该产品固件版本是否强制更新
    required this.iscontinuouschat,
    required this.wakeupenable,
    required this.broadcastpeertranslate,
    required this.updatedescription,
    required this.updatepackageaddress,
  });

  factory DBProduct.fromJson(Map<String, dynamic> json) =>
      _$DBProductFromJson(json);
  Map<String, dynamic> toJson() => _$DBProductToJson(this);
}

//设备类型
enum DeviceType {
  /// 未知设备
  /// @Description 未知设备
  /// @example
  unknown(0), //未知设备

  /// 经典蓝牙耳机
  /// @Description 经典蓝牙耳机
  /// @example
  classicBluetoothHeadset(1), //经典蓝牙耳机

  /// Ble蓝牙耳机 双端
  /// @Description Ble蓝牙耳机
  /// @example
  bleBluetoothDoubleHeadset(2), //Ble蓝牙耳机 双端

  /// Ble蓝牙耳机 单端
  /// @Description Ble蓝牙耳机
  /// @example
  bleBluetoothSingleHeadset(3), //Ble蓝牙耳机 单端

  /// 智能录音笔
  /// @Description 智能录音笔
  /// @example
  smartVoiceRecorder(4), //智能录音笔

  /// 智能眼镜
  /// @Description 智能眼镜
  /// @example
  smartEye(5); //智能眼镜

  /// 构造函数
  const DeviceType(this.value);

  /// 设备类型对应的整数值
  final int value;
}

// 为 DeviceType 添加扩展方法
extension DeviceTypeExtension on DeviceType {
  /// 获取设备类型的显示名称
  /// @Description 根据设备类型返回对应的翻译键
  String get displayName {
    switch (this) {
      case DeviceType.unknown:
        return "deviceTypeUnknown".tr; // 未知设备
      case DeviceType.classicBluetoothHeadset:
        return "deviceTypeClassicBluetoothHeadset".tr; // 经典蓝牙耳机
      case DeviceType.bleBluetoothDoubleHeadset:
      case DeviceType.bleBluetoothSingleHeadset:
        return "deviceTypeBleBluetoothHeadset".tr; // BLE蓝牙耳机（单端和双端都使用同一个翻译键）
      case DeviceType.smartVoiceRecorder:
        return "deviceTypeSmartVoiceRecorder".tr; // 智能录音笔
      case DeviceType.smartEye:
        return "deviceTypeSmartEye".tr; // 智能眼镜
    }
  }
}
