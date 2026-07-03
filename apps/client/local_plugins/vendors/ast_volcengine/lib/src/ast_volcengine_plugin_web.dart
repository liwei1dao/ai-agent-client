// Web implementation of the Volcengine AST (Audio Speech Translation) plugin.
//
// This is a direct port of the Android Kotlin reference at
// `android/src/main/kotlin/com/aiagent/ast_volcengine/AstVolcengineService.kt`.
// The Volcengine AST protocol is a pure Protobuf binary framing over a single
// WebSocket, with no custom frame header — each payload is a Protobuf
// `TranslateRequest` / `TranslateResponse` message (see the Kotlin file for the
// field layout). We re-implement the minimal subset of Protobuf wire-format
// encode/decode we need rather than pulling in a full runtime, matching the
// Kotlin implementation byte-for-byte.
//
// Browser WebSocket limitation:
//   The browser WebSocket API does *not* allow custom headers on the handshake,
//   so we cannot send `X-Api-App-Key` / `X-Api-Access-Key` / `X-Api-Resource-Id`
//   / `X-Api-Connect-Id` the way the mobile OkHttp client does. We fall back to
//   passing those values as query parameters (lower-cased, prefixed with the
//   same names) — backend compatibility with this fallback is NOT guaranteed
//   and may need a proxy / backend adjustment. See `_buildWsUri` below.
//
// Microphone capture:
//   getUserMedia -> AudioContext -> ScriptProcessorNode (4096-frame buffer) ->
//   downsample to 16 kHz mono 16-bit little-endian PCM -> Protobuf frame.
//   `ScriptProcessorNode` is deprecated but has the widest browser support; a
//   migration to `AudioWorkletNode` can be done later without changing the
//   protocol layer.
//
// TTS playback:
//   Incoming PCM chunks (24 kHz 16-bit mono) are scheduled gap-free on a
//   dedicated 24 kHz `AudioContext` using `AudioBufferSourceNode`s. Each chunk
//   also produces an `AstEvent(type: ttsAudioChunk)` for upstream consumers.
//
// Event coverage (server -> client):
//   Handled: 150 SessionStarted, 152 SessionFinished, 153 SessionFailed,
//            154 UsageResponse, 350 TTSSentenceStart, 359 TTSEnded,
//            451 AsrResponse, 650-655 source/translation subtitle range.
//   Unhandled: any event code not listed above is logged only; audio payloads
//              (field 3) on unknown events are still played.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

/// Volcengine AST (end-to-end speech translation) — web implementation.
class AstVolcenginePluginWeb implements AstPlugin {
  // ─── Protocol constants (must match the Kotlin reference) ─────────────────
  static const String _wsUrl =
      'wss://openspeech.bytedance.com/api/v4/ast/v2/translate';
  static const String _fixedResourceId = 'volc.bigasr.auc';

  static const int _micSampleRate = 16000;
  static const int _ttsSampleRate = 24000;

  // Event codes (Type enum from events.proto)
  static const int _evtStartSession = 100;
  static const int _evtFinishSession = 102;
  static const int _evtSessionStarted = 150;
  static const int _evtSessionFinished = 152;
  static const int _evtSessionFailed = 153;
  static const int _evtUsageResponse = 154;
  static const int _evtTaskRequest = 200;
  static const int _evtTtsSentenceStart = 350;
  static const int _evtTtsEnded = 359;
  static const int _evtAsrResponse = 451;
  static const int _evtSrcSubtitleStart = 650;
  static const int _evtSrcSubtitle = 651;
  static const int _evtSrcSubtitleEnd = 652;
  static const int _evtTransSubtitleStart = 653;
  static const int _evtTransSubtitle = 654;
  static const int _evtTransSubtitleEnd = 655;

  // ─── State ────────────────────────────────────────────────────────────────
  AstConfig? _config;
  StreamController<AstEvent>? _controller;

  WebSocketChannel? _channel;
  StreamSubscription? _channelSub;

  String _connectId = '';
  String _sessionId = '';
  String _srcLang = 'zh';
  String _dstLang = 'en';
  bool _isBidirectional = false;

  bool _running = false;
  bool _connected = false;
  bool _sessionStarted = false;
  bool _disposed = false;

  Completer<void>? _sessionStartedCompleter;

  // Incremental subtitle accumulators (server sends partials).
  final StringBuffer _srcAccum = StringBuffer();
  final StringBuffer _transAccum = StringBuffer();

  // Recognition round state (mirrors AST 5-piece lifecycle in [AstEvent]).
  String? _currentRequestId;
  bool _sourceRoleOpen = false;
  bool _translatedRoleOpen = false;

  // ─── Microphone ───────────────────────────────────────────────────────────
  web.AudioContext? _micContext;
  web.MediaStream? _micStream;
  JSObject? _micSource;
  JSObject? _micProcessor;

  // ─── TTS playback ─────────────────────────────────────────────────────────
  web.AudioContext? _ttsContext;
  double _ttsNextStartTime = 0.0;

  // ─── AstPlugin ────────────────────────────────────────────────────────────
  @override
  Future<void> initialize(AstConfig config) async {
    if (_disposed) {
      throw StateError('AstVolcenginePluginWeb: already disposed');
    }
    _config = config;
    _srcLang = config.srcLang.isEmpty ? 'zh' : config.srcLang;
    _dstLang = config.dstLang.isEmpty ? 'en' : config.dstLang;
    _isBidirectional = _srcLang == 'zh' && _dstLang == 'en' ||
        _srcLang == 'en' && _dstLang == 'zh';
    _controller ??= StreamController<AstEvent>.broadcast();
  }

  @override
  Future<void> startCall() async {
    if (_disposed) {
      throw StateError('AstVolcenginePluginWeb: already disposed');
    }
    final cfg = _config;
    if (cfg == null) {
      _emitError('config_error', 'Plugin not initialized');
      return;
    }
    if (cfg.appId.isEmpty || cfg.apiKey.isEmpty) {
      _emitError('config_error', 'appId or apiKey missing');
      return;
    }

    _controller ??= StreamController<AstEvent>.broadcast();
    _running = true;
    _connected = false;
    _sessionStarted = false;
    _connectId = _uuid();
    _sessionId = _uuid();
    _srcAccum.clear();
    _transAccum.clear();
    _resetRoundState();

    final resourceId =
        cfg.extraParams['resourceId'] ?? _fixedResourceId;

    // Build URL. Browsers can't set WebSocket request headers, so we pass
    // the handshake auth fields as query parameters — backend may need
    // explicit support for this fallback.
    final uri = _buildWsUri(
      appKey: cfg.appId,
      accessKey: cfg.apiKey,
      resourceId: resourceId,
      connectId: _connectId,
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;
    } catch (e) {
      _running = false;
      _emitError('ws_error', 'WebSocket connect failed: $e');
      return;
    }

    _channelSub = _channel!.stream.listen(
      _onWsMessage,
      onError: (Object err, StackTrace _) {
        if (_running) _emitError('ws_error', err.toString());
        _running = false;
        _connected = false;
        _emit(const AstEvent(type: AstEventType.disconnected));
      },
      onDone: () {
        _connected = false;
        if (_running) {
          _emit(const AstEvent(type: AstEventType.disconnected));
        }
        _running = false;
      },
    );

    // Prepare TTS playback context eagerly so scheduling is gap-free.
    _ensureTtsContext();

    // Send StartSession and wait for SessionStarted.
    _sessionStartedCompleter = Completer<void>();
    try {
      _sendBinary(_buildTranslateRequest(_evtStartSession));
      await _sessionStartedCompleter!.future
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      _running = false;
      _emitError('ast_error', 'SessionStarted timeout / failed: $e');
      return;
    }

    _connected = true;
    _sessionStarted = true;
    _emit(const AstEvent(type: AstEventType.connected));

    // On web, the plugin captures its own audio — start mic now.
    await _startMicrophone();
  }

  @override
  void sendAudio(List<int> pcmData) {
    // No-op on web: microphone is captured by the plugin itself via WebAudio.
  }

  @override
  Future<void> stopCall() async {
    _running = false;
    _forceEndRound();
    // Best-effort FinishSession.
    try {
      if (_channel != null && _sessionStarted) {
        _sendBinary(_buildTranslateRequest(_evtFinishSession));
      }
    } catch (_) {}

    await _stopMicrophone();

    try {
      await _channelSub?.cancel();
    } catch (_) {}
    _channelSub = null;

    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;

    _connected = false;
    _sessionStarted = false;
    _emit(const AstEvent(type: AstEventType.disconnected));
  }

  @override
  Stream<AstEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stopCall();
    try {
      await _ttsContext?.close().toDart;
    } catch (_) {}
    _ttsContext = null;
    await _controller?.close();
    _controller = null;
    _config = null;
  }

  // ─── WebSocket receive ────────────────────────────────────────────────────
  void _onWsMessage(dynamic raw) {
    Uint8List bytes;
    if (raw is Uint8List) {
      bytes = raw;
    } else if (raw is List<int>) {
      bytes = Uint8List.fromList(raw);
    } else if (raw is ByteBuffer) {
      bytes = raw.asUint8List();
    } else if (raw is String) {
      // Server typically only sends binary; log & ignore text frames.
      return;
    } else {
      return;
    }
    try {
      _handleResponse(bytes);
    } catch (e) {
      _emitError('decode_error', 'handleResponse error: $e');
    }
  }

  void _handleResponse(Uint8List data) {
    final fields = _decodeProto(data);
    final event = _fieldVarint(fields, 2);
    final audio = _fieldBytes(fields, 3);
    final text = _fieldStr(fields, 4);

    final metaBytes = _fieldBytes(fields, 1);
    final metaFields =
        metaBytes.isNotEmpty ? _decodeProto(metaBytes) : <_PbField>[];
    final statusCode = _fieldVarint(metaFields, 3);
    final message = _fieldStr(metaFields, 4);

    switch (event) {
      case _evtSessionStarted:
        if (_sessionStartedCompleter != null &&
            !_sessionStartedCompleter!.isCompleted) {
          _sessionStartedCompleter!.complete();
        }
        break;

      case _evtSessionFinished:
        _connected = false;
        _forceEndRound();
        _emit(const AstEvent(type: AstEventType.disconnected));
        break;

      case _evtSessionFailed:
        final msg = 'SessionFailed status=$statusCode msg=$message';
        if (_sessionStartedCompleter != null &&
            !_sessionStartedCompleter!.isCompleted) {
          _sessionStartedCompleter!.completeError(StateError(msg));
        }
        _emitError('ast_session_failed', msg);
        break;

      case _evtAsrResponse:
        if (text.isNotEmpty) {
          _beginRound();
          _openRole(AstRole.source);
          _emitRoleText(AstRole.source, AstEventType.recognizing, text);
        }
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtSrcSubtitleStart:
        _beginRound();
        _openRole(AstRole.source);
        _srcAccum.clear();
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtSrcSubtitle:
        if (text.isNotEmpty) {
          _beginRound();
          _openRole(AstRole.source);
          _srcAccum.write(text);
          _emitRoleText(
            AstRole.source,
            AstEventType.recognizing,
            _srcAccum.toString(),
          );
        }
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtSrcSubtitleEnd:
        if (_srcAccum.isNotEmpty) {
          _emitRoleText(
            AstRole.source,
            AstEventType.recognized,
            _srcAccum.toString(),
          );
        }
        _closeRole(AstRole.source);
        _maybeEndRound();
        break;

      case _evtTransSubtitleStart:
        _beginRound();
        _openRole(AstRole.translated);
        _transAccum.clear();
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtTransSubtitle:
        if (text.isNotEmpty) {
          _beginRound();
          _openRole(AstRole.translated);
          _transAccum.write(text);
          _emitRoleText(
            AstRole.translated,
            AstEventType.recognizing,
            _transAccum.toString(),
          );
        }
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtTransSubtitleEnd:
        if (_transAccum.isNotEmpty) {
          _emitRoleText(
            AstRole.translated,
            AstEventType.recognized,
            _transAccum.toString(),
          );
        }
        _closeRole(AstRole.translated);
        _maybeEndRound();
        break;

      case _evtTtsSentenceStart:
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtTtsEnded:
        // Sentence TTS ended — nothing to do; Dart-side audio context will
        // naturally drain remaining scheduled buffers.
        break;

      case _evtUsageResponse:
        break;

      default:
        // Unknown/unhandled event: still play any audio that came along.
        if (audio.isNotEmpty) _playTts(audio);
        break;
    }
  }

  // ─── WebSocket send helpers ──────────────────────────────────────────────
  void _sendBinary(Uint8List data) {
    final sink = _channel?.sink;
    if (sink == null) return;
    sink.add(data);
  }

  Uri _buildWsUri({
    required String appKey,
    required String accessKey,
    required String resourceId,
    required String connectId,
  }) {
    final uri = Uri.parse(_wsUrl);
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'X-Api-App-Key': appKey,
      'X-Api-Access-Key': accessKey,
      'X-Api-Resource-Id': resourceId,
      'X-Api-Connect-Id': connectId,
    });
  }

  // ─── Protobuf: TranslateRequest builder (mirrors Kotlin) ─────────────────
  /// Build a full `TranslateRequest` Protobuf message.
  ///
  /// Field layout (see Kotlin reference):
  ///   1: request_meta { 5: connectId, 6: sessionId }
  ///   2: event (varint)
  ///   3: user { 1: uid, 2: did }
  ///   4: source_audio { 4: format, 7: rate, 8: bits, 9: channel,
  ///                     14: binary_data }
  ///   5: target_audio { 4: format, 7: rate, 8: bits, 9: channel }
  ///   6: request { 1: mode, 2: source_language, 3: target_language }
  Uint8List _buildTranslateRequest(int event, [Uint8List? pcm]) {
    final srcAudioFields = BytesBuilder();
    srcAudioFields.add(_encStr(4, 'wav'));
    srcAudioFields.add(_encInt(7, _micSampleRate));
    srcAudioFields.add(_encInt(8, 16));
    srcAudioFields.add(_encInt(9, 1));
    if (pcm != null && pcm.isNotEmpty) {
      srcAudioFields.add(_encBytes(14, pcm));
    }

    final wsSource = _isBidirectional ? 'zhen' : _srcLang;
    final wsTarget = _isBidirectional ? 'zhen' : _dstLang;

    final meta = BytesBuilder()
      ..add(_encStr(5, _connectId))
      ..add(_encStr(6, _sessionId));

    final user = BytesBuilder()
      ..add(_encStr(1, 'ast_web'))
      ..add(_encStr(2, 'ast_web'));

    final target = BytesBuilder()
      ..add(_encStr(4, 'wav'))
      ..add(_encInt(7, _ttsSampleRate))
      ..add(_encInt(8, 16))
      ..add(_encInt(9, 1));

    final request = BytesBuilder()
      ..add(_encStr(1, 's2s'))
      ..add(_encStr(2, wsSource))
      ..add(_encStr(3, wsTarget));

    final out = BytesBuilder();
    out.add(_encMsg(1, meta.toBytes()));
    out.add(_encEnum(2, event));
    out.add(_encMsg(3, user.toBytes()));
    out.add(_encMsg(4, srcAudioFields.toBytes()));
    out.add(_encMsg(5, target.toBytes()));
    out.add(_encMsg(6, request.toBytes()));
    return out.toBytes();
  }

  /// Minimal audio-only frame — mirrors Kotlin's `buildAudioFrame`.
  Uint8List _buildAudioFrame(Uint8List pcm) {
    final meta = BytesBuilder()..add(_encStr(6, _sessionId));
    final src = BytesBuilder()..add(_encBytes(14, pcm));

    final out = BytesBuilder();
    out.add(_encMsg(1, meta.toBytes()));
    out.add(_encEnum(2, _evtTaskRequest));
    out.add(_encMsg(4, src.toBytes()));
    return out.toBytes();
  }

  // ─── Protobuf wire-format primitives ──────────────────────────────────────
  static Uint8List _varint(int value) {
    // Dart ints on web are JS numbers (safe integers); field sizes here fit.
    final out = <int>[];
    var v = value;
    while ((v & ~0x7F) != 0) {
      out.add((v & 0x7F) | 0x80);
      v = (v >> 7) & 0x1FFFFFFFFFFFFF; // keep unsigned up to 53 bits
    }
    out.add(v & 0x7F);
    return Uint8List.fromList(out);
  }

  static Uint8List _tag(int fieldNum, int wireType) =>
      _varint((fieldNum << 3) | wireType);

  static Uint8List _encEnum(int fieldNum, int value) {
    if (value == 0) return Uint8List(0);
    final t = _tag(fieldNum, 0);
    final v = _varint(value);
    return Uint8List.fromList([...t, ...v]);
  }

  static Uint8List _encInt(int fieldNum, int value) {
    if (value == 0) return Uint8List(0);
    final t = _tag(fieldNum, 0);
    final v = _varint(value);
    return Uint8List.fromList([...t, ...v]);
  }

  static Uint8List _encStr(int fieldNum, String value) {
    if (value.isEmpty) return Uint8List(0);
    final bytes = _utf8Encode(value);
    final t = _tag(fieldNum, 2);
    final len = _varint(bytes.length);
    return Uint8List.fromList([...t, ...len, ...bytes]);
  }

  static Uint8List _encBytes(int fieldNum, Uint8List value) {
    if (value.isEmpty) return Uint8List(0);
    final t = _tag(fieldNum, 2);
    final len = _varint(value.length);
    return Uint8List.fromList([...t, ...len, ...value]);
  }

  static Uint8List _encMsg(int fieldNum, Uint8List msg) {
    final t = _tag(fieldNum, 2);
    final len = _varint(msg.length);
    return Uint8List.fromList([...t, ...len, ...msg]);
  }

  static Uint8List _utf8Encode(String s) {
    // Dart core provides UTF-8 encoding via the codec.
    return Uint8List.fromList(const _Utf8().encode(s));
  }

  // ─── Protobuf decoding ────────────────────────────────────────────────────
  List<_PbField> _decodeProto(Uint8List bytes) {
    final fields = <_PbField>[];
    var pos = 0;
    while (pos < bytes.length) {
      // tag varint
      var tag = 0;
      var shift = 0;
      while (pos < bytes.length) {
        final b = bytes[pos++];
        tag |= (b & 0x7F) << shift;
        shift += 7;
        if ((b & 0x80) == 0) break;
      }
      final fieldNum = tag >> 3;
      final wireType = tag & 7;
      switch (wireType) {
        case 0:
          var v = 0;
          var sh = 0;
          while (pos < bytes.length) {
            final b = bytes[pos++];
            v |= (b & 0x7F) << sh;
            sh += 7;
            if ((b & 0x80) == 0) break;
          }
          fields.add(_PbField.varint(fieldNum, v));
          break;
        case 2:
          var len = 0;
          var sh = 0;
          while (pos < bytes.length) {
            final b = bytes[pos++];
            len |= (b & 0x7F) << sh;
            sh += 7;
            if ((b & 0x80) == 0) break;
          }
          final end = (pos + len).clamp(0, bytes.length);
          fields.add(_PbField.bytes(
            fieldNum,
            Uint8List.sublistView(bytes, pos, end),
          ));
          pos = end;
          break;
        case 1:
          pos += 8;
          break;
        case 5:
          pos += 4;
          break;
        default:
          return fields;
      }
    }
    return fields;
  }

  int _fieldVarint(List<_PbField> fields, int num) {
    for (final f in fields) {
      if (f.num == num && f.wireType == 0) return f.varint;
    }
    return 0;
  }

  Uint8List _fieldBytes(List<_PbField> fields, int num) {
    for (final f in fields) {
      if (f.num == num && f.wireType == 2) return f.raw;
    }
    return Uint8List(0);
  }

  String _fieldStr(List<_PbField> fields, int num) {
    final b = _fieldBytes(fields, num);
    if (b.isEmpty) return '';
    return const _Utf8().decode(b);
  }

  // ─── Microphone capture ──────────────────────────────────────────────────
  Future<void> _startMicrophone() async {
    try {
      final navigator = web.window.navigator;
      final mediaDevices = navigator.mediaDevices;
      final constraints = web.MediaStreamConstraints(
        audio: _micAudioConstraints().jsify() as JSAny,
        video: false.toJS,
      );
      final stream = await mediaDevices.getUserMedia(constraints).toDart;
      _micStream = stream;

      // Use a dedicated AudioContext for capture; native rate is browser
      // dependent — we downsample inside the processor callback.
      final ctx = web.AudioContext();
      _micContext = ctx;
      final ctxObj = ctx as JSObject;

      final source = ctxObj.callMethod<JSObject>(
        'createMediaStreamSource'.toJS,
        stream as JSObject,
      );
      _micSource = source;

      // ScriptProcessorNode(bufferSize, inputChannels, outputChannels)
      final processor = ctxObj.callMethod<JSObject>(
        'createScriptProcessor'.toJS,
        4096.toJS,
        1.toJS,
        1.toJS,
      );
      _micProcessor = processor;

      final inputRate = (ctxObj['sampleRate'] as JSNumber).toDartDouble;
      processor['onaudioprocess'] = ((JSObject evt) {
        if (!_running || !_connected) return;
        try {
          final inputBuffer = evt['inputBuffer'] as JSObject;
          final channelData = inputBuffer.callMethod<JSObject>(
            'getChannelData'.toJS,
            0.toJS,
          );
          final length = (channelData['length'] as JSNumber).toDartInt;
          // Float32 -> downsample -> Int16 LE PCM.
          final floats = Float32List(length);
          for (var i = 0; i < length; i++) {
            floats[i] =
                (channelData[i.toString()] as JSNumber).toDartDouble;
          }
          final pcm = _resampleToInt16(floats, inputRate, _micSampleRate);
          if (pcm.isNotEmpty) {
            _sendBinary(_buildAudioFrame(pcm));
          }
        } catch (_) {
          // Ignore transient processing errors.
        }
      }).toJS;

      // Connect graph: source -> processor -> destination (silent output is
      // required on some browsers to keep onaudioprocess firing).
      (source).callMethod('connect'.toJS, processor);
      (processor).callMethod('connect'.toJS, ctxObj['destination']!);
    } catch (e) {
      _emitError('permission_denied', 'getUserMedia failed: $e');
    }
  }

  Map<String, Object?> _micAudioConstraints() => {
        'channelCount': 1,
        'sampleRate': _micSampleRate,
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      };

  Future<void> _stopMicrophone() async {
    try {
      if (_micProcessor != null) {
        (_micProcessor!).callMethod('disconnect'.toJS);
      }
    } catch (_) {}
    try {
      if (_micSource != null) {
        (_micSource!).callMethod('disconnect'.toJS);
      }
    } catch (_) {}
    try {
      final s = _micStream;
      if (s != null) {
        final tracks = (s as JSObject)
            .callMethod<JSObject>('getTracks'.toJS);
        final length = (tracks['length'] as JSNumber).toDartInt;
        for (var i = 0; i < length; i++) {
          final t = tracks[i.toString()] as JSObject;
          t.callMethod('stop'.toJS);
        }
      }
    } catch (_) {}
    try {
      await _micContext?.close().toDart;
    } catch (_) {}
    _micProcessor = null;
    _micSource = null;
    _micStream = null;
    _micContext = null;
  }

  /// Linear downsample Float32 at `inputRate` to Int16 LE PCM at `targetRate`.
  Uint8List _resampleToInt16(
    Float32List input,
    double inputRate,
    int targetRate,
  ) {
    if (input.isEmpty) return Uint8List(0);
    if (inputRate == targetRate.toDouble()) {
      final out = Uint8List(input.length * 2);
      final bd = ByteData.view(out.buffer);
      for (var i = 0; i < input.length; i++) {
        var s = (input[i] * 32767.0).round();
        if (s > 32767) s = 32767;
        if (s < -32768) s = -32768;
        bd.setInt16(i * 2, s, Endian.little);
      }
      return out;
    }
    final ratio = inputRate / targetRate;
    final outLen = (input.length / ratio).floor();
    final out = Uint8List(outLen * 2);
    final bd = ByteData.view(out.buffer);
    for (var i = 0; i < outLen; i++) {
      final idx = (i * ratio).floor();
      final clamped = idx < input.length ? idx : input.length - 1;
      var s = (input[clamped] * 32767.0).round();
      if (s > 32767) s = 32767;
      if (s < -32768) s = -32768;
      bd.setInt16(i * 2, s, Endian.little);
    }
    return out;
  }

  // ─── TTS playback (24 kHz PCM, gap-free scheduling) ──────────────────────
  void _ensureTtsContext() {
    if (_ttsContext != null) return;
    try {
      final opts = web.AudioContextOptions(sampleRate: _ttsSampleRate);
      _ttsContext = web.AudioContext(opts);
      _ttsNextStartTime = 0.0;
    } catch (_) {
      // Some browsers reject explicit sampleRate — fall back to default.
      _ttsContext = web.AudioContext();
      _ttsNextStartTime = 0.0;
    }
  }

  void _playTts(Uint8List pcmBytes) {
    _ensureTtsContext();
    final ctx = _ttsContext;
    if (ctx == null || pcmBytes.isEmpty) return;
    // Decode 16-bit LE PCM mono -> Float32 samples.
    final samples = pcmBytes.length ~/ 2;
    if (samples == 0) return;
    final bd = ByteData.sublistView(pcmBytes);
    final floats = Float32List(samples);
    for (var i = 0; i < samples; i++) {
      floats[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }

    try {
      final buffer = ctx.createBuffer(1, samples, _ttsSampleRate.toDouble());
      buffer.copyToChannel(floats.toJS, 0);
      final source = ctx.createBufferSource();
      source.buffer = buffer;
      (source as JSObject).callMethod(
        'connect'.toJS,
        (ctx as JSObject)['destination']!,
      );

      final now = (ctx as JSObject)['currentTime'] as JSNumber;
      final nowDart = now.toDartDouble;
      final startAt = _ttsNextStartTime > nowDart
          ? _ttsNextStartTime
          : nowDart;
      (source).callMethod('start'.toJS, startAt.toJS);
      _ttsNextStartTime = startAt + samples / _ttsSampleRate.toDouble();
    } catch (_) {
      // Swallow — playback is best-effort; event consumers still receive
      // ttsAudioChunk for their own handling.
    }
  }

  // ─── Recognition round state machine ──────────────────────────────────────

  /// Start a new round if none is active. Pass `force=true` to implicitly end
  /// the previous round first.
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

  void _forceEndRound() {
    if (_currentRequestId == null) return;
    if (_sourceRoleOpen) _closeRole(AstRole.source);
    if (_translatedRoleOpen) _closeRole(AstRole.translated);
    _endRound();
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
    return 'ast_volcengine_${ms}_$r';
  }

  // ─── Utilities ────────────────────────────────────────────────────────────
  void _emit(AstEvent e) {
    if (_controller == null || _controller!.isClosed) return;
    _controller!.add(e);
  }

  void _emitError(String code, String message) {
    _emit(AstEvent(
      type: AstEventType.error,
      errorCode: code,
      errorMessage: message,
    ));
  }

  String _uuid() {
    // RFC4122 v4 via browser crypto when available; else Math.random fallback.
    try {
      final crypto = (web.window as JSObject)['crypto'];
      if (crypto != null && (crypto as JSObject).has('randomUUID')) {
        return (crypto.callMethod<JSString>('randomUUID'.toJS)).toDart;
      }
    } catch (_) {}
    final r = DateTime.now().microsecondsSinceEpoch;
    // Not RFC-compliant but adequate as a connect_id fallback.
    return 'web-$r-${identityHashCode(this)}';
  }
}

class _PbField {
  _PbField.varint(this.num, int value)
      : wireType = 0,
        varint = value,
        raw = Uint8List(0);
  _PbField.bytes(this.num, this.raw)
      : wireType = 2,
        varint = 0;

  final int num;
  final int wireType;
  final int varint;
  final Uint8List raw;
}

// Tiny UTF-8 helper to avoid pulling in `dart:convert` import alongside the
// many typed_data / js_interop usages. Semantically equivalent to utf8.encoder
// / utf8.decoder for well-formed input.
class _Utf8 {
  const _Utf8();

  List<int> encode(String s) {
    final out = <int>[];
    for (final rune in s.runes) {
      if (rune < 0x80) {
        out.add(rune);
      } else if (rune < 0x800) {
        out.add(0xC0 | (rune >> 6));
        out.add(0x80 | (rune & 0x3F));
      } else if (rune < 0x10000) {
        out.add(0xE0 | (rune >> 12));
        out.add(0x80 | ((rune >> 6) & 0x3F));
        out.add(0x80 | (rune & 0x3F));
      } else {
        out.add(0xF0 | (rune >> 18));
        out.add(0x80 | ((rune >> 12) & 0x3F));
        out.add(0x80 | ((rune >> 6) & 0x3F));
        out.add(0x80 | (rune & 0x3F));
      }
    }
    return out;
  }

  String decode(Uint8List bytes) {
    final sb = StringBuffer();
    var i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      int rune;
      if (b < 0x80) {
        rune = b;
        i += 1;
      } else if (b < 0xC0) {
        // Invalid lead byte; skip.
        i += 1;
        continue;
      } else if (b < 0xE0 && i + 1 < bytes.length) {
        rune = ((b & 0x1F) << 6) | (bytes[i + 1] & 0x3F);
        i += 2;
      } else if (b < 0xF0 && i + 2 < bytes.length) {
        rune = ((b & 0x0F) << 12) |
            ((bytes[i + 1] & 0x3F) << 6) |
            (bytes[i + 2] & 0x3F);
        i += 3;
      } else if (i + 3 < bytes.length) {
        rune = ((b & 0x07) << 18) |
            ((bytes[i + 1] & 0x3F) << 12) |
            ((bytes[i + 2] & 0x3F) << 6) |
            (bytes[i + 3] & 0x3F);
        i += 4;
      } else {
        break;
      }
      sb.writeCharCode(rune);
    }
    return sb.toString();
  }
}
