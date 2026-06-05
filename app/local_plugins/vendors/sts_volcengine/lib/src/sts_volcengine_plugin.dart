import 'dart:async';
import 'dart:math' as math;

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'sts_volcengine_plugin_desktop.dart';

/// StsVolcenginePlugin — 火山引擎端到端语音（STS），非 web 分支统一门面。
///
/// 条件导入无法区分 mobile 与 desktop（都满足 `dart.library.io`），运行时分派：
/// - **移动端（Android / iOS）**：[_StsVolcengineMethodChannel] —— 原生 WebSocket。
/// - **桌面（macOS / Windows / Linux）**：[StsVolcengineDesktop] —— 纯 Dart 协议 +
///   record 采集 + flutter_pcm_sound 播放。
class StsVolcenginePlugin implements StsPlugin {
  StsVolcenginePlugin() : _impl = _pickImpl();

  final StsPlugin _impl;

  static StsPlugin _pickImpl() {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return isDesktop ? StsVolcengineDesktop() : _StsVolcengineMethodChannel();
  }

  @override
  Future<void> initialize(StsConfig config) => _impl.initialize(config);

  @override
  Future<void> startCall() => _impl.startCall();

  @override
  void sendAudio(List<int> pcmData) => _impl.sendAudio(pcmData);

  @override
  Future<void> stopCall() => _impl.stopCall();

  @override
  Stream<StsEvent> get eventStream => _impl.eventStream;

  @override
  Future<void> dispose() => _impl.dispose();
}

/// 移动端实现：通过 MethodChannel 调用原生 WebSocket（OkHttp/URLSession）。
///
/// 原生侧目前仍在发送旧协议的 `sentenceDone` / `audioChunk` 事件；本 Dart
/// 包装层做一次"最小翻译"，把它们映射为新的识别生命周期事件。
class _StsVolcengineMethodChannel implements StsPlugin {
  static const _channel = MethodChannel('sts_volcengine/commands');
  static const _eventChannel = EventChannel('sts_volcengine/events');

  StsConfig? _config;
  StreamController<StsEvent>? _controller;
  StreamSubscription? _nativeSub;

  // Round state for the compat translation layer.
  String? _currentRequestId;
  bool _botRoleOpen = false;
  bool _botPlaybackOpen = false;

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
      _handleNativeEvent(kind, map);
    });

    await _channel.invokeMethod('startCall', {
      'apiKey': _config!.apiKey,
      'appId': _config!.appId,
      'voiceName': _config!.voiceName,
    });

    _emit(const StsEvent(type: StsEventType.connected));
  }

  @override
  void sendAudio(List<int> pcmData) {
    _channel.invokeMethod('sendAudio', {'data': pcmData});
  }

  @override
  Future<void> stopCall() async {
    await _channel.invokeMethod('stopCall');
    _forceCloseRound(interrupted: true);
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

  void _handleNativeEvent(String? kind, Map<Object?, Object?> map) {
    switch (kind) {
      case 'audioChunk':
        final data = (map['data'] as List?)?.cast<int>();
        _ensureBotRound();
        _emit(StsEvent(
          type: StsEventType.audioChunk,
          role: StsRole.bot,
          requestId: _currentRequestId,
          audioData: data,
        ));
        if (!_botPlaybackOpen) {
          _emit(StsEvent(
            type: StsEventType.playbackStart,
            role: StsRole.bot,
            requestId: _currentRequestId,
          ));
          _botPlaybackOpen = true;
        }
        break;

      case 'sentenceDone':
        // Legacy native event — map to a complete bot turn.
        final text = map['text'] as String?;
        if (text == null || text.isEmpty) {
          // Empty sentenceDone historically meant "user interrupted" — close
          // the round as interrupted.
          _forceCloseRound(interrupted: true);
        } else {
          _emitBotTurnWhole(text);
        }
        break;

      case 'disconnected':
        _forceCloseRound(interrupted: true);
        _emit(const StsEvent(type: StsEventType.disconnected));
        break;

      case 'error':
        _emit(StsEvent(
          type: StsEventType.error,
          requestId: _currentRequestId,
          errorCode: map['errorCode'] as String?,
          errorMessage: map['errorMessage'] as String?,
        ));
        break;

      default:
        // Unknown native kind — drop.
        break;
    }
  }

  void _ensureBotRound() {
    if (_currentRequestId != null) return;
    _currentRequestId = _newRequestId();
    _botRoleOpen = true;
    _emit(StsEvent(
      type: StsEventType.recognitionStart,
      role: StsRole.bot,
      requestId: _currentRequestId,
    ));
  }

  void _emitBotTurnWhole(String fullText) {
    _currentRequestId ??= _newRequestId();
    final requestId = _currentRequestId!;
    if (!_botRoleOpen) {
      _botRoleOpen = true;
      _emit(StsEvent(
        type: StsEventType.recognitionStart,
        role: StsRole.bot,
        requestId: requestId,
      ));
    }
    _emit(StsEvent(
      type: StsEventType.recognized,
      role: StsRole.bot,
      requestId: requestId,
      text: fullText,
    ));
    _emit(StsEvent(
      type: StsEventType.recognitionDone,
      role: StsRole.bot,
      requestId: requestId,
    ));
    _botRoleOpen = false;
  }

  void _forceCloseRound({required bool interrupted}) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    if (_botRoleOpen) {
      _emit(StsEvent(
        type: StsEventType.recognitionDone,
        role: StsRole.bot,
        requestId: requestId,
      ));
      _botRoleOpen = false;
    }
    if (_botPlaybackOpen) {
      _emit(StsEvent(
        type: StsEventType.playbackEnd,
        role: StsRole.bot,
        requestId: requestId,
        interrupted: interrupted,
      ));
      _botPlaybackOpen = false;
    }
    _emit(StsEvent(
      type: StsEventType.recognitionEnd,
      requestId: requestId,
    ));
    _currentRequestId = null;
  }

  void _emit(StsEvent e) {
    final c = _controller;
    if (c != null && !c.isClosed) c.add(e);
  }

  String _newRequestId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final r = math.Random().nextInt(1 << 30).toRadixString(36).padLeft(6, '0');
    return 'sts_volcengine_${ms}_$r';
  }
}
