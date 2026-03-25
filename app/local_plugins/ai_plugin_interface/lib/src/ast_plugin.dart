import 'package:flutter/foundation.dart';

/// AST（端到端语音翻译）配置
class AstConfig {
  const AstConfig({
    required this.apiKey,
    required this.appId,
    this.srcLang = 'zh',
    this.dstLang = 'en',
    this.extraParams = const {},
  });

  final String apiKey;
  final String appId;
  final String srcLang;
  final String dstLang;
  final Map<String, String> extraParams;
}

/// AST 事件类型
enum AstEventType {
  /// 连接建立
  connected,

  /// 源语言字幕（用户语音识别文字）
  sourceSubtitle,

  /// 翻译后字幕
  translatedSubtitle,

  /// 收到 TTS 音频数据
  ttsAudioChunk,

  /// 断开连接
  disconnected,

  /// 错误
  error,
}

/// AST 事件
@immutable
class AstEvent {
  const AstEvent({
    required this.type,
    this.text,
    this.audioData,
    this.errorCode,
    this.errorMessage,
  });

  final AstEventType type;
  final String? text;
  final List<int>? audioData;
  final String? errorCode;
  final String? errorMessage;
}

/// AST 插件抽象接口（端到端语音翻译）
abstract class AstPlugin {
  /// 初始化
  Future<void> initialize(AstConfig config);

  /// 建立 WebSocket 连接
  Future<void> startCall();

  /// 发送音频数据（麦克风录制的 PCM）
  void sendAudio(List<int> pcmData);

  /// 结束通话
  Future<void> stopCall();

  /// AST 事件流
  Stream<AstEvent> get eventStream;

  /// 释放资源
  Future<void> dispose();
}
