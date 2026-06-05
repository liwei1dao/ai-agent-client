import 'dart:async';
import 'dart:io' show Platform;

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'tts_azure_plugin_desktop.dart';

/// TtsAzurePluginDart — 非 web 分支统一门面。
///
/// 条件导入无法区分 mobile 与 desktop（都满足 `dart.library.io`），故运行时分派：
/// - **移动端（Android / iOS）**：[_TtsAzureMethodChannel] —— 走原生 Azure SDK。
/// - **桌面（macOS / Windows / Linux）**：[TtsAzureDesktop] —— Azure REST + audioplayers。
class TtsAzurePluginDart implements TtsPlugin {
  TtsAzurePluginDart() : _impl = _pickImpl();

  final TtsPlugin _impl;

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static TtsPlugin _pickImpl() =>
      _isDesktop ? TtsAzureDesktop() : _TtsAzureMethodChannel();

  @override
  Future<void> initialize(TtsConfig config) => _impl.initialize(config);

  @override
  Future<void> speak(String text, {String? requestId}) =>
      _impl.speak(text, requestId: requestId);

  @override
  Future<void> stop() => _impl.stop();

  @override
  Stream<TtsEvent> get eventStream => _impl.eventStream;

  @override
  Future<void> dispose() => _impl.dispose();

  /// 设置 iOS 端音频输出模式 (earpiece / speaker / auto)。
  /// Android 由 AgentsServer 统一控制 AudioManager；桌面无此概念，均 no-op。
  static Future<void> setAudioOutputMode(String mode) async {
    if (_isDesktop || !Platform.isIOS) return;
    await _TtsAzureMethodChannel._cmd
        .invokeMethod('setAudioOutputMode', {'mode': mode});
  }
}

/// 移动端实现：MethodChannel → 原生 Azure TTS。
class _TtsAzureMethodChannel implements TtsPlugin {
  static const _cmd = MethodChannel('tts_azure/commands');
  static const _evt = EventChannel('tts_azure/events');

  StreamController<TtsEvent>? _controller;
  StreamSubscription? _nativeSub;

  @override
  Future<void> initialize(TtsConfig config) async {
    _controller ??= StreamController<TtsEvent>.broadcast();
    _nativeSub ??= _evt.receiveBroadcastStream().listen(_onNativeEvent);
    await _cmd.invokeMethod('initialize', {
      'apiKey': config.apiKey,
      'region': config.region,
      'voiceName': config.voiceName,
      'outputFormat': config.outputFormat,
    });
  }

  @override
  Future<void> speak(String text, {String? requestId}) async {
    _controller ??= StreamController<TtsEvent>.broadcast();
    _nativeSub ??= _evt.receiveBroadcastStream().listen(_onNativeEvent);
    await _cmd
        .invokeMethod('speak', {'text': text, 'requestId': requestId ?? ''});
  }

  @override
  Future<void> stop() async {
    await _cmd.invokeMethod('stop');
  }

  @override
  Stream<TtsEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await _cmd.invokeMethod('stop');
    _nativeSub?.cancel();
    _controller?.close();
    _nativeSub = null;
    _controller = null;
  }

  void _onNativeEvent(dynamic raw) {
    final map = raw as Map<Object?, Object?>;
    final kind = map['kind'] as String?;

    final eventType = switch (kind) {
      'synthesisStart' => TtsEventType.synthesisStart,
      'synthesisReady' => TtsEventType.synthesisReady,
      'playbackStart' => TtsEventType.playbackStart,
      'playbackProgress' => TtsEventType.playbackProgress,
      'playbackDone' => TtsEventType.playbackDone,
      'playbackInterrupted' => TtsEventType.playbackInterrupted,
      _ => TtsEventType.error,
    };

    _controller?.add(TtsEvent(
      type: eventType,
      progressMs: map['progressMs'] as int?,
      durationMs: map['durationMs'] as int?,
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    ));
  }
}
