/// 复合翻译场景错误码命名空间：`translate.<reason>`。
class TranslateErrorCode {
  TranslateErrorCode._();

  /// 通话翻译需要耳机但未连接 / 未 ready
  static const String noDevice = 'translate.no_device';

  /// 当前设备不支持对应翻译能力
  static const String notSupported = 'translate.not_supported';

  /// 厂商插件不是预期的（当前仅杰理实现了通话翻译）
  static const String vendorMismatch = 'translate.vendor_mismatch';

  /// 已有 active session（互斥）
  static const String sessionBusy = 'translate.session_busy';

  /// agent 启动失败 / agent runner 不可用
  static const String agentFailed = 'translate.agent_failed';

  /// 进入 / 退出 RCSP 翻译模式失败
  static const String enterModeFailed = 'translate.enter_mode_failed';
  static const String exitModeFailed = 'translate.exit_mode_failed';

  /// 设备会话中途断开
  static const String deviceDisconnected = 'translate.device_disconnected';

  /// 请求参数非法
  static const String invalidArgument = 'translate.invalid_argument';

  /// 未实现：面对面翻译 / 音视频翻译目前仅占位
  static const String notImplemented = 'translate.not_implemented';
}

class TranslateException implements Exception {
  TranslateException(this.code, [this.message, this.cause]);

  final String code;
  final String? message;
  final Object? cause;

  @override
  String toString() =>
      'TranslateException($code${message == null ? '' : ': $message'})';
}
