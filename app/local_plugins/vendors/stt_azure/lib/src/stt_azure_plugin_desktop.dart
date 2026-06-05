import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 桌面（macOS / Windows / Linux）Azure 语音识别（STT）实现。
///
/// web 端用浏览器 SpeechRecognition（不可移植到桌面）；桌面这里实现 Azure 语音
/// 服务的 WebSocket 流式协议（USP）：
///  - 用 `record` 采集 16 kHz mono 16-bit PCM；
///  - 通过 `web_socket_channel`（桌面走 dart:io，可在握手设置订阅密钥 query）连接
///    `wss://{region}.stt.speech.microsoft.com/.../conversation/.../v1`；
///  - 消息为 USP 分帧：文本帧（`Path: ...\r\n...\r\n\r\n{json}`）与二进制音频帧
///    （2 字节大端头长度 + ASCII 头 + 音频）。
///
/// ⚠️ 该协议为纯 Dart 从零实现，未经 Azure 凭据实机验证；首次接入请用真实 key
/// 在 macOS 上跑「服务测试 → STT」核对识别结果，必要时按服务端报文微调。
class SttAzureDesktop implements SttPlugin {
  static const String _path = 'conversation'; // 连续识别

  SttConfig? _config;
  StreamController<SttEvent>? _controller;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;

  WebSocketChannel? _socket;
  StreamSubscription? _socketSub;

  bool _listening = false;
  bool _firstAudioChunk = true;
  String _requestId = '';

  @override
  bool get supportsLanguageDetection => false;

  @override
  Future<void> initialize(SttConfig config) async {
    _config = config;
    _controller ??= StreamController<SttEvent>.broadcast();
  }

  @override
  Future<void> startListening() async {
    if (_listening) return;
    final cfg = _config;
    if (cfg == null) {
      _emit(const SttEvent(
        type: SttEventType.error,
        errorCode: 'stt.not_initialized',
        errorMessage: 'initialize() must be called first',
      ));
      return;
    }
    if (cfg.apiKey.isEmpty || cfg.region.isEmpty) {
      _emit(const SttEvent(
        type: SttEventType.error,
        errorCode: 'auth_failed',
        errorMessage: 'apiKey or region missing',
      ));
      return;
    }

    _controller ??= StreamController<SttEvent>.broadcast();
    _requestId = _hex32();
    _firstAudioChunk = true;

    try {
      await _openSocket(cfg);
    } catch (e) {
      _emit(SttEvent(
        type: SttEventType.error,
        errorCode: 'network_error',
        errorMessage: 'STT connect failed: $e',
      ));
      return;
    }

    // speech.config（连接级配置）。
    _sendText('speech.config', _connectionId(), 'application/json',
        _speechConfigBody());

    // 启动麦克风。
    try {
      if (!await _recorder.hasPermission()) {
        _emit(const SttEvent(
          type: SttEventType.error,
          errorCode: 'permission_denied',
          errorMessage: 'microphone permission denied',
        ));
        await _closeSocket();
        return;
      }
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _listening = true;
      _emit(const SttEvent(type: SttEventType.listeningStarted));
      _micSub = stream.listen(
        (chunk) {
          if (!_listening) return;
          _sendAudio(chunk);
        },
        onError: (_) {},
      );
    } catch (e) {
      _emit(SttEvent(
        type: SttEventType.error,
        errorCode: 'permission_denied',
        errorMessage: 'record start failed: $e',
      ));
      await _closeSocket();
    }
  }

  @override
  Future<void> stopListening() async {
    if (!_listening) {
      await _closeSocket();
      return;
    }
    _listening = false;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    // 发送空音频帧通知服务端音频流结束。
    try {
      _sendAudio(Uint8List(0));
    } catch (_) {}
    _emit(const SttEvent(type: SttEventType.listeningStopped));
    await _closeSocket();
  }

  @override
  Stream<SttEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await stopListening();
    try {
      await _recorder.dispose();
    } catch (_) {}
    await _controller?.close();
    _controller = null;
    _config = null;
  }

  // ── WebSocket ──────────────────────────────────────────────────────────

  Future<void> _openSocket(SttConfig cfg) async {
    final lang = cfg.language.isEmpty ? 'zh-CN' : cfg.language;
    // 浏览器不能设 header，但桌面 IOWebSocket 可。web_socket_channel 的
    // connect 不直接支持 header，这里把订阅密钥与语言放 query；Azure 同时支持
    // `Ocp-Apim-Subscription-Key` query 形式。
    final url = 'wss://${cfg.region}.stt.speech.microsoft.com'
        '/speech/recognition/$_path/cognitiveservices/v1'
        '?language=${Uri.encodeQueryComponent(lang)}'
        '&format=simple'
        '&Ocp-Apim-Subscription-Key=${Uri.encodeQueryComponent(cfg.apiKey)}'
        '&X-ConnectionId=${_connectionId()}';

    final ws = WebSocketChannel.connect(Uri.parse(url));
    _socket = ws;
    await ws.ready.timeout(const Duration(seconds: 15));

    _socketSub = ws.stream.listen(
      _onMessage,
      onError: (Object err) {
        if (_listening) {
          _emit(SttEvent(
            type: SttEventType.error,
            errorCode: 'network_error',
            errorMessage: err.toString(),
          ));
        }
      },
      onDone: () {
        if (_listening) {
          _listening = false;
          _emit(const SttEvent(type: SttEventType.listeningStopped));
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

  void _onMessage(dynamic raw) {
    // 服务端通常发文本帧；忽略二进制（TTS-only 协议无二进制下行）。
    if (raw is! String) return;
    final sep = raw.indexOf('\r\n\r\n');
    if (sep < 0) return;
    final headerText = raw.substring(0, sep);
    final body = raw.substring(sep + 4);
    final path = _headerValue(headerText, 'Path');
    switch (path) {
      case 'turn.start':
        break;
      case 'speech.startDetected':
        _emit(const SttEvent(type: SttEventType.vadSpeechStart));
        break;
      case 'speech.hypothesis':
        final text = _jsonStr(body, 'Text');
        if (text.isNotEmpty) {
          _emit(SttEvent(type: SttEventType.partialResult, text: text));
        }
        break;
      case 'speech.endDetected':
        _emit(const SttEvent(type: SttEventType.vadSpeechEnd));
        break;
      case 'speech.phrase':
        final status = _jsonStr(body, 'RecognitionStatus');
        final text = _jsonStr(body, 'DisplayText');
        if (status == 'Success' && text.isNotEmpty) {
          _emit(SttEvent(
            type: SttEventType.finalResult,
            text: text,
            isFinal: true,
          ));
        }
        break;
      case 'turn.end':
        // 连续识别下一轮 turn 由服务端继续推送，无需关闭。
        break;
      default:
        break;
    }
  }

  // ── USP 帧编码 ─────────────────────────────────────────────────────────

  void _sendText(
      String path, String requestId, String contentType, String body) {
    final ws = _socket;
    if (ws == null) return;
    final ts = DateTime.now().toUtc().toIso8601String();
    final msg = 'Path: $path\r\n'
        'X-RequestId: $requestId\r\n'
        'X-Timestamp: $ts\r\n'
        'Content-Type: $contentType\r\n\r\n$body';
    try {
      ws.sink.add(msg);
    } catch (_) {}
  }

  void _sendAudio(Uint8List pcm) {
    final ws = _socket;
    if (ws == null) return;
    final ts = DateTime.now().toUtc().toIso8601String();
    final header = 'Path: audio\r\n'
        'X-RequestId: $_requestId\r\n'
        'X-Timestamp: $ts\r\n'
        'Content-Type: audio/x-wav\r\n';
    final headerBytes = ascii.encode(header);

    Uint8List audioBody;
    if (_firstAudioChunk && pcm.isNotEmpty) {
      // 首个音频帧需带 WAV/RIFF 头（16 kHz / 16-bit / mono）。
      audioBody = Uint8List.fromList([..._wavHeader(16000, 16, 1), ...pcm]);
      _firstAudioChunk = false;
    } else {
      audioBody = pcm;
    }

    final out = BytesBuilder();
    out.addByte((headerBytes.length >> 8) & 0xFF);
    out.addByte(headerBytes.length & 0xFF);
    out.add(headerBytes);
    out.add(audioBody);
    try {
      ws.sink.add(out.toBytes());
    } catch (_) {}
  }

  Uint8List _wavHeader(int sampleRate, int bits, int channels) {
    final byteRate = sampleRate * channels * bits ~/ 8;
    final blockAlign = channels * bits ~/ 8;
    final bd = ByteData(44);
    void str(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        bd.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    bd.setUint32(4, 0xFFFFFFFF, Endian.little); // streaming size placeholder
    str(8, 'WAVE');
    str(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, byteRate, Endian.little);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bits, Endian.little);
    str(36, 'data');
    bd.setUint32(40, 0xFFFFFFFF, Endian.little); // streaming size placeholder
    return bd.buffer.asUint8List();
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  String _speechConfigBody() => jsonEncode({
        'context': {
          'system': {'version': '1.0', 'name': 'ai-agent-client'},
          'os': {'platform': 'Desktop', 'name': 'Flutter', 'version': '1.0'},
        },
      });

  String _connectionId() => _requestId;

  String _headerValue(String headers, String key) {
    for (final line in headers.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      if (line.substring(0, idx).trim().toLowerCase() == key.toLowerCase()) {
        return line.substring(idx + 1).trim();
      }
    }
    return '';
  }

  String _jsonStr(String body, String key) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m[key] != null) return m[key].toString();
    } catch (_) {}
    return '';
  }

  String _hex32() {
    final rnd = math.Random();
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(rnd.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  void _emit(SttEvent e) {
    final c = _controller;
    if (c != null && !c.isClosed) c.add(e);
  }
}
