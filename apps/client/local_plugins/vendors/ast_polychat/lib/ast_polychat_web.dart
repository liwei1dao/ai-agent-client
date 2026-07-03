// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Web-side registrar (Flutter plugin contract). No method channels on web —
/// [AstPolychatPluginWeb] is constructed directly by the web service factory.
class AstPolychatWeb {
  static void registerWith(Registrar registrar) {}
}

/// AstPolychatPluginWeb — PolyChat (VoiTrans) end-to-end Audio-Speech
/// Translation over WebRTC, mirroring the Android
/// [VoitransWebRtcSession] + [AstPolychatService] behaviour.
///
/// DataChannel events (`trans_original` / `trans_translated`) carry a boolean
/// `done` flag — `done=false` is a streaming snapshot of the in-progress
/// segment, `done=true` is the finalised text. This plugin maps that wire
/// protocol onto the AST recognition five-piece lifecycle defined in
/// [AstEvent]:
///
///   recognitionStart → recognizing* → recognized → recognitionDone
///   → recognitionEnd
///
/// Each round shares a single [requestId] across both [AstRole.source] and
/// [AstRole.translated]; the round ends once both roles have emitted
/// `recognized` (or are force-closed by a new `user_speaking`).
class AstPolychatPluginWeb implements AstPlugin {
  // ── Config ────────────────────────────────────────────────────────────────
  AstConfig? _config;
  String _baseUrl = '';
  String _appId = '';
  String _appSecret = '';
  String _agentId = '';

  // ── Runtime state ─────────────────────────────────────────────────────────
  StreamController<AstEvent>? _controller;
  JSObject? _pc;
  JSObject? _dataChannel;
  web.MediaStream? _micStream;
  web.HTMLAudioElement? _remoteAudio;
  Timer? _pingTimer;
  String? _pcId;
  bool _remoteDescriptionSet = false;
  bool _isConnected = false;
  bool _dcOpen = false;
  bool _connectedEmitted = false;
  final List<JSObject> _pendingCandidates = <JSObject>[];

  // ── Recognition round state ───────────────────────────────────────────────
  String? _currentRequestId;
  bool _sourceRoleOpen = false;
  bool _translatedRoleOpen = false;

  JSFunction? _onIceCandidateCb;
  JSFunction? _onIceStateCb;
  JSFunction? _onTrackCb;
  JSFunction? _onDcOpenCb;
  JSFunction? _onDcMessageCb;
  JSFunction? _onDcCloseCb;

  // ==========================================================================
  // AstPlugin API
  // ==========================================================================

  @override
  Future<void> initialize(AstConfig config) async {
    _config = config;
    _appId = config.appId;
    _appSecret = (config.extraParams['appSecret'] ?? '').trim();
    _baseUrl = (config.extraParams['baseUrl'] ?? '').trim();
    while (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
    _agentId = (config.extraParams['agentId'] ?? '').trim();
    _controller ??= StreamController<AstEvent>.broadcast();
  }

  @override
  Future<void> startCall() async {
    if (_config == null) {
      _emit(const AstEvent(
        type: AstEventType.error,
        errorCode: 'ast.not_initialized',
        errorMessage: 'initialize() must be called before startCall()',
      ));
      return;
    }
    if (_baseUrl.isEmpty ||
        _appId.isEmpty ||
        _appSecret.isEmpty ||
        _agentId.isEmpty) {
      _emit(const AstEvent(
        type: AstEventType.error,
        errorCode: 'auth_failed',
        errorMessage:
            'polychat config incomplete (baseUrl/appId/appSecret/agentId)',
      ));
      return;
    }

    _controller ??= StreamController<AstEvent>.broadcast();
    _remoteDescriptionSet = false;
    _isConnected = false;
    _dcOpen = false;
    _connectedEmitted = false;
    _pendingCandidates.clear();
    _resetRoundState();

    try {
      final tokenFuture = _requestConnectToken();

      await _createPeerConnection();
      await _attachLocalMic();
      _createDataChannel();
      final offer = await _createOffer();

      final connectResp = await tokenFuture.timeout(const Duration(seconds: 15));
      final rawConnectUrl = (connectResp['connect_url'] as String?) ?? '';
      if (rawConnectUrl.isEmpty) {
        throw StateError('connect_url missing in token response');
      }
      final connectUrl = rawConnectUrl.startsWith('http://')
          ? rawConnectUrl.replaceFirst('http://', 'https://')
          : rawConnectUrl;
      final token = (connectResp['token'] as String?) ?? '';

      final answer = await _sendOffer(connectUrl, offer, token);
      _pcId = answer['pc_id'] as String?;
      final answerSdp = (answer['sdp'] as String?) ?? '';
      if (_pcId == null || answerSdp.isEmpty) {
        throw StateError('offer response missing pc_id or sdp');
      }

      await _setRemoteDescription(answerSdp);
      _remoteDescriptionSet = true;
      await _flushPendingCandidates();
    } on TimeoutException catch (e) {
      _emit(AstEvent(
        type: AstEventType.error,
        errorCode: 'ast.connect_timeout',
        errorMessage: 'connect timed out: ${e.message}',
      ));
      await _teardown();
    } catch (e) {
      _emit(AstEvent(
        type: AstEventType.error,
        errorCode: 'ast.connect_failed',
        errorMessage: e.toString(),
      ));
      await _teardown();
    }
  }

  /// Browser drives mic capture through the PeerConnection — PCM from Dart
  /// is not used on web.
  @override
  void sendAudio(List<int> pcmData) {
    // Intentional no-op.
  }

  @override
  Future<void> stopCall() async {
    await _teardown();
  }

  @override
  Stream<AstEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await stopCall();
    try {
      await _controller?.close();
    } catch (_) {}
    _controller = null;
    _config = null;
  }

  // ==========================================================================
  // Internal: HTTP signaling
  // ==========================================================================

  Future<Map<String, dynamic>> _requestConnectToken() async {
    final url = Uri.parse('$_baseUrl/open/v1/agents/$_agentId/connect');
    final resp = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'X-App-Id': _appId,
        'X-App-Secret': _appSecret,
      },
      body: '{}',
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError(
        'connect token request failed: ${resp.statusCode} ${resp.body}',
      );
    }
    final parsed = jsonDecode(resp.body);
    if (parsed is! Map<String, dynamic>) {
      throw StateError('connect token response not a JSON object');
    }
    return parsed;
  }

  Future<Map<String, dynamic>> _sendOffer(
    String connectUrl,
    String offerSdp,
    String token,
  ) async {
    final payload = <String, dynamic>{
      'sdp': offerSdp,
      'type': 'offer',
      'request_data': {
        'connect_token': token,
        'agent_id': _agentId,
      },
    };
    final resp = await http.post(
      Uri.parse(connectUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(payload),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw StateError('offer request failed: ${resp.statusCode} ${resp.body}');
    }
    final parsed = jsonDecode(resp.body);
    if (parsed is! Map<String, dynamic>) {
      throw StateError('offer response not a JSON object');
    }
    return parsed;
  }

  Future<void> _sendIceCandidates(List<JSObject> candidates) async {
    final pcId = _pcId;
    if (pcId == null || candidates.isEmpty) return;
    final list = <Map<String, dynamic>>[];
    for (final c in candidates) {
      list.add({
        'candidate': (c['candidate'] as JSString?)?.toDart ?? '',
        'sdp_mid': (c['sdpMid'] as JSString?)?.toDart,
        'sdp_mline_index': (c['sdpMLineIndex'] as JSNumber?)?.toDartInt,
      });
    }
    final payload = jsonEncode({'pc_id': pcId, 'candidates': list});
    try {
      await http.patch(
        Uri.parse('$_baseUrl/api/offer'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: payload,
      );
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> _flushPendingCandidates() async {
    if (_pendingCandidates.isEmpty) return;
    final toSend = List<JSObject>.from(_pendingCandidates);
    _pendingCandidates.clear();
    await _sendIceCandidates(toSend);
  }

  // ==========================================================================
  // Internal: WebRTC
  // ==========================================================================

  Future<void> _createPeerConnection() async {
    final rtcCtor = (web.window as JSObject)['RTCPeerConnection'];
    if (rtcCtor == null) {
      throw StateError('RTCPeerConnection not supported by this browser');
    }
    final cfg = _toJSObject(<String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.miwifi.com:3478'},
        {'urls': 'stun:stun.chat.bilibili.com:3478'},
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    final pc = (rtcCtor as JSFunction).callAsConstructor<JSObject>(cfg);
    _pc = pc;

    _onIceCandidateCb = ((JSObject event) {
      final candidate = event['candidate'] as JSObject?;
      if (candidate == null) return;
      final sdp = (candidate['candidate'] as JSString?)?.toDart ?? '';
      if (sdp.isEmpty) return;
      if (_remoteDescriptionSet) {
        _sendIceCandidates([candidate]);
      } else {
        _pendingCandidates.add(candidate);
      }
    }).toJS;
    pc['onicecandidate'] = _onIceCandidateCb;

    _onIceStateCb = ((JSAny _) {
      final state = (pc['iceConnectionState'] as JSString?)?.toDart ?? '';
      switch (state) {
        case 'connected':
        case 'completed':
          _isConnected = true;
          _maybeEmitConnected();
          break;
        case 'disconnected':
        case 'failed':
        case 'closed':
          if (!(_controller?.isClosed ?? true)) {
            _emit(const AstEvent(type: AstEventType.disconnected));
          }
          break;
      }
    }).toJS;
    pc['oniceconnectionstatechange'] = _onIceStateCb;

    _onTrackCb = ((JSObject event) {
      final streams = event['streams'] as JSObject?;
      if (streams == null) return;
      final len = (streams['length'] as JSNumber?)?.toDartInt ?? 0;
      if (len == 0) return;
      _attachRemoteAudio(streams[0.toString()] as JSObject);
    }).toJS;
    pc['ontrack'] = _onTrackCb;
  }

  void _createDataChannel() {
    final pc = _pc;
    if (pc == null) return;
    final init = _toJSObject(<String, dynamic>{'ordered': true});
    final dc = pc.callMethod<JSObject>(
      'createDataChannel'.toJS,
      'events'.toJS,
      init,
    );
    _setupDataChannel(dc);
  }

  void _setupDataChannel(JSObject dc) {
    _dataChannel = dc;

    _onDcOpenCb = ((JSAny _) {
      _dcOpen = true;
      _startPingHeartbeat();
      _maybeEmitConnected();
    }).toJS;
    dc['onopen'] = _onDcOpenCb;

    _onDcMessageCb = ((JSObject event) {
      final data = event['data'];
      if (data == null) return;
      if (!data.isA<JSString>()) return;
      final text = (data as JSString).toDart;
      if (text.isEmpty) return;
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          _handleDataChannelMessage(parsed);
        }
      } catch (_) {}
    }).toJS;
    dc['onmessage'] = _onDcMessageCb;

    _onDcCloseCb = ((JSAny _) {
      _dcOpen = false;
      _stopPingHeartbeat();
    }).toJS;
    dc['onclose'] = _onDcCloseCb;
  }

  Future<void> _attachLocalMic() async {
    final md = web.window.navigator.mediaDevices;
    final constraints = web.MediaStreamConstraints(
      audio: web.MediaTrackConstraints(
        echoCancellation: true.toJS,
        noiseSuppression: true.toJS,
        autoGainControl: true.toJS,
        channelCount: 1.toJS,
      ) as JSAny,
    );
    final stream = await md.getUserMedia(constraints).toDart;
    _micStream = stream;
    final pc = _pc!;
    final tracks = stream.getAudioTracks().toDart;
    for (final t in tracks) {
      pc.callMethod<JSAny?>('addTrack'.toJS, t as JSObject, stream as JSObject);
    }
  }

  void _attachRemoteAudio(JSObject stream) {
    try {
      final audio = web.document.createElement('audio') as web.HTMLAudioElement;
      audio.autoplay = true;
      (audio as JSObject)['srcObject'] = stream;
      audio.style.display = 'none';
      web.document.body?.append(audio as JSAny);
      _remoteAudio = audio;
    } catch (_) {}
  }

  Future<String> _createOffer() async {
    final pc = _pc!;
    final constraints = _toJSObject(<String, dynamic>{
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    final offerPromise = pc.callMethod<JSAny>('createOffer'.toJS, constraints);
    final offer = await (offerPromise as JSPromise<JSObject>).toDart;
    final setLocalPromise =
        pc.callMethod<JSAny>('setLocalDescription'.toJS, offer);
    await (setLocalPromise as JSPromise).toDart;
    return (offer['sdp'] as JSString).toDart;
  }

  Future<void> _setRemoteDescription(String sdp) async {
    final pc = _pc!;
    final desc = _toJSObject(<String, dynamic>{'type': 'answer', 'sdp': sdp});
    final p = pc.callMethod<JSAny>('setRemoteDescription'.toJS, desc);
    await (p as JSPromise).toDart;
  }

  // ==========================================================================
  // Internal: DataChannel routing → AST recognition five-piece lifecycle
  // ==========================================================================

  void _handleDataChannelMessage(Map<String, dynamic> json) {
    final type = (json['type'] as String?) ?? '';
    switch (type) {
      case 'user_speaking':
        // New utterance starts — force-end any in-flight round (e.g. previous
        // round's translated stream never reached done=true), then open the
        // source role to mark the new round.
        _beginRound(force: true);
        _openRole(AstRole.source);
        break;

      case 'trans_original':
        _beginRound();
        _openRole(AstRole.source);
        final text = (json['text'] as String?) ?? '';
        final done = (json['done'] as bool?) ?? false;
        if (text.isNotEmpty) {
          if (done) {
            _emitRoleText(AstRole.source, AstEventType.recognized, text);
            _closeRole(AstRole.source);
            _maybeEndRound();
          } else {
            _emitRoleText(AstRole.source, AstEventType.recognizing, text);
          }
        }
        break;

      case 'trans_translated':
        _beginRound();
        _openRole(AstRole.translated);
        final text = (json['text'] as String?) ?? '';
        final done = (json['done'] as bool?) ?? false;
        if (text.isEmpty) break;
        if (done) {
          _emitRoleText(AstRole.translated, AstEventType.recognized, text);
          _closeRole(AstRole.translated);
          _maybeEndRound();
        } else {
          _emitRoleText(AstRole.translated, AstEventType.recognizing, text);
        }
        break;

      case 'error':
        final message = (json['message'] as String?) ?? 'Unknown error';
        final fatal = (json['fatal'] as bool?) ?? false;
        _emit(AstEvent(
          type: fatal ? AstEventType.error : AstEventType.recognitionError,
          requestId: _currentRequestId,
          errorCode: fatal ? 'ast.fatal' : 'ast.error',
          errorMessage: message,
        ));
        break;

      case 'session_state':
      case 'mcp_tool_call':
      case 'mcp_tool_result':
      case 'disconnect_warning':
        // Not surfaced through AstEvent.
        break;

      default:
        break;
    }
  }

  // ==========================================================================
  // Internal: recognition round state machine
  // ==========================================================================

  /// Start a new round if none is active. Pass `force=true` to implicitly end
  /// the previous round first (user re-opens mic mid-translation).
  void _beginRound({bool force = false}) {
    if (_currentRequestId != null) {
      if (!force) return;
      if (_sourceRoleOpen) _closeRole(AstRole.source);
      if (_translatedRoleOpen) _closeRole(AstRole.translated);
      _endRound();
    }
    _currentRequestId = _newRequestId();
  }

  void _openRole(AstRole role) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    if (role == AstRole.source && !_sourceRoleOpen) {
      _sourceRoleOpen = true;
      _emit(AstEvent(
        type: AstEventType.recognitionStart,
        role: role,
        requestId: requestId,
      ));
    } else if (role == AstRole.translated && !_translatedRoleOpen) {
      _translatedRoleOpen = true;
      _emit(AstEvent(
        type: AstEventType.recognitionStart,
        role: role,
        requestId: requestId,
      ));
    }
  }

  void _closeRole(AstRole role) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    if (role == AstRole.source && _sourceRoleOpen) {
      _sourceRoleOpen = false;
      _emit(AstEvent(
        type: AstEventType.recognitionDone,
        role: role,
        requestId: requestId,
      ));
    } else if (role == AstRole.translated && _translatedRoleOpen) {
      _translatedRoleOpen = false;
      _emit(AstEvent(
        type: AstEventType.recognitionDone,
        role: role,
        requestId: requestId,
      ));
    }
  }

  /// End the round once both roles are closed.
  void _maybeEndRound() {
    if (_sourceRoleOpen || _translatedRoleOpen) return;
    if (_currentRequestId == null) return;
    _endRound();
  }

  void _endRound() {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    _emit(AstEvent(
      type: AstEventType.recognitionEnd,
      requestId: requestId,
    ));
    _resetRoundState();
  }

  void _emitRoleText(AstRole role, AstEventType type, String text) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    _emit(AstEvent(
      type: type,
      role: role,
      requestId: requestId,
      text: text,
    ));
  }

  void _resetRoundState() {
    _currentRequestId = null;
    _sourceRoleOpen = false;
    _translatedRoleOpen = false;
  }

  String _newRequestId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final r = math.Random().nextInt(1 << 30).toRadixString(36).padLeft(6, '0');
    return 'ast_polychat_${ms}_$r';
  }

  // ==========================================================================
  // Internal: heartbeat + teardown
  // ==========================================================================

  void _maybeEmitConnected() {
    if (_connectedEmitted) return;
    if (_isConnected && _dcOpen) {
      _connectedEmitted = true;
      _emit(const AstEvent(type: AstEventType.connected));
    }
  }

  void _startPingHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final dc = _dataChannel;
      if (dc == null) return;
      final state = (dc['readyState'] as JSString?)?.toDart ?? '';
      if (state != 'open') return;
      try {
        dc.callMethod<JSAny?>('send'.toJS, 'ping'.toJS);
      } catch (_) {}
    });
  }

  void _stopPingHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  Future<void> _teardown() async {
    _stopPingHeartbeat();
    _isConnected = false;
    _dcOpen = false;
    _connectedEmitted = false;

    // Force-close any in-flight round so consumers don't see a dangling
    // recognitionStart without its matching End.
    if (_currentRequestId != null) {
      if (_sourceRoleOpen) _closeRole(AstRole.source);
      if (_translatedRoleOpen) _closeRole(AstRole.translated);
      _endRound();
    }

    final pcId = _pcId;
    _pcId = null;
    if (pcId != null && _baseUrl.isNotEmpty) {
      try {
        final encoded = Uri.encodeComponent(pcId);
        await http
            .delete(Uri.parse('$_baseUrl/api/sessions/$encoded'))
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    try {
      final dc = _dataChannel;
      if (dc != null) {
        dc['onopen'] = null;
        dc['onmessage'] = null;
        dc['onclose'] = null;
        dc.callMethod<JSAny?>('close'.toJS);
      }
    } catch (_) {}
    _dataChannel = null;
    _onDcOpenCb = null;
    _onDcMessageCb = null;
    _onDcCloseCb = null;

    try {
      final pc = _pc;
      if (pc != null) {
        pc['onicecandidate'] = null;
        pc['oniceconnectionstatechange'] = null;
        pc['ontrack'] = null;
        pc.callMethod<JSAny?>('close'.toJS);
      }
    } catch (_) {}
    _pc = null;
    _onIceCandidateCb = null;
    _onIceStateCb = null;
    _onTrackCb = null;

    try {
      final stream = _micStream;
      if (stream != null) {
        final tracks = stream.getTracks().toDart;
        for (final t in tracks) {
          try {
            t.stop();
          } catch (_) {}
        }
      }
    } catch (_) {}
    _micStream = null;

    try {
      final audio = _remoteAudio;
      if (audio != null) {
        (audio as JSObject)['srcObject'] = null;
        audio.remove();
      }
    } catch (_) {}
    _remoteAudio = null;

    if (_controller != null && !_controller!.isClosed) {
      _emit(const AstEvent(type: AstEventType.disconnected));
    }
  }

  // ==========================================================================
  // Internal: helpers
  // ==========================================================================

  void _emit(AstEvent e) {
    final c = _controller;
    if (c != null && !c.isClosed) c.add(e);
  }

  JSAny? _toJSAny(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value.toJS;
    if (value is int) return value.toJS;
    if (value is double) return value.toJS;
    if (value is String) return value.toJS;
    if (value is Map) {
      final obj = JSObject();
      value.forEach((k, v) {
        obj[k.toString()] = _toJSAny(v);
      });
      return obj;
    }
    if (value is List) {
      final arr = JSArray<JSAny?>();
      for (var i = 0; i < value.length; i++) {
        arr[i] = _toJSAny(value[i]);
      }
      return arr;
    }
    return null;
  }

  JSObject _toJSObject(Map<String, dynamic> map) => _toJSAny(map) as JSObject;
}
