import 'dart:async';
import 'package:flutter/services.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// SttAzurePluginDart — Dart 侧桥接（封装 MethodChannel + EventChannel）
///
/// 实现 [SttPlugin] 抽象接口，将 Native 事件转换为 [SttEvent] 流。
class SttAzurePluginDart implements SttPlugin {
  static const _cmd = MethodChannel('stt_azure/commands');
  static const _evt = EventChannel('stt_azure/events');

  StreamController<SttEvent>? _controller;
  StreamSubscription? _nativeSub;

  @override
  Future<void> initialize(SttConfig config) async {
    _controller ??= StreamController<SttEvent>.broadcast();
    _nativeSub ??= _evt.receiveBroadcastStream().listen(_onNativeEvent);
    await _cmd.invokeMethod('initialize', {
      'apiKey': config.apiKey,
      'region': config.region,
      'language': config.language,
    });
  }

  @override
  Future<void> startListening() async {
    _controller ??= StreamController<SttEvent>.broadcast();
    _nativeSub ??= _evt.receiveBroadcastStream().listen(_onNativeEvent);
    await _cmd.invokeMethod('startListening');
  }

  @override
  Future<void> stopListening() async {
    await _cmd.invokeMethod('stopListening');
  }

  @override
  Stream<SttEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await _cmd.invokeMethod('stopListening');
    _nativeSub?.cancel();
    _controller?.close();
    _nativeSub = null;
    _controller = null;
  }

  void _onNativeEvent(dynamic raw) {
    final map = raw as Map<Object?, Object?>;
    final kind = map['kind'] as String?;
    final text = map['text'] as String?;
    final errorCode = map['errorCode'] as String?;
    final errorMessage = map['errorMessage'] as String?;

    final eventType = switch (kind) {
      'listeningStarted' => SttEventType.listeningStarted,
      'vadSpeechStart' => SttEventType.vadSpeechStart,
      'vadSpeechEnd' => SttEventType.vadSpeechEnd,
      'partialResult' => SttEventType.partialResult,
      'finalResult' => SttEventType.finalResult,
      'listeningStopped' => SttEventType.listeningStopped,
      _ => SttEventType.error,
    };

    _controller?.add(SttEvent(
      type: eventType,
      text: text,
      isFinal: kind == 'finalResult',
      errorCode: errorCode,
      errorMessage: errorMessage,
    ));
  }
}
