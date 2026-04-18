import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// StsVolcenginePlugin — 火山引擎端到端语音（STS）
///
/// 通过 MethodChannel 调用原生 WebSocket 实现（OkHttp/URLSession）。
/// agent_sts_chat 在需要 STS 模式时直接调度此插件，绕过 STT→LLM→TTS 管线。
///
/// 原生侧目前仍在发送旧协议的 `sentenceDone` / `audioChunk` 事件；本 Dart
/// 包装层做一次"最小翻译"，把它们映射为新的识别生命周期事件
/// （`recognitionStart` → `recognized` → `recognitionDone` → `recognitionEnd`），
/// 供上层消费。等 Kotlin / Swift 侧迁移到新协议后可直接透传。
class StsVolcenginePlugin implements StsPlugin {
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
