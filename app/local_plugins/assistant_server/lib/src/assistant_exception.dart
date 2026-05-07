/// AI 助理场景错误码命名空间：`assistant.<reason>`。
class AssistantErrorCode {
  AssistantErrorCode._();

  /// 需要耳机但未连接 / 未 ready
  static const String noDevice = 'assistant.no_device';

  /// 当前设备不支持对应能力
  static const String notSupported = 'assistant.not_supported';

  /// 厂商插件不是预期的（当前仅杰理实现了 PCM 通道）
  static const String vendorMismatch = 'assistant.vendor_mismatch';

  /// 已有 active session（互斥）
  static const String sessionBusy = 'assistant.session_busy';

  /// agent 启动失败 / agent runner 不可用
  static const String agentFailed = 'assistant.agent_failed';

  /// agent 不接受 PCM 外部音频
  static const String agentUnsupported = 'assistant.agent_unsupported';

  /// agent connect 超时
  static const String connectTimeout = 'assistant.connect_timeout';

  /// 进入 / 退出 RCSP 通道失败
  static const String enterModeFailed = 'assistant.enter_mode_failed';
  static const String exitModeFailed = 'assistant.exit_mode_failed';

  /// 设备会话中途断开
  static const String deviceDisconnected = 'assistant.device_disconnected';

  /// 请求参数非法
  static const String invalidArgument = 'assistant.invalid_argument';

  /// 启动失败（兜底）
  static const String startFailed = 'assistant.start_failed';

  /// PCM 推送循环失败
  static const String pumpFailed = 'assistant.pump_failed';
}

class AssistantException implements Exception {
  AssistantException(this.code, [this.message, this.cause]);

  final String code;
  final String? message;
  final Object? cause;

  @override
  String toString() =>
      'AssistantException($code${message == null ? '' : ': $message'})';
}
