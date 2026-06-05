// Desktop (macOS / Windows / Linux) implementation of the Volcengine AST
// (Audio Speech Translation) plugin.
//
// 协议层（Protobuf 二进制帧的 encode/decode + TranslateRequest 构建 + 识别五件套
// 回合状态机）与 web 实现 `ast_volcengine_plugin_web.dart` 完全一致——AST 协议本身
// 就用跨平台的 `web_socket_channel`。仅替换两处浏览器专用音频 I/O：
//   - 麦克风：`record` 直接产出 16 kHz mono 16-bit PCM（无需手动重采样）；
//   - TTS 播放：`flutter_pcm_sound` 喂 24 kHz PCM 无缝播放。

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Volcengine AST（端到端语音翻译）— 桌面实现。
class AstVolcengineDesktop implements AstPlugin {
  // ─── Protocol constants（与 Kotlin / web 一致）───────────────────────────
  static const String _wsUrl =
      'wss://openspeech.bytedance.com/api/v4/ast/v2/translate';
  static const String _fixedResourceId = 'volc.bigasr.auc';

  static const int _micSampleRate = 16000;
  static const int _ttsSampleRate = 24000;

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

  final StringBuffer _srcAccum = StringBuffer();
  final StringBuffer _transAccum = StringBuffer();

  String? _currentRequestId;
  bool _sourceRoleOpen = false;
  bool _translatedRoleOpen = false;

  // ─── Mic capture（record）────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;

  // ─── TTS playback（flutter_pcm_sound）───────────────────────────────────
  bool _pcmReady = false;

  // ─── AstPlugin ────────────────────────────────────────────────────────────
  @override
  Future<void> initialize(AstConfig config) async {
    if (_disposed) {
      throw StateError('AstVolcengineDesktop: already disposed');
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
      throw StateError('AstVolcengineDesktop: already disposed');
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

    final resourceId = cfg.extraParams['resourceId'] ?? _fixedResourceId;
    final uri = _buildWsUri(
      appKey: cfg.appId,
      accessKey: cfg.apiKey,
      resourceId: resourceId,
      connectId: _connectId,
    );

    try {
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready.timeout(const Duration(seconds: 15));
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

    await _startMicrophone();
  }

  @override
  void sendAudio(List<int> pcmData) {
    // No-op：桌面上插件自管麦克风（record）。
  }

  @override
  Future<void> stopCall() async {
    _running = false;
    _forceEndRound();
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
    if (_pcmReady) {
      try {
        await FlutterPcmSound.release();
      } catch (_) {}
      _pcmReady = false;
    }
    try {
      await _recorder.dispose();
    } catch (_) {}
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
              AstRole.source, AstEventType.recognizing, _srcAccum.toString());
        }
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtSrcSubtitleEnd:
        if (_srcAccum.isNotEmpty) {
          _emitRoleText(
              AstRole.source, AstEventType.recognized, _srcAccum.toString());
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
          _emitRoleText(AstRole.translated, AstEventType.recognizing,
              _transAccum.toString());
        }
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtTransSubtitleEnd:
        if (_transAccum.isNotEmpty) {
          _emitRoleText(AstRole.translated, AstEventType.recognized,
              _transAccum.toString());
        }
        _closeRole(AstRole.translated);
        _maybeEndRound();
        break;

      case _evtTtsSentenceStart:
        if (audio.isNotEmpty) _playTts(audio);
        break;

      case _evtTtsEnded:
        break;

      case _evtUsageResponse:
        break;

      default:
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

  // ─── Protobuf: TranslateRequest builder（与 web 一致）─────────────────────
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
      ..add(_encStr(1, 'ast_desktop'))
      ..add(_encStr(2, 'ast_desktop'));

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

  Uint8List _buildAudioFrame(Uint8List pcm) {
    final meta = BytesBuilder()..add(_encStr(6, _sessionId));
    final src = BytesBuilder()..add(_encBytes(14, pcm));

    final out = BytesBuilder();
    out.add(_encMsg(1, meta.toBytes()));
    out.add(_encEnum(2, _evtTaskRequest));
    out.add(_encMsg(4, src.toBytes()));
    return out.toBytes();
  }

  // ─── Protobuf wire-format primitives（与 web 一致）────────────────────────
  static Uint8List _varint(int value) {
    final out = <int>[];
    var v = value;
    while ((v & ~0x7F) != 0) {
      out.add((v & 0x7F) | 0x80);
      v = (v >> 7) & 0x1FFFFFFFFFFFFF;
    }
    out.add(v & 0x7F);
    return Uint8List.fromList(out);
  }

  static Uint8List _tag(int fieldNum, int wireType) =>
      _varint((fieldNum << 3) | wireType);

  static Uint8List _encEnum(int fieldNum, int value) {
    if (value == 0) return Uint8List(0);
    return Uint8List.fromList([..._tag(fieldNum, 0), ..._varint(value)]);
  }

  static Uint8List _encInt(int fieldNum, int value) {
    if (value == 0) return Uint8List(0);
    return Uint8List.fromList([..._tag(fieldNum, 0), ..._varint(value)]);
  }

  static Uint8List _encStr(int fieldNum, String value) {
    if (value.isEmpty) return Uint8List(0);
    final bytes = utf8.encode(value);
    return Uint8List.fromList(
        [..._tag(fieldNum, 2), ..._varint(bytes.length), ...bytes]);
  }

  static Uint8List _encBytes(int fieldNum, Uint8List value) {
    if (value.isEmpty) return Uint8List(0);
    return Uint8List.fromList(
        [..._tag(fieldNum, 2), ..._varint(value.length), ...value]);
  }

  static Uint8List _encMsg(int fieldNum, Uint8List msg) {
    return Uint8List.fromList(
        [..._tag(fieldNum, 2), ..._varint(msg.length), ...msg]);
  }

  // ─── Protobuf decoding（与 web 一致）──────────────────────────────────────
  List<_PbField> _decodeProto(Uint8List bytes) {
    final fields = <_PbField>[];
    var pos = 0;
    while (pos < bytes.length) {
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
              fieldNum, Uint8List.sublistView(bytes, pos, end)));
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
    return utf8.decode(b, allowMalformed: true);
  }

  // ─── Mic capture (record → 16 kHz mono PCM16) ────────────────────────────
  Future<void> _startMicrophone() async {
    try {
      if (!await _recorder.hasPermission()) {
        _emitError('permission_denied', 'microphone permission denied');
        return;
      }
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _micSampleRate,
        numChannels: 1,
      ));
      _micSub = stream.listen(
        (chunk) {
          if (!_running || !_connected) return;
          if (chunk.isNotEmpty) _sendBinary(_buildAudioFrame(chunk));
        },
        onError: (_) {},
      );
    } catch (e) {
      _emitError('permission_denied', 'record start failed: $e');
    }
  }

  Future<void> _stopMicrophone() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
  }

  // ─── TTS playback (24 kHz PCM via flutter_pcm_sound) ──────────────────────
  Future<void> _ensurePcm() async {
    if (_pcmReady) return;
    await FlutterPcmSound.setup(sampleRate: _ttsSampleRate, channelCount: 1);
    _pcmReady = true;
  }

  void _playTts(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) return;
    () async {
      try {
        await _ensurePcm();
        await FlutterPcmSound.feed(
          PcmArrayInt16(bytes: ByteData.sublistView(pcmBytes)),
        );
      } catch (_) {}
    }();
  }

  // ─── Recognition round state machine（与 web 一致）────────────────────────
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
          requestId: requestId));
    } else if (role == AstRole.translated && !_translatedRoleOpen) {
      _translatedRoleOpen = true;
      _emit(AstEvent(
          type: AstEventType.recognitionStart,
          role: role,
          requestId: requestId));
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
          requestId: requestId));
    } else if (role == AstRole.translated && _translatedRoleOpen) {
      _translatedRoleOpen = false;
      _emit(AstEvent(
          type: AstEventType.recognitionDone,
          role: role,
          requestId: requestId));
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
    _emit(AstEvent(type: AstEventType.recognitionEnd, requestId: requestId));
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
    _emit(AstEvent(type: type, role: role, requestId: requestId, text: text));
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
        type: AstEventType.error, errorCode: code, errorMessage: message));
  }

  String _uuid() {
    final rnd = math.Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
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
