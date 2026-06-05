import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:archive/archive.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// StsVolcengineDesktop — Volcengine 端到端语音对话（桌面 macOS / Windows / Linux）。
///
/// 协议层（帧编解码 + gzip + 会话握手 + 回合状态机）与 web 实现完全一致，只把三处
/// 音频 I/O 换成桌面 Dart 包：
///  1. WebSocket：`web_socket_channel`（桌面走 dart:io WebSocket）。鉴权沿用 web 的
///     URL query 参数方式（gateway 已知可接受）。
///  2. 麦克风：`record` 直接产出 16 kHz mono 16-bit PCM 流（无需手动重采样）。
///  3. TTS 播放：`flutter_pcm_sound` 喂 24 kHz PCM 实现无缝播放。
class StsVolcengineDesktop implements StsPlugin {
  // ── Protocol constants（与 Kotlin / web 一致）─────────────────────────────
  static const String _wsUrl =
      'wss://openspeech.bytedance.com/api/v3/realtime/dialogue';
  static const String _fixedResourceId = 'volc.speech.dialog';
  static const String _fixedAppKey = 'PlgvMymc7f3tQnJ6';

  static const int _headerB0 = 0x11;

  static const int _typeFullClient = 0x10;
  static const int _typeAudioClient = 0x20;
  static const int _typeFullServer = 0x90;
  static const int _typeAudioServer = 0xB0;
  static const int _typeError = 0xF0;

  static const int _flagWithEvent = 0x04;
  static const int _flagNegSequence = 0x02;

  static const int _serNone = 0x00;
  static const int _serJson = 0x10;

  static const int _compressGzip = 0x01;

  static const int _hdr2JsonGzip = _serJson | _compressGzip;
  static const int _hdr2RawGzip = _serNone | _compressGzip;

  static const int _evtStartConnection = 1;
  static const int _evtFinishConnection = 2;
  static const int _evtStartSession = 100;
  static const int _evtFinishSession = 102;
  static const int _evtSendAudio = 200;

  static const int _evtConnectionStarted = 50;
  static const int _evtConnectionFailed = 51;
  static const int _evtConnectionFinished = 52;
  static const int _evtSessionStarted = 150;
  static const int _evtSessionFinOk = 152;
  static const int _evtSessionFinErr = 153;
  static const int _evtTtsType = 350;
  static const int _evtTtsEnded = 359;
  static const int _evtClearAudio = 450;
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
  WebSocketChannel? _socket;
  StreamSubscription? _socketSub;
  String _remoteSessionId = '';
  bool _isConnected = false;
  bool _isRunning = false;

  String? _currentRequestId;
  bool _botRoleOpen = false;
  bool _botPlaybackOpen = false;

  Completer<void>? _connectionStarted;
  Completer<void>? _sessionStarted;

  // ── Mic capture（record）────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  bool _isAudioRunning = false;

  // ── TTS playback（flutter_pcm_sound）────────────────────────────────────
  bool _pcmReady = false;

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
    _connectionStarted = Completer<void>();
    _sessionStarted = Completer<void>();

    try {
      await _openWebSocket(cfg);

      _sendJsonFrame(_evtStartConnection, '{}');
      await _connectionStarted!.future.timeout(const Duration(seconds: 10));

      _sendJsonFrame(_evtStartSession, _buildSessionPayload());
      await _sessionStarted!.future.timeout(const Duration(seconds: 10));

      _isConnected = true;
      _emit(const StsEvent(type: StsEventType.connected));

      await startAudio();
    } on TimeoutException catch (e) {
      _isRunning = false;
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.handshake_timeout',
        errorMessage: 'Handshake timed out: ${e.message}',
      ));
      await _closeSocket();
    } catch (e) {
      _isRunning = false;
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'sts.connect_failed',
        errorMessage: e.toString(),
      ));
      await _closeSocket();
    }
  }

  /// 桌面上插件自管麦克风（record），agents_server 不向插件泵 PCM，故 no-op。
  @override
  void sendAudio(List<int> pcmData) {}

  @override
  Future<void> stopCall() async {
    _isRunning = false;
    _isConnected = false;

    await stopAudio();
    await _cancelPlayback();
    _forceCloseRound(interrupted: true);

    try {
      if (_remoteSessionId.isNotEmpty) {
        _sendJsonFrame(_evtFinishSession, '{}');
      }
      _sendJsonFrame(_evtFinishConnection, '{}');
    } catch (_) {}

    await _closeSocket();
    _remoteSessionId = '';
  }

  @override
  Stream<StsEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
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

  // ==========================================================================
  // Mic capture (record → 16 kHz mono PCM16)
  // ==========================================================================

  Future<void> startAudio() async {
    if (_isAudioRunning || !_isConnected) return;
    try {
      if (!await _recorder.hasPermission()) {
        _emit(const StsEvent(
          type: StsEventType.error,
          errorCode: 'permission_denied',
          errorMessage: 'microphone permission denied',
        ));
        return;
      }
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _isAudioRunning = true;
      _micSub = stream.listen(
        (chunk) {
          if (!_isAudioRunning || !_isConnected) return;
          _sendAudioFrame(chunk);
        },
        onError: (_) {},
      );
    } catch (e) {
      _emit(StsEvent(
        type: StsEventType.error,
        errorCode: 'permission_denied',
        errorMessage: 'record start failed: $e',
      ));
    }
  }

  Future<void> stopAudio() async {
    _isAudioRunning = false;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
  }

  // ==========================================================================
  // WebSocket
  // ==========================================================================

  Future<void> _openWebSocket(StsConfig cfg) async {
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

    final ws = WebSocketChannel.connect(Uri.parse(url));
    _socket = ws;
    await ws.ready.timeout(const Duration(seconds: 15));

    _socketSub = ws.stream.listen(
      (data) {
        final bytes = data is Uint8List
            ? data
            : Uint8List.fromList((data as List).cast<int>());
        try {
          _parseServerFrame(bytes);
        } catch (e) {
          _emit(StsEvent(
            type: StsEventType.error,
            errorCode: 'sts.parse_error',
            errorMessage: e.toString(),
          ));
        }
      },
      onError: (Object err) {
        _completeExceptionally('WebSocket error: $err');
        if (_isRunning) {
          _emit(const StsEvent(
            type: StsEventType.error,
            errorCode: 'network_error',
            errorMessage: 'WebSocket error',
          ));
        }
      },
      onDone: () {
        _completeExceptionally('WebSocket closed');
        _isConnected = false;
        if (_controller != null && !_controller!.isClosed) {
          _emit(const StsEvent(type: StsEventType.disconnected));
        }
      },
    );
  }

  Future<void> _closeSocket() async {
    final ws = _socket;
    _socket = null;
    await _socketSub?.cancel();
    _socketSub = null;
    if (ws == null) return;
    try {
      await ws.sink.close();
    } catch (_) {}
  }

  void _completeExceptionally(String msg) {
    for (final c in [_connectionStarted, _sessionStarted]) {
      if (c != null && !c.isCompleted) {
        c.completeError(StateError(msg));
      }
    }
  }

  // ==========================================================================
  // Frame encoding（与 web 一致）
  // ==========================================================================

  void _sendJsonFrame(int event, String jsonPayload) {
    final body = _gzip(utf8.encode(jsonPayload));
    final skipSession = _noSessionEvents.contains(event);
    final sidBytes = utf8.encode(_remoteSessionId);

    var size = 4 + 4 + body.length;
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
      ws.sink.add(bytes);
    } catch (_) {}
  }

  // ==========================================================================
  // Frame decoding（与 web 一致）
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
            } catch (_) {}
          }
        }

        if (msgType == _typeFullServer) {
          _handleServerEvent(event, payload, serType);
        } else {
          if (payload.isNotEmpty) {
            _schedulePlayback(payload);
            _ensureBotRoundForAudio();
            _emit(StsEvent(
              type: StsEventType.audioChunk,
              role: StsRole.bot,
              requestId: _currentRequestId,
              audioData: payload,
              audioFormat: _botPlaybackOpen
                  ? null
                  : const StsAudioFormat(
                      sampleRateHz: 24000,
                      channels: 1,
                      encoding: 'pcm_s16le',
                    ),
            ));
            if (!_botPlaybackOpen) {
              _emit(StsEvent(
                type: StsEventType.playbackStart,
                role: StsRole.bot,
                requestId: _currentRequestId,
              ));
              _botPlaybackOpen = true;
            }
          }
        }
        break;

      case _typeError:
        String errText;
        if (data.length >= 12) {
          final errCode =
              ByteData.sublistView(data, 4, 8).getInt32(0, Endian.big);
          final pLen =
              ByteData.sublistView(data, 8, 12).getInt32(0, Endian.big);
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
        if (!(_connectionStarted?.isCompleted ?? true)) {
          _connectionStarted!.complete();
        }
        break;
      case _evtConnectionFailed:
        final msg = (json?['message'] as String?) ?? 'connection failed';
        if (!(_connectionStarted?.isCompleted ?? true)) {
          _connectionStarted!.completeError(StateError(msg));
        }
        break;
      case _evtConnectionFinished:
        _emit(const StsEvent(type: StsEventType.disconnected));
        break;
      case _evtSessionStarted:
        if (!(_sessionStarted?.isCompleted ?? true)) {
          _sessionStarted!.complete();
        }
        break;
      case _evtSessionFinOk:
      case _evtSessionFinErr:
        break;
      case _evtClearAudio:
        _cancelPlayback();
        _forceCloseRound(interrupted: true);
        break;
      case _evtChatEnded:
        final content = (json?['content'] as String?) ?? '';
        if (content.isNotEmpty) {
          _emitBotTurnWhole(content);
        }
        break;
      case _evtTtsEnded:
        _forceCloseRound(interrupted: false);
        break;
      case _evtTtsType:
        break;
      default:
        break;
    }
  }

  // ==========================================================================
  // TTS playback (24 kHz int16 LE → flutter_pcm_sound)
  // ==========================================================================

  Future<void> _ensurePcm() async {
    if (_pcmReady) return;
    await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
    _pcmReady = true;
  }

  void _schedulePlayback(Uint8List pcmInt16Le) {
    // fire-and-forget；setup 是幂等的（_pcmReady 守卫）。
    () async {
      try {
        await _ensurePcm();
        await FlutterPcmSound.feed(
          PcmArrayInt16(bytes: ByteData.sublistView(pcmInt16Le)),
        );
      } catch (_) {
        // 播放失败不应中断对话会话。
      }
    }();
  }

  Future<void> _cancelPlayback() async {
    if (!_pcmReady) return;
    // flutter_pcm_sound 无显式清空队列；release + 重新 setup 丢弃已排队音频。
    try {
      await FlutterPcmSound.release();
    } catch (_) {}
    _pcmReady = false;
  }

  // ==========================================================================
  // Payload helpers（与 web 一致）
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
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
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

  // ==========================================================================
  // Recognition round state machine（与 web 一致）
  // ==========================================================================

  void _ensureBotRoundForAudio() {
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

  String _newRequestId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final r = math.Random().nextInt(1 << 30).toRadixString(36).padLeft(6, '0');
    return 'sts_volcengine_${ms}_$r';
  }
}
