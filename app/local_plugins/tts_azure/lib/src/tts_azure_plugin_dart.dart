import 'dart:async';
import 'package:flutter/services.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// TtsAzurePluginDart — Dart 侧桥接
class TtsAzurePluginDart implements TtsPlugin {
  static const _cmd = MethodChannel('tts_azure/commands');
  static const _evt = EventChannel('tts_azure/events');

  StreamController<TtsEvent>? _controller;
  StreamSubscription? _nativeSub;

  @override
  Future<void> initialize(TtsConfig config) async {
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
    await _cmd.invokeMethod('speak', {'text': text, 'requestId': requestId ?? ''});
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
