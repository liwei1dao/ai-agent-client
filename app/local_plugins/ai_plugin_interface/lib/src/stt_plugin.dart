import 'package:flutter/foundation.dart';

/// 配置：语音识别服务
class SttConfig {
  const SttConfig({
    required this.apiKey,
    required this.region,
    this.language = 'zh-CN',
    this.extraParams = const {},
  });

  final String apiKey;
  final String region;
  final String language;
  final Map<String, String> extraParams;
}

/// STT 事件类型（7 种）
enum SttEventType {
  /// 开始监听（麦克风已打开）
  listeningStarted,

  /// VAD 检测到语音开始
  vadSpeechStart,

  /// VAD 检测到语音结束（静音超时）
  vadSpeechEnd,

  /// 识别中间结果（流式）
  partialResult,

  /// 识别最终结果（isFinal=true，此时生成 requestId）
  finalResult,

  /// 停止监听（麦克风已关闭）
  listeningStopped,

  /// 错误
  error,
}

/// STT 事件
@immutable
class SttEvent {
  const SttEvent({
    required this.type,
    this.text,
    this.isFinal = false,
    this.errorCode,
    this.errorMessage,
  });

  final SttEventType type;

  /// 识别文本（partialResult / finalResult 时有值）
  final String? text;

  /// 是否为最终结果
  final bool isFinal;

  /// 错误码（error 时有值）
  final String? errorCode;

  /// 错误描述
  final String? errorMessage;
}

/// STT 插件抽象接口
abstract class SttPlugin {
  /// 初始化（加载 SDK、申请权限等）
  Future<void> initialize(SttConfig config);

  /// 开始监听（打开麦克风）
  Future<void> startListening();

  /// 停止监听
  Future<void> stopListening();

  /// STT 事件流
  Stream<SttEvent> get eventStream;

  /// 释放资源
  Future<void> dispose();
}
