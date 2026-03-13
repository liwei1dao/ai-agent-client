/// STS（端到端语音）配置
class StsConfig {
  const StsConfig({
    required this.apiKey,
    required this.appId,
    this.voiceName = 'zh_female_tianmei',
    this.extraParams = const {},
  });

  final String apiKey;
  final String appId;
  final String voiceName;
  final Map<String, String> extraParams;
}

/// STS 事件类型
enum StsEventType {
  /// 连接建立
  connected,

  /// 接收到音频数据（分片）
  audioChunk,

  /// 一句话结束
  sentenceDone,

  /// 断开连接
  disconnected,

  /// 错误
  error,
}

/// STS 事件
class StsEvent {
  const StsEvent({
    required this.type,
    this.audioData,
    this.text,
    this.errorCode,
    this.errorMessage,
  });

  final StsEventType type;
  final List<int>? audioData;
  final String? text;
  final String? errorCode;
  final String? errorMessage;
}

/// STS 插件抽象接口（端到端，agent_runtime 直接调度）
abstract class StsPlugin {
  /// 初始化
  Future<void> initialize(StsConfig config);

  /// 建立 WebSocket 连接，开始双向通话
  Future<void> startCall();

  /// 发送音频数据（麦克风录制的 PCM）
  void sendAudio(List<int> pcmData);

  /// 结束通话
  Future<void> stopCall();

  /// STS 事件流
  Stream<StsEvent> get eventStream;

  /// 释放资源
  Future<void> dispose();
}
