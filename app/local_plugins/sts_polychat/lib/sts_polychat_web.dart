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
/// [StsPolychatPluginWeb] is constructed directly by [WebServiceFactory].
class StsPolychatWeb {
  static void registerWith(Registrar registrar) {}
}

/// StsPolychatPluginWeb — PolyChat (VoiTrans) end-to-end Speech-to-Speech over
/// WebRTC on the web, mirroring the Android [VoitransWebRtcSession] +
/// [StsPolychatService] behaviour.
///
/// Event mapping (polychat DataChannel → [StsEvent]) follows the identification
/// lifecycle defined in [ai_plugin_interface/CLAUDE.md §5]:
///
/// | DC frame | StsEvent |
/// |---|---|
/// | `user_speaking` | `recognitionStart(role=user, requestId=新)` |
/// | `user_transcription` partial | `recognizing(role=user, text=快照)` |
/// | `user_transcription` done=true | `recognized(role=user)` + `recognitionDone(role=user)` |
/// | `bot_response_start` | `recognitionStart(role=bot)`（若 requestId 缺省则本地生成） |
/// | `bot_response` done=false | `recognizing(role=bot, text=服务端快照)` |
/// | `bot_response` done=true | `recognized(role=bot)` + `recognitionDone(role=bot)` |
/// | `ai_speaking` | `playbackStart(role=bot)` |
/// | `ai_stopped` | `playbackEnd(role=bot)` |
/// | `ai_response_done` | `recognitionEnd`（回合关闭） |
///
/// polychat 的 `bot_response.text` 本身就是**本句累计快照**（不是增量），因此
/// 插件内部不做任何累加——直接透传。上层适配器若需要增量可自行基于前一帧做
/// 差分。
///
/// Config sourcing (see [WebConfigParser.parseSts] in agents_server):
///   - `appId`      ← `StsConfig.appId`
///   - `appSecret`  ← `StsConfig.extraParams['appSecret']`
///   - `baseUrl`    ← `StsConfig.extraParams['baseUrl']`
///   - `agentId`    ← `StsConfig.extraParams['agentId']`
class StsPolychatPluginWeb implements StsPlugin {
  // ── Config ────────────────────────────────────────────────────────────────
  StsConfig? _config;
  String _baseUrl = '';
  String _appId = '';
  String _appSecret = '';
  String _agentId = '';

  // ── Runtime state ─────────────────────────────────────────────────────────
  StreamController<StsEvent>? _controller;
  JSObject? _pc; // RTCPeerConnection
  JSObject? _dataChannel; // RTCDataChannel "events"
  web.MediaStream? _micStream;
  web.HTMLAudioElement? _remoteAudio;
  Timer? _pingTimer;
  String? _pcId;
  bool _remoteDescriptionSet = false;
  bool _isConnected = false; // ICE connected
  bool _dcOpen = false;
  bool _connectedEmitted = false;
  final List<JSObject> _pendingCandidates = <JSObject>[];

  // ── Recognition round state ───────────────────────────────────────────────
  /// Current Q&A round id — generated on the first frame of a round and kept
  /// until `recognitionEnd` is emitted.
  String? _currentRequestId;

  /// Per-role open state within the current round. Used to know whether a
  /// `recognitionStart` is still missing and to detect when the round can be
  /// closed.
  bool _userRoleOpen = false;
  bool _botRoleOpen = false;

  /// Whether a bot playback window is currently reported as active
  /// (`playbackStart` emitted, `playbackEnd` pending).
  bool _botPlaybackOpen = false;

  // Retained JS callbacks so the browser does not GC them while the
  // RTCPeerConnection / DataChannel are alive.
  JSFunction? _onIceCandidateCb;
  JSFunction? _onIceStateCb;
  JSFunction? _onTrackCb;
  JSFunction? _onDcOpenCb;
  JSFunction? _onDcMessageCb;
  JSFunction? _onDcCloseCb;

  // ==========================================================================
  // StsPlugin API
  // ==========================================================================

  @override
  Future<void> initialize(StsConfig config) async {
    _config = config;
    _appId = config.appId;
    _appSecret = (config.extraParams['appSecret'] ?? '').trim();
    _baseUrl = (config.extraParams['baseUrl'] ?? '').trim();
    while (_baseUrl.endsWith('/')) {
      _baseUrl = _baseUrl.substring(0, _baseUrl.length - 1);
    }
    _agentId = (config.extraParams['agentId'] ?? '').trim();
    _controller ??= StreamController<StsEvent>.broadcast();
  }

  @override
  Future<void> startCall() async {
    if (_config == null) {
      _emit(const StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.not_initialized',
        errorMessage: 'initialize() must be called before startCall()',
      ));
      return;
    }
    if (_baseUrl.isEmpty ||
        _appId.isEmpty ||
        _appSecret.isEmpty ||
        _agentId.isEmpty) {
      _emit(const StsEvent(
        type: StsEventType.error,
        errorCode: 'auth_failed',
        errorMessage:
            'polychat config incomplete (baseUrl/appId/appSecret/agentId)',
      ));
      return;
    }

    _controller ??= StreamController<StsEvent>.broadcast();
    _remoteDescriptionSet = false;
    _isConnected = false;
    _dcOpen = false;
    _connectedEmitted = false;
    _pendingCandidates.clear();
    _resetRoundState();

    try {
      // 1. Request connect token + capture mic in parallel with PC setup.
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

      // 2. Send SDP offer to server → receive answer + pc_id.
      final answer = await _sendOffer(connectUrl, offer, token);
      _pcId = answer['pc_id'] as String?;
      final answerSdp = (answer['sdp'] as String?) ?? '';
      if (_pcId == null || answerSdp.isEmpty) {
        throw StateError('offer response missing pc_id or sdp');
      }

      // 3. Apply remote description.
      await _setRemoteDescription(answerSdp);
      _remoteDescriptionSet = true;

      // 4. Flush any ICE candidates we gathered before remoteDesc was set.
      await _flushPendingCandidates();
    } on TimeoutException catch (e) {
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.connect_timeout',
        errorMessage: 'connect timed out: ${e.message}',
      ));
      await _teardown();
    } catch (e) {
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.connect_failed',
        errorMessage: e.toString(),
      ));
      await _teardown();
    }
  }

  /// On the web the browser drives mic capture + encoding on the remote
  /// `RTCPeerConnection`. PCM frames from the Dart agent runtime are not used.
  @override
  void sendAudio(List<int> pcmData) {
    // Intentional no-op.
  }

  @override
  Future<void> stopCall() async {
    await _teardown();
  }

  @override
  Stream<StsEvent> get eventStream =>
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
        'sdp_mline_index':
            (c['sdpMLineIndex'] as JSNumber?)?.toDartInt,
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
      // Non-fatal — ICE negotiation may succeed without these trickles.
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
    final iceServers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.miwifi.com:3478'},
      {'urls': 'stun:stun.chat.bilibili.com:3478'},
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    final cfg = _toJSObject(<String, dynamic>{
      'iceServers': iceServers,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    final pc = (rtcCtor as JSFunction).callAsConstructor<JSObject>(cfg);
    _pc = pc;

    _onIceCandidateCb = ((JSObject event) {
      // Browsers fire one final event with candidate=null once gathering
      // completes — skip that.
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
            _emit(const StsEvent(type: StsEventType.disconnected));
          }
          break;
      }
    }).toJS;
    pc['oniceconnectionstatechange'] = _onIceStateCb;

    _onTrackCb = ((JSObject event) {
      final streams = event['streams'];
      if (streams == null) return;
      final streamsObj = streams as JSObject;
      final len = (streamsObj['length'] as JSNumber?)?.toDartInt ?? 0;
      if (len == 0) return;
      final stream = streamsObj[0.toString()] as JSObject;
      _attachRemoteAudio(stream);
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
      String text;
      if (data.isA<JSString>()) {
        text = (data as JSString).toDart;
      } else {
        // Binary on this channel would be anomalous — skip.
        return;
      }
      if (text.isEmpty) return;
      try {
        final parsed = jsonDecode(text);
        if (parsed is Map<String, dynamic>) {
          _handleDataChannelMessage(parsed);
        }
      } catch (_) {
        // Ignore unparseable frames.
      }
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
    web.MediaStream stream;
    try {
      stream = await md.getUserMedia(constraints).toDart;
    } catch (e) {
      throw StateError('getUserMedia failed: $e');
    }
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
      // `srcObject` is not typed on the current `web` bindings — set via JS.
      (audio as JSObject)['srcObject'] = stream;
      audio.style.display = 'none';
      web.document.body?.append(audio as JSAny);
      _remoteAudio = audio;
    } catch (_) {
      // Non-fatal — no remote audio playback, but DataChannel still works.
    }
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
    final desc = _toJSObject(<String, dynamic>{
      'type': 'answer',
      'sdp': sdp,
    });
    final p = pc.callMethod<JSAny>('setRemoteDescription'.toJS, desc);
    await (p as JSPromise).toDart;
  }

  // ==========================================================================
  // Internal: DataChannel event routing (mirrors StsPolychatService.kt)
  // ==========================================================================

  void _handleDataChannelMessage(Map<String, dynamic> json) {
    final type = (json['type'] as String?) ?? '';
    switch (type) {
      case 'user_speaking':
        _beginRound(force: true);
        _openRole(StsRole.user);
        break;

      case 'user_transcription':
        _beginRound();
        _openRole(StsRole.user);
        final text = (json['text'] as String?) ?? '';
        final done = (json['done'] as bool?) ?? false;
        if (text.isNotEmpty) {
          if (done) {
            _emitRoleText(StsRole.user, StsEventType.recognized, text);
            _closeRole(StsRole.user);
          } else {
            _emitRoleText(StsRole.user, StsEventType.recognizing, text);
          }
        }
        break;

      case 'bot_response_start':
        _beginRound();
        // If user side was still open (no final user_transcription), close it
        // implicitly so the lifecycle stays balanced.
        if (_userRoleOpen) {
          _closeRole(StsRole.user);
        }
        _openRole(StsRole.bot);
        break;

      case 'bot_response':
        _beginRound();
        _openRole(StsRole.bot);
        final text = (json['text'] as String?) ?? '';
        final done = (json['done'] as bool?) ?? false;
        if (text.isEmpty) break;
        if (done) {
          // polychat sends the full cumulative text on done=true.
          _emitRoleText(StsRole.bot, StsEventType.recognized, text);
          _closeRole(StsRole.bot);
        } else {
          // polychat's partial frames already carry the cumulative snapshot —
          // pass through as recognizing.text without local accumulation.
          _emitRoleText(StsRole.bot, StsEventType.recognizing, text);
        }
        break;

      case 'ai_speaking':
        _beginRound();
        if (!_botPlaybackOpen) {
          _emit(StsEvent(
            type: StsEventType.playbackStart,
            role: StsRole.bot,
            requestId: _currentRequestId,
          ));
          _botPlaybackOpen = true;
        }
        break;

      case 'ai_stopped':
        if (_botPlaybackOpen) {
          _emit(StsEvent(
            type: StsEventType.playbackEnd,
            role: StsRole.bot,
            requestId: _currentRequestId,
          ));
          _botPlaybackOpen = false;
        }
        break;

      case 'ai_response_done':
        // Round closes here. Force-close any still-open roles and playback.
        if (_userRoleOpen) _closeRole(StsRole.user);
        if (_botRoleOpen) _closeRole(StsRole.bot);
        if (_botPlaybackOpen) {
          _emit(StsEvent(
            type: StsEventType.playbackEnd,
            role: StsRole.bot,
            requestId: _currentRequestId,
          ));
          _botPlaybackOpen = false;
        }
        _endRound();
        break;

      case 'error':
        final message = (json['message'] as String?) ?? 'Unknown error';
        final fatal = (json['fatal'] as bool?) ?? false;
        _emit(StsEvent(
          type: StsEventType.error,
          requestId: _currentRequestId,
          errorCode: fatal ? 'sts.fatal' : 'sts.error',
          errorMessage: message,
        ));
        break;

      case 'session_state':
      case 'mcp_tool_call':
      case 'mcp_tool_result':
      case 'disconnect_warning':
        // No-op: state transitions handled by agent_sts_chat, not surfaced
        // through StsEvent.
        break;

      default:
        break;
    }
  }

  // ==========================================================================
  // Internal: recognition round state machine
  // ==========================================================================

  /// Start a new round if none is active. Pass `force=true` to implicitly end
  /// the previous round first (user interrupted mid-playback).
  void _beginRound({bool force = false}) {
    if (_currentRequestId != null) {
      if (!force) return;
      // Force-end the previous round before starting a new one.
      if (_userRoleOpen) _closeRole(StsRole.user);
      if (_botRoleOpen) _closeRole(StsRole.bot);
      if (_botPlaybackOpen) {
        _emit(StsEvent(
          type: StsEventType.playbackEnd,
          role: StsRole.bot,
          requestId: _currentRequestId,
          interrupted: true,
        ));
        _botPlaybackOpen = false;
      }
      _endRound();
    }
    _currentRequestId = _newRequestId();
  }

  void _openRole(StsRole role) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    if (role == StsRole.user && !_userRoleOpen) {
      _userRoleOpen = true;
      _emit(StsEvent(
        type: StsEventType.recognitionStart,
        role: role,
        requestId: requestId,
      ));
    } else if (role == StsRole.bot && !_botRoleOpen) {
      _botRoleOpen = true;
      _emit(StsEvent(
        type: StsEventType.recognitionStart,
        role: role,
        requestId: requestId,
      ));
    }
  }

  void _closeRole(StsRole role) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    if (role == StsRole.user && _userRoleOpen) {
      _userRoleOpen = false;
      _emit(StsEvent(
        type: StsEventType.recognitionDone,
        role: role,
        requestId: requestId,
      ));
    } else if (role == StsRole.bot && _botRoleOpen) {
      _botRoleOpen = false;
      _emit(StsEvent(
        type: StsEventType.recognitionDone,
        role: role,
        requestId: requestId,
      ));
    }
  }

  void _endRound() {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    _emit(StsEvent(
      type: StsEventType.recognitionEnd,
      requestId: requestId,
    ));
    _resetRoundState();
  }

  void _emitRoleText(StsRole role, StsEventType type, String text) {
    final requestId = _currentRequestId;
    if (requestId == null) return;
    _emit(StsEvent(
      type: type,
      role: role,
      requestId: requestId,
      text: text,
    ));
  }

  void _resetRoundState() {
    _currentRequestId = null;
    _userRoleOpen = false;
    _botRoleOpen = false;
    _botPlaybackOpen = false;
  }

  String _newRequestId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final r = math.Random().nextInt(1 << 30).toRadixString(36).padLeft(6, '0');
    return 'sts_polychat_${ms}_$r';
  }

  // ==========================================================================
  // Internal: heartbeat + teardown
  // ==========================================================================

  void _maybeEmitConnected() {
    if (_connectedEmitted) return;
    if (_isConnected && _dcOpen) {
      _connectedEmitted = true;
      _emit(const StsEvent(type: StsEventType.connected));
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

    // Force-close any in-flight round so consumers see a clean lifecycle.
    if (_currentRequestId != null) {
      if (_userRoleOpen) _closeRole(StsRole.user);
      if (_botRoleOpen) _closeRole(StsRole.bot);
      if (_botPlaybackOpen) {
        _emit(StsEvent(
          type: StsEventType.playbackEnd,
          role: StsRole.bot,
          requestId: _currentRequestId,
          interrupted: true,
        ));
        _botPlaybackOpen = false;
      }
      _endRound();
    }

    // Ask the server to release the session — best-effort.
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
      _emit(const StsEvent(type: StsEventType.disconnected));
    }
  }

  // ==========================================================================
  // Internal: helpers
  // ==========================================================================

  void _emit(StsEvent e) {
    final c = _controller;
    if (c != null && !c.isClosed) c.add(e);
  }

  /// Converts a plain Dart `Map`/`List`/scalar tree into a JS object usable
  /// directly by WebRTC constructors. We can't use `jsify()` from `dart:js`
  /// with the new interop, so walk the tree explicitly.
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

  JSObject _toJSObject(Map<String, dynamic> map) =>
      _toJSAny(map) as JSObject;
}
