import 'package:flutter/foundation.dart';

/// 配置：语音合成服务
class TtsConfig {
  const TtsConfig({
    required this.apiKey,
    required this.region,
    this.voiceName = 'zh-CN-XiaoxiaoNeural',
    this.outputFormat = 'audio-16khz-128kbitrate-mono-mp3',
    this.extraParams = const {},
  });

  final String apiKey;
  final String region;
  final String voiceName;
  final String outputFormat;
  final Map<String, String> extraParams;
}

/// TTS 事件类型（7 种）
enum TtsEventType {
  /// 开始合成请求（网络请求已发出）
  synthesisStart,

  /// 合成完成，音频数据已就绪（可开始播放）
  synthesisReady,

  /// 开始播放音频
  playbackStart,

  /// 播放进度（已播放时长 ms）
  playbackProgress,

  /// 播放完成
  playbackDone,

  /// 播放被打断（新 requestId 来临）
  playbackInterrupted,

  /// 错误
  error,
}

/// TTS 事件
@immutable
class TtsEvent {
  const TtsEvent({
    required this.type,
    this.progressMs,
    this.durationMs,
    this.errorCode,
    this.errorMessage,
  });

  final TtsEventType type;

  /// 当前播放进度（ms），playbackProgress 时有值
  final int? progressMs;

  /// 音频总时长（ms），synthesisReady 时有值
  final int? durationMs;

  final String? errorCode;
  final String? errorMessage;
}

/// TTS 插件抽象接口
abstract class TtsPlugin {
  /// 初始化
  Future<void> initialize(TtsConfig config);

  /// 合成并播放文本
  Future<void> speak(String text, {String? requestId});

  /// 停止当前播放（触发 playbackInterrupted）
  Future<void> stop();

  /// TTS 事件流
  Stream<TtsEvent> get eventStream;

  /// 释放资源
  Future<void> dispose();
}
