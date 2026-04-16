// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

/// StsDoubaoPlugin — Doubao realtime Speech-to-Speech (web implementation).
///
/// The native Android/iOS implementations use MethodChannel bridges to native
/// WebSocket + AudioRecord / AudioTrack. On the web we:
///
///  1. Open the ByteDance realtime WebSocket directly in Dart.
///  2. Capture the microphone via `getUserMedia` + `ScriptProcessorNode`, then
///     downsample to 16 kHz mono 16-bit PCM and push frames (event=200) to
///     the server.
///  3. Decode the server's 24 kHz PCM TTS audio chunks into `AudioBuffer`s and
///     schedule them on a single playback `AudioContext` so consecutive chunks
///     play back-to-back without gaps.
///
/// IMPORTANT: the browser WebSocket API does NOT allow custom request headers;
/// it only supports sub-protocols. The ByteDance realtime gateway normally
/// expects `X-Api-*` headers, but it also accepts the same identifiers as URL
/// query parameters (`?resource_id=...&access_key=...&app_key=...&app_id=...
/// &connect_id=...`), which is the approach used here. If the backend rejects
/// query auth, a small proxy (or a Cloudflare Worker) in front of the WS can
/// rewrite the query into proper headers. Document any gateway-side issue in
/// the integration ticket.
///
/// The plugin also implements `sendAudio()` as a no-op: on the web the Dart
/// agent runtime in `agents_server` does not pump PCM to the plugin, so the
/// plugin self-starts mic capture after `SessionStarted`.
class StsDoubaoPlugin implements StsPlugin {
  // ── Protocol constants (mirror the Kotlin companion) ──────────────────────
  static const String _wsUrl =
      'wss://openspeech.bytedance.com/api/v3/realtime/dialogue';
  static const String _fixedResourceId = 'volc.speech.dialog';
  static const String _fixedAppKey = 'PlgvMymc7f3tQnJ6';

  // Header byte 0: version=1, headerSize=1 (4 bytes)
  static const int _headerB0 = 0x11;

  // Message types (upper nibble of byte 1)
  static const int _typeFullClient = 0x10;
  static const int _typeAudioClient = 0x20;
  static const int _typeFullServer = 0x90;
  static const int _typeAudioServer = 0xB0;
  static const int _typeError = 0xF0;

  // Flags (lower nibble of byte 1)
  static const int _flagWithEvent = 0x04;
  static const int _flagNegSequence = 0x02;

  // Serialization (upper nibble of byte 2)
  static const int _serNone = 0x00;
  static const int _serJson = 0x10;

  // Compression (lower nibble of byte 2)
  static const int _compressNone = 0x00; // ignore: unused_field
  static const int _compressGzip = 0x01;

  // Header byte 2 combinations
  static const int _hdr2JsonGzip = _serJson | _compressGzip; // 0x11
  static const int _hdr2RawGzip = _serNone | _compressGzip; // 0x01

  // Event codes — client
  static const int _evtStartConnection = 1;
  static const int _evtFinishConnection = 2;
  static const int _evtStartSession = 100;
  static const int _evtFinishSession = 102;
  static const int _evtSendAudio = 200;

  // Event codes — server
  static const int _evtConnectionStarted = 50;
  static const int _evtConnectionFailed = 51;
  static const int _evtConnectionFinished = 52;
  static const int _evtSessionStarted = 150;
  static const int _evtSessionFinOk = 152;
  static const int _evtSessionFinErr = 153;
  static const int _evtTtsType = 350;
  static const int _evtTtsEnded = 359;
  static const int _evtClearAudio = 450;
  static const int _evtAsrResponse = 451; // ignore: unused_field
  static const int _evtUserQueryEnded = 459; // ignore: unused_field
  static const int _evtChatResponse = 550; // ignore: unused_field
  static const int _evtChatEnded = 559;

  static const Set<int> _noSessionEvents = {
    _evtStartConnection,
    _evtFinishConnection,
  };

  // ── Config ────────────────────────────────────────────────────────────────
  StsConfig? _config;
  String _speaker = 'zh_female_vv_jupiter_bigtts';
  String _systemPrompt =
      '你是一个友好、专业的 AI 语音助手，请用简洁的语言回答用户的问题。';

  // ── Runtime state ─────────────────────────────────────────────────────────
  StreamController<StsEvent>? _controller;
  web.WebSocket? _socket;
  String _remoteSessionId = '';
  bool _isConnected = false;
  bool _isRunning = false;

  Completer<void>? _wsReady;
  Completer<void>? _connectionStarted;
  Completer<void>? _sessionStarted;

  // WebSocket event listener registrations (for removal on dispose).
  JSFunction? _onOpenCb;
  JSFunction? _onMessageCb;
  JSFunction? _onErrorCb;
  JSFunction? _onCloseCb;

  // ── Mic capture ───────────────────────────────────────────────────────────
  web.MediaStream? _micStream;
  JSObject? _micContext; // AudioContext for capture
  JSObject? _micSource; // MediaStreamAudioSourceNode
  JSObject? _micProcessor; // ScriptProcessorNode
  // Retained reference to the onaudioprocess callback so the browser doesn't
  // garbage-collect it while the node is live.
  // ignore: unused_field
  JSFunction? _micProcessCb;
  bool _isAudioRunning = false;
  double _micSampleRate = 48000.0; // filled in from AudioContext

  // Residual sample buffer for 16 kHz downsample (fractional step leftovers).
  Float32List _resampleTail = Float32List(0);

  // ── TTS playback ──────────────────────────────────────────────────────────
  JSObject? _playContext; // AudioContext for output
  double _nextPlayTime = 0.0; // scheduled time for next chunk (context time)
  final List<JSObject> _liveSources = <JSObject>[];

  // ==========================================================================
  // StsPlugin API
  // ==========================================================================

  @override
  Future<void> initialize(StsConfig config) async {
    _config = config;
    if (config.voiceName.isNotEmpty) _speaker = config.voiceName;
    final sp = config.extraParams['systemPrompt'];
    if (sp != null && sp.isNotEmpty) _systemPrompt = sp;
    _controller ??= StreamController<StsEvent>.broadcast();
  }

  @override
  Future<void> startCall() async {
    final cfg = _config;
    if (cfg == null) {
      _emit(const StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.not_initialized',
        errorMessage: 'initialize() must be called before startCall()',
      ));
      return;
    }
    if (cfg.apiKey.isEmpty || cfg.appId.isEmpty) {
      _emit(const StsEvent(
        type: StsEventType.error,
        errorCode: 'auth_failed',
        errorMessage: 'appId or accessToken missing',
      ));
      return;
    }

    _controller ??= StreamController<StsEvent>.broadcast();
    _remoteSessionId = '';
    _isConnected = false;
    _isRunning = true;

    _wsReady = Completer<void>();
    _connectionStarted = Completer<void>();
    _sessionStarted = Completer<void>();

    try {
      _openWebSocket(cfg);

      await _wsReady!.future.timeout(const Duration(seconds: 15));

      // Step 1: StartConnection (no sessionId).
      _sendJsonFrame(_evtStartConnection, '{}');
      await _connectionStarted!.future.timeout(const Duration(seconds: 10));

      // Step 2: StartSession (with sessionId).
      _sendJsonFrame(_evtStartSession, _buildSessionPayload());
      await _sessionStarted!.future.timeout(const Duration(seconds: 10));

      _isConnected = true;
      _emit(const StsEvent(type: StsEventType.connected));

      // On web we self-start mic capture right after SessionStarted.
      await startAudio();
    } on TimeoutException catch (e) {
      _isRunning = false;
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.handshake_timeout',
        errorMessage: 'Handshake timed out: ${e.message}',
      ));
      await _closeSocket(code: 1001, reason: 'handshake timeout');
    } catch (e) {
      _isRunning = false;
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.connect_failed',
        errorMessage: e.toString(),
      ));
      await _closeSocket(code: 1011, reason: 'connect failed');
    }
  }

  /// On the web `sendAudio` is a no-op because the plugin captures the mic
  /// itself via `getUserMedia`. The Dart agent runtime in `agents_server` does
  /// not pump PCM to the plugin on this platform.
  @override
  void sendAudio(List<int> pcmData) {
    // Intentional no-op.
  }

  @override
  Future<void> stopCall() async {
    _isRunning = false;
    _isConnected = false;

    await stopAudio();
    _cancelPlayback();

    // Try graceful shutdown: FinishSession + FinishConnection.
    try {
      if (_remoteSessionId.isNotEmpty) {
        _sendJsonFrame(_evtFinishSession, '{}');
      }
      _sendJsonFrame(_evtFinishConnection, '{}');
    } catch (_) {}

    await _closeSocket(code: 1000, reason: 'stopCall');
    _remoteSessionId = '';
  }

  @override
  Stream<StsEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await stopCall();
    await _closePlaybackContext();
    await _controller?.close();
    _controller = null;
    _config = null;
  }

  // ==========================================================================
  // Mic capture (startAudio / stopAudio)
  // ==========================================================================

  /// Internal helper — begin capturing mic and pushing 16 kHz PCM frames.
  /// Called automatically after SessionStarted; safe to invoke externally if
  /// the caller wants to explicitly control when mic starts.
  Future<void> startAudio() async {
    if (_isAudioRunning) return;
    if (!_isConnected) return;

    try {
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

      // Use the default sample rate; ScriptProcessor will deliver native-rate
      // Float32 buffers and we downsample to 16 kHz in Dart.
      final ctor = (web.window as JSObject)['AudioContext'] ??
          (web.window as JSObject)['webkitAudioContext'];
      if (ctor == null) {
        throw StateError('AudioContext not supported');
      }
      final ctx = (ctor as JSFunction).callAsConstructor<JSObject>();
      _micContext = ctx;
      _micSampleRate = (ctx['sampleRate'] as JSNumber).toDartDouble;
      _resampleTail = Float32List(0);

      final src = ctx.callMethod<JSObject>(
        'createMediaStreamSource'.toJS,
        stream as JSObject,
      );
      _micSource = src;

      // 4096 buffer, 1 in, 1 out — deprecated but universally available. An
      // AudioWorklet approach would require shipping a JS worklet module,
      // which is awkward to bundle from a Flutter plugin package.
      final processor = ctx.callMethod<JSObject>(
        'createScriptProcessor'.toJS,
        4096.toJS,
        1.toJS,
        1.toJS,
      );
      _micProcessor = processor;

      final cb = ((JSObject event) {
        _handleMicBuffer(event);
      }).toJS;
      _micProcessCb = cb;
      processor['onaudioprocess'] = cb;

      src.callMethod('connect'.toJS, processor);
      // ScriptProcessor requires a downstream node to fire onaudioprocess in
      // some browsers; hook it to a muted gain so mic audio is not echoed.
      final gain = ctx.callMethod<JSObject>('createGain'.toJS);
      (gain['gain'] as JSObject)['value'] = 0.toJS;
      processor.callMethod('connect'.toJS, gain);
      gain.callMethod('connect'.toJS, ctx['destination'] as JSObject);

      _isAudioRunning = true;
    } catch (e) {
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'permission_denied',
        errorMessage: 'getUserMedia failed: $e',
      ));
    }
  }

  /// Internal helper — stop mic capture and release audio nodes.
  Future<void> stopAudio() async {
    _isAudioRunning = false;
    try {
      final proc = _micProcessor;
      if (proc != null) {
        proc['onaudioprocess'] = null;
        try {
          proc.callMethod('disconnect'.toJS);
        } catch (_) {}
      }
    } catch (_) {}
    _micProcessor = null;
    _micProcessCb = null;

    try {
      _micSource?.callMethod('disconnect'.toJS);
    } catch (_) {}
    _micSource = null;

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
      final ctx = _micContext;
      if (ctx != null) {
        ctx.callMethod('close'.toJS);
      }
    } catch (_) {}
    _micContext = null;

    _resampleTail = Float32List(0);
  }

  void _handleMicBuffer(JSObject event) {
    if (!_isAudioRunning || !_isConnected) return;
    try {
      final inputBuffer = event['inputBuffer'] as JSObject;
      final channelData = inputBuffer.callMethod<JSObject>(
        'getChannelData'.toJS,
        0.toJS,
      );
      // JS Float32Array — copy into a Dart Float32List.
      final length = (channelData['length'] as JSNumber).toDartInt;
      final floats = Float32List(length);
      for (var i = 0; i < length; i++) {
        floats[i] = (channelData[i.toString()] as JSNumber).toDartDouble;
      }

      // Prepend residual tail samples from last callback for smoother resample.
      Float32List combined;
      if (_resampleTail.isEmpty) {
        combined = floats;
      } else {
        combined = Float32List(_resampleTail.length + floats.length);
        combined.setRange(0, _resampleTail.length, _resampleTail);
        combined.setRange(_resampleTail.length, combined.length, floats);
      }

      final int16 = _downsampleTo16k(combined, _micSampleRate);
      _sendAudioFrame(int16);
    } catch (_) {
      // Swallow per-frame errors — the pump must keep running.
    }
  }

  /// Linear-interpolation downsample from any source rate (typically 48 kHz or
  /// 44.1 kHz in browsers) to 16 kHz, producing Int16 little-endian PCM.
  Uint8List _downsampleTo16k(Float32List input, double srcRate) {
    const dstRate = 16000.0;
    if (input.isEmpty) return Uint8List(0);
    if ((srcRate - dstRate).abs() < 1.0) {
      _resampleTail = Float32List(0);
      return _floatsToInt16LE(input);
    }

    final ratio = srcRate / dstRate; // e.g. 3.0 for 48 kHz → 16 kHz
    final outLen = (input.length / ratio).floor();
    final out = Float32List(outLen);
    for (var i = 0; i < outLen; i++) {
      final srcPos = i * ratio;
      final i0 = srcPos.floor();
      final i1 = math.min(i0 + 1, input.length - 1);
      final frac = srcPos - i0;
      out[i] = input[i0] * (1 - frac) + input[i1] * frac;
    }

    // Keep the fractional tail (samples not consumed) for the next callback.
    final consumed = (outLen * ratio).floor();
    if (consumed < input.length) {
      _resampleTail = Float32List.fromList(input.sublist(consumed));
    } else {
      _resampleTail = Float32List(0);
    }
    return _floatsToInt16LE(out);
  }

  Uint8List _floatsToInt16LE(Float32List floats) {
    final bd = ByteData(floats.length * 2);
    for (var i = 0; i < floats.length; i++) {
      var s = floats[i];
      if (s > 1.0) s = 1.0;
      if (s < -1.0) s = -1.0;
      final v = (s < 0 ? s * 0x8000 : s * 0x7FFF).round();
      bd.setInt16(i * 2, v, Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  // ==========================================================================
  // WebSocket
  // ==========================================================================

  void _openWebSocket(StsConfig cfg) {
    final connectId = _uuid();
    final q = <String, String>{
      'resource_id': _fixedResourceId,
      'access_key': cfg.apiKey,
      'app_key': _fixedAppKey,
      'app_id': cfg.appId,
      'connect_id': connectId,
    };
    final query = q.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final url = '$_wsUrl?$query';

    final ws = web.WebSocket(url);
    ws.binaryType = 'arraybuffer';
    _socket = ws;

    _onOpenCb = ((JSAny _) {
      if (_wsReady != null && !_wsReady!.isCompleted) {
        _wsReady!.complete();
      }
    }).toJS;
    _onMessageCb = ((JSObject event) {
      final data = event['data'];
      if (data.isA<web.Blob>()) {
        // Shouldn't happen because we set binaryType='arraybuffer', but
        // defensively decode via FileReader if it does.
        return;
      }
      final buffer = data as JSObject;
      final uint8 = Uint8List.view(
        (buffer as JSArrayBuffer).toDart,
      );
      try {
        _parseServerFrame(uint8);
      } catch (e) {
        _emit(StsEvent(
          type: StsEventType.error,
          errorCode: 'sts.parse_error',
          errorMessage: e.toString(),
        ));
      }
    }).toJS;
    _onErrorCb = ((JSAny _) {
      final err = 'WebSocket error';
      _completeExceptionally(err);
      if (_isRunning) {
        _emit(const StsEvent(
          type: StsEventType.error,
          errorCode: 'network_error',
          errorMessage: 'WebSocket error',
        ));
      }
    }).toJS;
    _onCloseCb = ((JSObject event) {
      final code = (event['code'] as JSNumber?)?.toDartInt ?? 0;
      final reason = (event['reason'] as JSString?)?.toDart ?? '';
      _completeExceptionally('WebSocket closed $code $reason');
      _isConnected = false;
      if (_controller != null && !_controller!.isClosed) {
        _emit(const StsEvent(type: StsEventType.disconnected));
      }
    }).toJS;

    ws.addEventListener('open', _onOpenCb);
    ws.addEventListener('message', _onMessageCb);
    ws.addEventListener('error', _onErrorCb);
    ws.addEventListener('close', _onCloseCb);
  }

  Future<void> _closeSocket({int code = 1000, String reason = ''}) async {
    final ws = _socket;
    _socket = null;
    if (ws == null) return;
    try {
      if (_onOpenCb != null) ws.removeEventListener('open', _onOpenCb);
      if (_onMessageCb != null) ws.removeEventListener('message', _onMessageCb);
      if (_onErrorCb != null) ws.removeEventListener('error', _onErrorCb);
      if (_onCloseCb != null) ws.removeEventListener('close', _onCloseCb);
    } catch (_) {}
    _onOpenCb = null;
    _onMessageCb = null;
    _onErrorCb = null;
    _onCloseCb = null;
    try {
      ws.close(code, reason);
    } catch (_) {}
  }

  void _completeExceptionally(String msg) {
    for (final c in [_wsReady, _connectionStarted, _sessionStarted]) {
      if (c != null && !c.isCompleted) {
        c.completeExceptionally(StateError(msg));
      }
    }
  }

  // ==========================================================================
  // Frame encoding
  // ==========================================================================

  void _sendJsonFrame(int event, String jsonPayload) {
    final body = _gzip(utf8.encode(jsonPayload));
    final skipSession = _noSessionEvents.contains(event);
    final sidBytes = utf8.encode(_remoteSessionId);

    var size = 4 + 4 + body.length; // header + event(4) + payloadLen(4)
    if (!skipSession) size += 4 + sidBytes.length;

    final bd = ByteData(4 + size);
    var off = 0;
    bd.setUint8(off++, _headerB0);
    bd.setUint8(off++, _typeFullClient | _flagWithEvent);
    bd.setUint8(off++, _hdr2JsonGzip);
    bd.setUint8(off++, 0x00);

    bd.setInt32(off, event, Endian.big);
    off += 4;
    if (!skipSession) {
      bd.setInt32(off, sidBytes.length, Endian.big);
      off += 4;
      for (var i = 0; i < sidBytes.length; i++) {
        bd.setUint8(off + i, sidBytes[i]);
      }
      off += sidBytes.length;
    }
    bd.setInt32(off, body.length, Endian.big);
    off += 4;
    for (var i = 0; i < body.length; i++) {
      bd.setUint8(off + i, body[i]);
    }
    _wsSend(bd.buffer.asUint8List());
  }

  void _sendAudioFrame(Uint8List pcm) {
    if (_socket == null || !_isAudioRunning) return;
    final body = _gzip(pcm);
    final sidBytes = utf8.encode(_remoteSessionId);
    final size = 4 + 4 + sidBytes.length + 4 + body.length;

    final bd = ByteData(4 + size);
    var off = 0;
    bd.setUint8(off++, _headerB0);
    bd.setUint8(off++, _typeAudioClient | _flagWithEvent);
    bd.setUint8(off++, _hdr2RawGzip);
    bd.setUint8(off++, 0x00);

    bd.setInt32(off, _evtSendAudio, Endian.big);
    off += 4;
    bd.setInt32(off, sidBytes.length, Endian.big);
    off += 4;
    for (var i = 0; i < sidBytes.length; i++) {
      bd.setUint8(off + i, sidBytes[i]);
    }
    off += sidBytes.length;
    bd.setInt32(off, body.length, Endian.big);
    off += 4;
    for (var i = 0; i < body.length; i++) {
      bd.setUint8(off + i, body[i]);
    }
    _wsSend(bd.buffer.asUint8List());
  }

  void _wsSend(Uint8List bytes) {
    final ws = _socket;
    if (ws == null) return;
    try {
      // Pass the underlying ArrayBuffer (not a typed-array view) so that the
      // browser sends the exact byte range we want.
      ws.send(bytes.buffer.toJS);
    } catch (_) {}
  }

  // ==========================================================================
  // Frame decoding
  // ==========================================================================

  void _parseServerFrame(Uint8List data) {
    if (data.length < 4) return;
    final b1 = data[1] & 0xFF;
    final b2 = data[2] & 0xFF;

    final msgType = b1 & 0xF0;
    final flags = b1 & 0x0F;
    final compress = b2 & 0x0F;
    final serType = b2 & 0xF0;

    final hasNegSeq = (flags & _flagNegSequence) != 0;
    final hasEvent = (flags & _flagWithEvent) != 0;

    var pos = 4;
    if (hasNegSeq && pos + 4 <= data.length) pos += 4;

    var event = -1;
    if (hasEvent && pos + 4 <= data.length) {
      event = ByteData.sublistView(data, pos, pos + 4).getInt32(0, Endian.big);
      pos += 4;
    }

    switch (msgType) {
      case _typeFullServer:
      case _typeAudioServer:
        if (pos + 4 > data.length) return;
        final sidLen =
            ByteData.sublistView(data, pos, pos + 4).getInt32(0, Endian.big);
        pos += 4;
        if (sidLen > 0) {
          if (pos + sidLen > data.length) return;
          final sid = utf8.decode(data.sublist(pos, pos + sidLen));
          if (_remoteSessionId.isEmpty && sid.isNotEmpty) {
            _remoteSessionId = sid;
          }
          pos += sidLen;
        }

        if (pos + 4 > data.length) return;
        final payloadLen =
            ByteData.sublistView(data, pos, pos + 4).getInt32(0, Endian.big);
        pos += 4;

        Uint8List payload;
        if (payloadLen <= 0 || pos + payloadLen > data.length) {
          payload = Uint8List(0);
        } else {
          payload = data.sublist(pos, pos + payloadLen);
          if (compress == _compressGzip && payload.isNotEmpty) {
            try {
              payload = Uint8List.fromList(GZipDecoder().decodeBytes(payload));
            } catch (_) {
              // Fall through with compressed bytes; likely a server hiccup.
            }
          }
        }

        if (msgType == _typeFullServer) {
          _handleServerEvent(event, payload, serType);
        } else {
          if (payload.isNotEmpty) {
            _schedulePlayback(payload);
            _emit(StsEvent(
              type: StsEventType.audioChunk,
              audioData: payload,
            ));
          }
        }
        break;

      case _typeError:
        String errText;
        if (data.length >= 12) {
          final errCode = ByteData.sublistView(data, 4, 8).getInt32(0, Endian.big);
          final pLen = ByteData.sublistView(data, 8, 12).getInt32(0, Endian.big);
          if (pLen > 0 && 12 + pLen <= data.length) {
            var raw = data.sublist(12, 12 + pLen);
            if (compress == _compressGzip) {
              try {
                raw = Uint8List.fromList(GZipDecoder().decodeBytes(raw));
              } catch (_) {}
            }
            errText = 'code=$errCode ${utf8.decode(raw, allowMalformed: true)}';
          } else {
            errText = 'code=$errCode';
          }
        } else {
          errText = 'unknown';
        }
        _emit(StsEvent(
          type: StsEventType.error,
          errorCode: 'sts.server_error',
          errorMessage: errText,
        ));
        break;

      default:
        // Unknown message type — ignore.
        break;
    }
  }

  void _handleServerEvent(int event, Uint8List payload, int serType) {
    Map<String, dynamic>? json;
    if (serType == _serJson && payload.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(payload, allowMalformed: true));
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
    }

    switch (event) {
      case _evtConnectionStarted:
        _connectionStarted?.completeIfNotCompleted();
        break;
      case _evtConnectionFailed:
        final msg = (json?['message'] as String?) ?? 'connection failed';
        _connectionStarted?.completeExceptionallyIfNotCompleted(
          StateError(msg),
        );
        break;
      case _evtConnectionFinished:
        _emit(const StsEvent(type: StsEventType.disconnected));
        break;
      case _evtSessionStarted:
        _sessionStarted?.completeIfNotCompleted();
        break;
      case _evtSessionFinOk:
      case _evtSessionFinErr:
        // Session closed from the server side — nothing to emit, the outer
        // stopCall()/close flow handles disconnection.
        break;
      case _evtClearAudio:
        // User started speaking: drop any queued TTS audio so the response
        // can be interrupted cleanly. Emit `sentenceDone(text: null)` per the
        // plugin contract for STS interruption.
        _cancelPlayback();
        _emit(const StsEvent(type: StsEventType.sentenceDone));
        break;
      case _evtChatEnded:
        final content = (json?['content'] as String?) ?? '';
        if (content.isNotEmpty) {
          _emit(StsEvent(type: StsEventType.sentenceDone, text: content));
        }
        break;
      case _evtTtsEnded:
      case _evtTtsType:
        // No direct StsEvent; progress is implicit via audioChunk / sentenceDone.
        break;
      default:
        // Other events (ASR partial/final, CHAT_RESPONSE, USER_QUERY_ENDED)
        // are intentionally not surfaced — StsEvent has no corresponding type
        // and the mobile plugin also drops them at this layer.
        break;
    }
  }

  // ==========================================================================
  // TTS playback (24 kHz int16 LE → AudioBuffer, gapless scheduling)
  // ==========================================================================

  void _schedulePlayback(Uint8List pcmInt16Le) {
    try {
      _playContext ??= _createPlayContext();
      final ctx = _playContext!;
      const sampleRate = 24000;
      final frames = pcmInt16Le.length ~/ 2;
      if (frames == 0) return;

      final floats = Float32List(frames);
      final bd = ByteData.sublistView(pcmInt16Le);
      for (var i = 0; i < frames; i++) {
        floats[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
      }

      final buffer = ctx.callMethod<JSObject>(
        'createBuffer'.toJS,
        1.toJS,
        frames.toJS,
        sampleRate.toJS,
      );
      final channel = buffer.callMethod<JSObject>(
        'getChannelData'.toJS,
        0.toJS,
      );
      // Fill the channel data using `set` on the JS Float32Array.
      channel.callMethod('set'.toJS, floats.toJS);

      final source = ctx.callMethod<JSObject>('createBufferSource'.toJS);
      source['buffer'] = buffer;
      source.callMethod('connect'.toJS, ctx['destination'] as JSObject);

      final currentTime = (ctx['currentTime'] as JSNumber).toDartDouble;
      if (_nextPlayTime < currentTime) {
        _nextPlayTime = currentTime;
      }
      source.callMethod('start'.toJS, _nextPlayTime.toJS);
      _nextPlayTime += frames / sampleRate;

      _liveSources.add(source);
      source['onended'] = ((JSAny _) {
        _liveSources.remove(source);
      }).toJS;
    } catch (_) {
      // Playback failure shouldn't kill the dialogue session.
    }
  }

  void _cancelPlayback() {
    for (final src in List<JSObject>.from(_liveSources)) {
      try {
        src.callMethod('stop'.toJS);
      } catch (_) {}
      try {
        src.callMethod('disconnect'.toJS);
      } catch (_) {}
    }
    _liveSources.clear();
    _nextPlayTime = 0.0;
  }

  JSObject _createPlayContext() {
    final ctor = (web.window as JSObject)['AudioContext'] ??
        (web.window as JSObject)['webkitAudioContext'];
    if (ctor == null) {
      throw StateError('AudioContext not supported');
    }
    final ctx = (ctor as JSFunction).callAsConstructor<JSObject>();
    return ctx;
  }

  Future<void> _closePlaybackContext() async {
    _cancelPlayback();
    try {
      _playContext?.callMethod('close'.toJS);
    } catch (_) {}
    _playContext = null;
    _nextPlayTime = 0.0;
  }

  // ==========================================================================
  // Payload helpers
  // ==========================================================================

  String _buildSessionPayload() {
    final payload = <String, dynamic>{
      'asr': {
        'extra': {'end_smooth_window_ms': 1500},
      },
      'tts': {
        'speaker': _speaker,
        'audio_config': {
          'channel': 1,
          'format': 'pcm_s16le',
          'sample_rate': 24000,
        },
      },
      'dialog': {
        'system_role': _systemPrompt,
        'extra': {
          'strict_audit': false,
          'recv_timeout': 10,
          'input_mod': 'audio',
          'model': 'O',
        },
      },
    };
    return jsonEncode(payload);
  }

  Uint8List _gzip(List<int> data) {
    final encoded = GZipEncoder().encode(data);
    return Uint8List.fromList(encoded);
  }

  String _uuid() {
    final rnd = math.Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant 10xx
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-'
        '${h.substring(20)}';
  }

  void _emit(StsEvent e) {
    final c = _controller;
    if (c != null && !c.isClosed) c.add(e);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Small ergonomics extensions on Completer so the event-handling switch reads
// cleanly.
// ──────────────────────────────────────────────────────────────────────────────
extension _CompleterX<T> on Completer<T> {
  void completeIfNotCompleted([T? value]) {
    if (!isCompleted) complete(value as T);
  }

  void completeExceptionallyIfNotCompleted(Object error) {
    if (!isCompleted) completeError(error);
  }
}

extension _VoidCompleterX on Completer<void> {
  void completeExceptionally(Object error) {
    if (!isCompleted) completeError(error);
  }
}
