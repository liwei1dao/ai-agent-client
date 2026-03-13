import 'dart:async';
import 'package:flutter/services.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// StsDoubaoPlugin — 豆包端到端语音（STS）
///
/// 通过 MethodChannel 调用原生 WebSocket 实现（OkHttp/URLSession）。
/// agent_runtime 在需要 STS 模式时直接调度此插件，绕过 STT→LLM→TTS 管线。
class StsDoubaoPlugin implements StsPlugin {
  static const _channel = MethodChannel('sts_doubao/commands');
  static const _eventChannel = EventChannel('sts_doubao/events');

  StsConfig? _config;
  StreamController<StsEvent>? _controller;
  StreamSubscription? _nativeSub;

  @override
  Future<void> initialize(StsConfig config) async {
    _config = config;
  }

  @override
  Future<void> startCall() async {
    _controller = StreamController<StsEvent>.broadcast();

    _nativeSub = _eventChannel.receiveBroadcastStream().listen((raw) {
      final map = raw as Map<Object?, Object?>;
      final kind = map['kind'] as String?;
      _controller?.add(_parseEvent(kind, map));
    });

    await _channel.invokeMethod('startCall', {
      'apiKey': _config!.apiKey,
      'appId': _config!.appId,
      'voiceName': _config!.voiceName,
    });

    _controller?.add(const StsEvent(type: StsEventType.connected));
  }

  @override
  void sendAudio(List<int> pcmData) {
    _channel.invokeMethod('sendAudio', {'data': pcmData});
  }

  @override
  Future<void> stopCall() async {
    await _channel.invokeMethod('stopCall');
    _nativeSub?.cancel();
    _controller?.close();
    _controller = null;
  }

  @override
  Stream<StsEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await stopCall();
  }

  StsEvent _parseEvent(String? kind, Map<Object?, Object?> map) {
    switch (kind) {
      case 'audioChunk':
        final data = (map['data'] as List?)?.cast<int>();
        return StsEvent(type: StsEventType.audioChunk, audioData: data);
      case 'sentenceDone':
        return StsEvent(type: StsEventType.sentenceDone, text: map['text'] as String?);
      case 'disconnected':
        return const StsEvent(type: StsEventType.disconnected);
      case 'error':
        return StsEvent(
          type: StsEventType.error,
          errorCode: map['errorCode'] as String?,
          errorMessage: map['errorMessage'] as String?,
        );
      default:
        return const StsEvent(type: StsEventType.disconnected);
    }
  }
}
