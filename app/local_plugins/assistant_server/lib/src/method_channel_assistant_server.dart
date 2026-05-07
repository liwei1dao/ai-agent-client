import 'dart:async';

import 'package:flutter/services.dart';

import 'assistant_event.dart';
import 'assistant_exception.dart';
import 'assistant_request.dart';
import 'assistant_server.dart';
import 'assistant_session.dart';

/// `AssistantServer` 的 MethodChannel 实现 —— 编排逻辑全在 native，本类只做转发。
///
/// channel 协议：
///   - `assistant_server/method`:
///       startAssistant / stopActiveSession / activeSessionId
///   - `assistant_server/events`:
///       message / sessionState / error / connectionState（统一带 `sessionId` + `type` 字段）
class MethodChannelAssistantServer implements AssistantServer {
  MethodChannelAssistantServer() {
    _eventSub = _events.receiveBroadcastStream().listen(
      (raw) => _route(raw as Map),
      onError: (e, _) => _serverEventCtrl.add(AssistantServerEvent(
        type: AssistantServerEventType.error,
        errorCode: 'assistant.event_channel_error',
        errorMessage: '$e',
      )),
    );
  }

  static const _method = MethodChannel('assistant_server/method');
  static const _events = EventChannel('assistant_server/events');

  StreamSubscription<dynamic>? _eventSub;
  final _serverEventCtrl = StreamController<AssistantServerEvent>.broadcast();

  _AssistantSessionImpl? _active;
  bool _disposed = false;

  @override
  AssistantSession? get activeSession => _active;

  @override
  Stream<AssistantServerEvent> get eventStream => _serverEventCtrl.stream;

  @override
  Future<AssistantSession> startAssistant(AssistantRequest request) async {
    _checkAlive();
    if (_active != null) {
      throw AssistantException(
        AssistantErrorCode.sessionBusy,
        'another assistant session is active: ${_active!.sessionId}',
      );
    }

    final String sessionId;
    try {
      sessionId = (await _method.invokeMethod<String>('startAssistant', {
        if (request.sessionId != null) 'sessionId': request.sessionId,
        'agentType': request.agentType,
        'agentConfig': request.agentConfig,
        'userLanguage': request.userLanguage,
      }))!;
    } on PlatformException catch (e) {
      throw AssistantException(
        e.code.startsWith('assistant.') ? e.code : AssistantErrorCode.startFailed,
        e.message ?? '$e',
      );
    }

    final session = _AssistantSessionImpl(
      sessionId: sessionId,
      agentType: request.agentType,
      userLanguage: request.userLanguage,
      stopHandler: _stopActive,
    );
    _active = session;
    _serverEventCtrl.add(AssistantServerEvent(
      type: AssistantServerEventType.sessionStarted,
      sessionId: sessionId,
    ));
    return session;
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
      case 'message':
        session._dispatchMessage(raw);
      case 'error':
        session._dispatchError(raw);
      case 'sessionState':
        final stateStr = raw['state'] as String?;
        final newState = _parseState(stateStr);
        session._dispatchState(newState, raw['errorMessage'] as String?);
        if (newState == AssistantSessionState.stopped ||
            newState == AssistantSessionState.error) {
          if (identical(_active, session)) {
            _active = null;
            _serverEventCtrl.add(AssistantServerEvent(
              type: AssistantServerEventType.sessionStopped,
              sessionId: sessionId,
            ));
          }
        }
      case 'connectionState':
        // 连接状态目前不暴露给 AssistantSession 接口；如需，扩 stateStream / 加 connectionStream。
        break;
    }
  }

  AssistantSessionState _parseState(String? s) => switch (s) {
        'starting' => AssistantSessionState.starting,
        'active' => AssistantSessionState.active,
        'stopping' => AssistantSessionState.stopping,
        'stopped' => AssistantSessionState.stopped,
        'error' => AssistantSessionState.error,
        _ => AssistantSessionState.starting,
      };

  void _checkAlive() {
    if (_disposed) {
      throw StateError('AssistantServer already disposed');
    }
  }
}

class _AssistantSessionImpl extends AssistantSession {
  _AssistantSessionImpl({
    required this.sessionId,
    required this.agentType,
    required this.userLanguage,
    required Future<void> Function() stopHandler,
  })  : _stopHandler = stopHandler,
        startedAtMs = DateTime.now().millisecondsSinceEpoch;

  final Future<void> Function() _stopHandler;

  @override
  final String sessionId;
  @override
  final int startedAtMs;
  @override
  final String agentType;
  @override
  final String userLanguage;

  AssistantSessionState _state = AssistantSessionState.starting;

  final _messageCtrl = StreamController<AssistantMessageEvent>.broadcast();
  final _errorCtrl = StreamController<AssistantErrorEvent>.broadcast();
  final _stateCtrl = StreamController<AssistantSessionState>.broadcast();
  final _latestByRole = <AssistantRole, AssistantMessageEvent>{};
  bool _stopped = false;

  @override
  AssistantSessionState get state => _state;

  @override
  Stream<AssistantMessageEvent> get messages => _messageCtrl.stream;

  @override
  Stream<AssistantErrorEvent> get errors => _errorCtrl.stream;

  @override
  Stream<AssistantSessionState> get stateStream => _stateCtrl.stream;

  @override
  AssistantMessageEvent? latestMessageByRole(AssistantRole role) =>
      _latestByRole[role];

  @override
  Future<void> stop() async {
    if (_stopped) return;
    await _stopHandler();
    // 实际收尾在 sessionState=stopped 事件到达时由 _close 完成。
  }

  // ────────────────── 事件路由（由 server _route 调用） ──────────────────

  void _dispatchMessage(Map raw) {
    if (_messageCtrl.isClosed) return;
    final roleStr = raw['role'] as String? ?? '';
    final stageStr = raw['stage'] as String? ?? '';
    final role = _parseRole(roleStr);
    final stage = _parseStage(stageStr);
    final evt = AssistantMessageEvent(
      sessionId: sessionId,
      role: role,
      stage: stage,
      text: (raw['text'] as String?) ?? '',
      requestId: raw['requestId'] as String?,
    );
    _latestByRole[role] = evt;
    _messageCtrl.add(evt);
  }

  void _dispatchError(Map raw) {
    if (_errorCtrl.isClosed) return;
    _errorCtrl.add(AssistantErrorEvent(
      sessionId: sessionId,
      code: (raw['code'] as String?) ?? 'assistant.unknown',
      message: raw['message'] as String?,
      role: _parseOptionalRole(raw['role'] as String?),
      fatal: (raw['fatal'] as bool?) ?? false,
    ));
  }

  void _dispatchState(AssistantSessionState newState, String? errorMessage) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateCtrl.isClosed) _stateCtrl.add(newState);
    if (newState == AssistantSessionState.stopped ||
        newState == AssistantSessionState.error) {
      _close();
    }
  }

  void _close() {
    if (_stopped) return;
    _stopped = true;
    _messageCtrl.close();
    _errorCtrl.close();
    _stateCtrl.close();
  }

  static AssistantRole _parseRole(String s) => switch (s) {
        'user' => AssistantRole.user,
        'assistant' => AssistantRole.assistant,
        _ => AssistantRole.user,
      };

  static AssistantRole? _parseOptionalRole(String? s) =>
      s == null ? null : _parseRole(s);

  static AssistantMessageStage _parseStage(String s) => switch (s) {
        'partial' => AssistantMessageStage.partial,
        'final' => AssistantMessageStage.finalized,
        _ => AssistantMessageStage.partial,
      };
}
