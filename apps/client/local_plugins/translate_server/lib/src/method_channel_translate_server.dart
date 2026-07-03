import 'dart:async';

import 'package:flutter/services.dart';

import 'translate_event.dart';
import 'translate_exception.dart';
import 'translate_request.dart';
import 'translate_server.dart';
import 'translate_session.dart';

/// `TranslateServer` 的 MethodChannel 实现 —— 编排逻辑全在 native，本类只做转发。
///
/// channel 协议：
///   - `translate_server/method`:
///       startCallTranslation / stopActiveSession / activeSessionId /
///       startFaceToFaceTranslation* / startAudioTranslation*
///   - `translate_server/events`:
///       字幕 / 状态 / 错误 / 连接状态（统一带 `sessionId` + `type` 字段）
class MethodChannelTranslateServer implements TranslateServer {
  MethodChannelTranslateServer() {
    _eventSub = _events.receiveBroadcastStream().listen(
      (raw) => _route(raw as Map),
      onError: (e, _) => _serverEventCtrl.add(TranslationServerEvent(
        type: TranslationServerEventType.error,
        errorCode: 'translate.event_channel_error',
        errorMessage: '$e',
      )),
    );
  }

  static const _method = MethodChannel('translate_server/method');
  static const _events = EventChannel('translate_server/events');

  StreamSubscription<dynamic>? _eventSub;
  final _serverEventCtrl = StreamController<TranslationServerEvent>.broadcast();

  _CallSessionImpl? _active;
  bool _disposed = false;

  @override
  TranslationSession? get activeSession => _active;

  @override
  TranslationKind? get activeKind => _active?.kind;

  @override
  Stream<TranslationServerEvent> get eventStream => _serverEventCtrl.stream;

  @override
  Future<CallTranslationSession> startCallTranslation(
    CallTranslationRequest request,
  ) async {
    _checkAlive();
    if (_active != null) {
      throw TranslateException(
        TranslateErrorCode.sessionBusy,
        'another translation session is active: ${_active!.sessionId}',
      );
    }

    final String sessionId;
    try {
      sessionId = (await _method.invokeMethod<String>('startCallTranslation', {
        if (request.sessionId != null) 'sessionId': request.sessionId,
        'uplinkAgentType': request.uplinkAgentType,
        'uplinkConfig': request.uplinkConfig,
        'downlinkAgentType': request.downlinkAgentType,
        'downlinkConfig': request.downlinkConfig,
        'userLanguage': request.userLanguage,
        'peerLanguage': request.peerLanguage,
      }))!;
    } on PlatformException catch (e) {
      throw TranslateException(
        e.code.startsWith('translate.') ? e.code : 'translate.start_failed',
        e.message ?? '$e',
      );
    }

    final session = _CallSessionImpl(
      sessionId: sessionId,
      uplinkAgentType: request.uplinkAgentType,
      downlinkAgentType: request.downlinkAgentType,
      userLanguage: request.userLanguage,
      peerLanguage: request.peerLanguage,
      stopHandler: _stopActive,
    );
    _active = session;
    _serverEventCtrl.add(TranslationServerEvent(
      type: TranslationServerEventType.sessionStarted,
      sessionId: sessionId,
    ));
    return session;
  }

  @override
  Future<FaceToFaceTranslationSession> startFaceToFaceTranslation(
    FaceToFaceTranslationRequest request,
  ) {
    _checkAlive();
    throw TranslateException(
      TranslateErrorCode.notImplemented,
      'face-to-face translation not implemented yet',
    );
  }

  @override
  Future<AudioTranslationSession> startAudioTranslation(
    AudioTranslationRequest request,
  ) {
    _checkAlive();
    throw TranslateException(
      TranslateErrorCode.notImplemented,
      'audio translation not implemented yet',
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
    _eventSub = null;
    if (_active != null) {
      await _stopActive();
    }
    await _serverEventCtrl.close();
  }

  Future<void> _stopActive() async {
    try {
      await _method.invokeMethod('stopActiveSession');
    } on PlatformException catch (_) {
      // best effort
    }
  }

  void _route(Map raw) {
    final type = raw['type'] as String?;
    final sessionId = raw['sessionId'] as String?;
    if (sessionId == null) return;
    final session = _active;
    if (session == null || session.sessionId != sessionId) return;

    switch (type) {
      case 'subtitle':
        session._dispatchSubtitle(raw);
      case 'error':
        session._dispatchError(raw);
      case 'sessionState':
        final stateStr = raw['state'] as String?;
        final newState = _parseState(stateStr);
        session._dispatchState(newState, raw['errorMessage'] as String?);
        if (newState == TranslationSessionState.stopped ||
            newState == TranslationSessionState.error) {
          if (identical(_active, session)) {
            _active = null;
            _serverEventCtrl.add(TranslationServerEvent(
              type: TranslationServerEventType.sessionStopped,
              sessionId: sessionId,
            ));
          }
        }
      case 'connectionState':
        // 连接状态目前不暴露给 TranslationSession 接口；如需，扩 stateStream / 加 connectionStream。
        break;
    }
  }

  TranslationSessionState _parseState(String? s) => switch (s) {
        'starting' => TranslationSessionState.starting,
        'active' => TranslationSessionState.active,
        'stopping' => TranslationSessionState.stopping,
        'stopped' => TranslationSessionState.stopped,
        'error' => TranslationSessionState.error,
        _ => TranslationSessionState.starting,
      };

  void _checkAlive() {
    if (_disposed) {
      throw StateError('TranslateServer already disposed');
    }
  }
}

class _CallSessionImpl extends CallTranslationSession {
  _CallSessionImpl({
    required this.sessionId,
    required this.uplinkAgentType,
    required this.downlinkAgentType,
    required this.userLanguage,
    required this.peerLanguage,
    required Future<void> Function() stopHandler,
  })  : _stopHandler = stopHandler,
        startedAtMs = DateTime.now().millisecondsSinceEpoch;

  final Future<void> Function() _stopHandler;

  @override
  final String sessionId;
  @override
  final int startedAtMs;
  @override
  final String uplinkAgentType;
  @override
  final String downlinkAgentType;
  @override
  final String userLanguage;
  @override
  final String peerLanguage;

  TranslationSessionState _state = TranslationSessionState.starting;

  final _subtitleCtrl = StreamController<TranslateSubtitleEvent>.broadcast();
  final _errorCtrl = StreamController<TranslateErrorEvent>.broadcast();
  final _stateCtrl = StreamController<TranslationSessionState>.broadcast();
  final _latestByRole = <SubtitleRole, TranslateSubtitleEvent>{};
  bool _stopped = false;

  @override
  TranslationSessionState get state => _state;

  @override
  Stream<TranslateSubtitleEvent> get subtitles => _subtitleCtrl.stream;

  @override
  Stream<TranslateErrorEvent> get errors => _errorCtrl.stream;

  @override
  Stream<TranslationSessionState> get stateStream => _stateCtrl.stream;

  @override
  TranslateSubtitleEvent? latestSubtitleByRole(SubtitleRole role) =>
      _latestByRole[role];

  @override
  Future<void> stop() async {
    if (_stopped) return;
    await _stopHandler();
    // 实际收尾在 sessionState=stopped 事件到达时由 _close 完成。
  }

  // ────────────────── 事件路由（由 server _route 调用） ──────────────────

  void _dispatchSubtitle(Map raw) {
    if (_subtitleCtrl.isClosed) return;
    final legStr = raw['leg'] as String? ?? '';
    final stageStr = raw['stage'] as String? ?? '';
    final role = _parseRole(legStr);
    final stage = _parseStage(stageStr);
    final evt = TranslateSubtitleEvent(
      sessionId: sessionId,
      role: role,
      stage: stage,
      sourceText: (raw['sourceText'] as String?) ?? '',
      translatedText: raw['translatedText'] as String?,
      requestId: raw['requestId'] as String?,
      sourceLanguage: raw['sourceLanguage'] as String?,
      destLanguage: raw['destLanguage'] as String?,
    );
    _latestByRole[role] = evt;
    _subtitleCtrl.add(evt);
  }

  void _dispatchError(Map raw) {
    if (_errorCtrl.isClosed) return;
    _errorCtrl.add(TranslateErrorEvent(
      sessionId: sessionId,
      code: (raw['code'] as String?) ?? 'translate.unknown',
      message: raw['message'] as String?,
      role: _parseOptionalRole(raw['leg'] as String?),
      fatal: (raw['fatal'] as bool?) ?? false,
    ));
  }

  void _dispatchState(TranslationSessionState newState, String? errorMessage) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateCtrl.isClosed) _stateCtrl.add(newState);
    if (newState == TranslationSessionState.stopped ||
        newState == TranslationSessionState.error) {
      _close();
    }
  }

  void _close() {
    if (_stopped) return;
    _stopped = true;
    _subtitleCtrl.close();
    _errorCtrl.close();
    _stateCtrl.close();
  }

  static SubtitleRole _parseRole(String s) => switch (s) {
        'uplink' => SubtitleRole.user,
        'downlink' => SubtitleRole.peer,
        'media' => SubtitleRole.media,
        _ => SubtitleRole.user,
      };

  static SubtitleRole? _parseOptionalRole(String? s) =>
      s == null ? null : _parseRole(s);

  static SubtitleStage _parseStage(String s) => switch (s) {
        'partial' => SubtitleStage.partial,
        'final' => SubtitleStage.finalized,
        _ => SubtitleStage.partial,
      };
}
