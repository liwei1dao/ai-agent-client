/// 统一错误码命名空间：`device.<reason>`。
///
/// 通用约定：
/// - `permission_denied` / `bluetooth_off` 是 UI 引导用户的固定码；
/// - `audio_busy` 表示同一 session 已有 active 上行/下行；
/// - `not_supported` 表示厂商插件未声明对应能力；
/// - `format_unsupported` 出现在 `DevicePlugin.initialize` 阶段，用以禁用厂商。
class DeviceErrorCode {
  DeviceErrorCode._();

  static const String permissionDenied = 'device.permission_denied';
  static const String bluetoothOff = 'device.bluetooth_off';
  static const String scanFailed = 'device.scan_failed';
  static const String connectTimeout = 'device.connect_timeout';
  static const String connectFailed = 'device.connect_failed';
  static const String handshakeFailed = 'device.handshake_failed';
  static const String disconnectedRemote = 'device.disconnected_remote';
  static const String disconnectedLocal = 'device.disconnected_local';
  static const String writeFailed = 'device.write_failed';
  static const String readFailed = 'device.read_failed';
  static const String featureFailed = 'device.feature_failed';
  static const String audioBusy = 'device.audio_busy';
  static const String notSupported = 'device.not_supported';
  static const String formatUnsupported = 'device.format_unsupported';
  static const String vendorSwitching = 'device.vendor_switching';
  static const String noActiveSession = 'device.no_active_session';
  static const String invalidArgument = 'device.invalid_argument';
  static const String pluginNotInitialized = 'device.plugin_not_initialized';
}

/// 设备域统一异常。
///
/// - 所有插件方法**禁止**让 SDK 原始异常逃逸；要么 catch 后转换为
///   [DeviceException]，要么以 `error` 事件派发到事件流。
/// - [code] 必须使用 [DeviceErrorCode] 中预定义的字符串；新增码必须同步更新。
class DeviceException implements Exception {
  DeviceException(this.code, [this.message, this.cause]);

  final String code;
  final String? message;
  final Object? cause;

  @override
  String toString() =>
      'DeviceException($code${message == null ? '' : ': $message'})';
}
