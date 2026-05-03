import 'package:json_annotation/json_annotation.dart';

part 'channel_app_model.g.dart';

/// 渠道应用信息响应模型
@JsonSerializable()
class ChannelAppResponse {
  @JsonKey(name: 'code')
  final int code;

  @JsonKey(name: 'data')
  final ChannelAppData? data;

  @JsonKey(name: 'msg')
  final String msg;

  const ChannelAppResponse({
    required this.code,
    this.data,
    required this.msg,
  });

  factory ChannelAppResponse.fromJson(Map<String, dynamic> json) =>
      _$ChannelAppResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ChannelAppResponseToJson(this);
}

/// 渠道应用数据模型
@JsonSerializable()
class ChannelAppData {
  @JsonKey(name: 'app')
  final AppInfo app;

  const ChannelAppData({
    required this.app,
  });

  factory ChannelAppData.fromJson(Map<String, dynamic> json) =>
      _$ChannelAppDataFromJson(json);

  Map<String, dynamic> toJson() => _$ChannelAppDataToJson(this);
}

/// 应用信息模型
@JsonSerializable()
class AppInfo {
  /// 下载地址（可选）
  @JsonKey(name: 'address')
  final String? address;

  /// 渠道标识（支持数字类型转换）
  @JsonKey(
    name: 'channel',
    fromJson: UserChannel.fromJson,
    toJson: _channelToJson,
  )
  final UserChannel channel;

  /// 应用描述
  @JsonKey(name: 'description')
  final String description;

  /// 最新版本号
  @JsonKey(name: 'version')
  final String version;

  /// 是否显示游客登录
  @JsonKey(name: 'tourists')
  final bool tourists;

  /// 是否允许跳过设备绑定
  @JsonKey(name: 'allowskipdevicebinding')
  final bool allowskipdevicebinding;

  /// 支付渠道列表
  @JsonKey(name: 'Paychannels')
  final String? paychannels;

  const AppInfo({
    this.address,
    required this.channel,
    required this.description,
    required this.version,
    this.tourists = false,
    this.allowskipdevicebinding = false,
    required this.paychannels,
  });

  factory AppInfo.fromJson(Map<String, dynamic> json) =>
      _$AppInfoFromJson(json);

  Map<String, dynamic> toJson() => _$AppInfoToJson(this);
}

// 辅助函数：将 UserChannel 转换为 JSON
int _channelToJson(UserChannel channel) => channel.value;

/// 版本更新信息模型
class VersionUpdateInfo {
  /// 是否有新版本
  final bool hasUpdate;

  /// 当前版本
  final String currentVersion;

  /// 最新版本
  final String latestVersion;

  /// 应用信息
  final AppInfo? appInfo;

  /// 更新类型
  final UpdateType updateType;

  const VersionUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    this.appInfo,
    required this.updateType,
  });
}

/// 更新类型枚举
enum UpdateType {
  /// 无需更新
  none,

  /// 可选更新
  optional,

  /// 强制更新
  force,
}

/// 应用商店类型枚举
enum AppStoreType {
  /// iOS App Store
  appStore,

  /// Google Play
  googlePlay,

  /// 华为应用市场
  huawei,

  /// 小米应用商店
  xiaomi,

  /// OPPO软件商店
  oppo,

  /// vivo应用商店
  vivo,

  /// 荣耀应用市场
  honor,

  /// 官网下载
  official,

  /// 未知
  unknown,
}

// 用户渠道枚举
enum UserChannel {
  UNKNOWN(0), // 未知渠道
  CHINA_HUAWEI(1), // 中国-华为
  CHINA_XIAOMI(2), // 中国-小米
  CHINA_OPPO(3), // 中国-OPPO
  CHINA_VIVO(4), // 中国-VIVO
  CHINA_HONOR(5), // 中国-荣耀
  OFFICIAL(100), // 官方渠道
  GLOBAL_APPLE(101), // 全球-苹果
  GLOBAL_GOOGLE(102); // 全球-谷歌

  const UserChannel(this.value);
  final int value;

  // 从数字值创建枚举
  static UserChannel fromValue(int value) {
    return UserChannel.values.firstWhere(
      (channel) => channel.value == value,
      orElse: () => UserChannel.UNKNOWN,
    );
  }

  // 从字符串名称创建枚举
  static UserChannel fromName(String name) {
    switch (name.toUpperCase()) {
      case 'CHINA_HUAWEI':
        return UserChannel.CHINA_HUAWEI;
      case 'CHINA_XIAOMI':
        return UserChannel.CHINA_XIAOMI;
      case 'CHINA_OPPO':
        return UserChannel.CHINA_OPPO;
      case 'CHINA_VIVO':
        return UserChannel.CHINA_VIVO;
      case 'CHINA_HONOR':
        return UserChannel.CHINA_HONOR;
      case 'OFFICIAL':
        return UserChannel.OFFICIAL;
      case 'GLOBAL_APPLE':
        return UserChannel.GLOBAL_APPLE;
      case 'GLOBAL_GOOGLE':
        return UserChannel.GLOBAL_GOOGLE;
      default:
        return UserChannel.UNKNOWN;
    }
  }

  // JSON 序列化时返回数字值
  int toJson() => value;

  // JSON 反序列化时从数字值创建枚举
  static UserChannel fromJson(dynamic json) {
    if (json is int) {
      return fromValue(json);
    } else if (json is String) {
      final intValue = int.tryParse(json);
      if (intValue != null) {
        return fromValue(intValue);
      }
    }
    return UserChannel.UNKNOWN;
  }
}

/// 平台信息模型
class PlatformInfo {
  /// 平台类型
  final String platform;

  /// 应用商店类型
  final AppStoreType storeType;

  /// 渠道标识
  final UserChannel channel;

  const PlatformInfo({
    required this.platform,
    required this.storeType,
    required this.channel,
  });
}
