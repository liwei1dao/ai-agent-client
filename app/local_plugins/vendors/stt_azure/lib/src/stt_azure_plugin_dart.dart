import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'stt_azure_plugin_desktop.dart';

/// SttAzurePluginDart — 非 web 分支统一门面。
///
/// 条件导入无法区分 mobile 与 desktop（都满足 `dart.library.io`），运行时分派：
/// - **移动端（Android / iOS）**：[_SttAzureMethodChannel] —— 原生 Azure SDK。
/// - **桌面（macOS / Windows / Linux）**：[SttAzureDesktop] —— Azure 语音 WebSocket
///   + record 采集。
class SttAzurePluginDart implements SttPlugin {
  SttAzurePluginDart() : _impl = _pickImpl();

  final SttPlugin _impl;

  static SttPlugin _pickImpl() {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return isDesktop ? SttAzureDesktop() : _SttAzureMethodChannel();
  }

  @override
  bool get supportsLanguageDetection => _impl.supportsLanguageDetection;

  @override
  Future<void> initialize(SttConfig config) => _impl.initialize(config);

  @override
  Future<void> startListening() => _impl.startListening();

  @override
  Future<void> stopListening() => _impl.stopListening();

  @override
  Stream<SttEvent> get eventStream => _impl.eventStream;

  @override
  Future<void> dispose() => _impl.dispose();
}

/// 移动端实现：MethodChannel + EventChannel → 原生 Azure SDK。
class _SttAzureMethodChannel implements SttPlugin {
  static const _cmd = MethodChannel('stt_azure/commands');
  static const _evt = EventChannel('stt_azure/events');

  StreamController<SttEvent>? _controller;
  StreamSubscription? _nativeSub;

  @override
  bool get supportsLanguageDetection => false;

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
    final detectedLang = map['detectedLang'] as String?;
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
      detectedLang: detectedLang,
      errorCode: errorCode,
      errorMessage: errorMessage,
    ));
  }
}
