import 'dart:async';
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

/// 桌面（macOS / Windows / Linux）Azure TTS 实现。
///
/// 与 web 版同构：调用 Azure Speech REST 端点合成 MP3，再用 [audioplayers] 的
/// [BytesSource] 播放（替代 web 的 HTMLAudioElement），从而拿到 playbackStart /
/// progress / done 事件。合成逻辑（SSML + REST）与 web 完全一致。
class TtsAzureDesktop implements TtsPlugin {
  TtsConfig? _config;
  StreamController<TtsEvent>? _controller;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<void>? _completeSub;

  bool _interrupted = false;
  bool _wired = false;

  @override
  Future<void> initialize(TtsConfig config) async {
    _config = config;
    _controller ??= StreamController<TtsEvent>.broadcast();
    _wirePlayer();
  }

  void _wirePlayer() {
    if (_wired) return;
    _wired = true;
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        _emit(const TtsEvent(type: TtsEventType.playbackStart));
      }
    });
    _posSub = _player.onPositionChanged.listen((pos) {
      _emit(TtsEvent(
        type: TtsEventType.playbackProgress,
        progressMs: pos.inMilliseconds,
      ));
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      _emit(const TtsEvent(type: TtsEventType.playbackDone));
    });
  }

  @override
  Future<void> speak(String text, {String? requestId}) async {
    final cfg = _config;
    if (cfg == null) {
      _emit(const TtsEvent(
        type: TtsEventType.error,
        errorCode: 'tts.not_initialized',
        errorMessage: 'Plugin not initialized',
      ));
      return;
    }
    _controller ??= StreamController<TtsEvent>.broadcast();
    _wirePlayer();

    // 新一轮合成前先打断上一轮播放。
    await _stopInternal(interrupted: true);
    _interrupted = false;

    _emit(const TtsEvent(type: TtsEventType.synthesisStart));
    try {
      final bytes = await _synthesize(cfg, text);
      if (_interrupted) return;
      _emit(const TtsEvent(type: TtsEventType.synthesisReady));
      await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    } catch (e) {
      _emit(TtsEvent(
        type: TtsEventType.error,
        errorCode: 'tts.synthesis_failed',
        errorMessage: e.toString(),
      ));
    }
  }

  Future<Uint8List> _synthesize(TtsConfig cfg, String text) async {
    final endpoint =
        'https://${cfg.region}.tts.speech.microsoft.com/cognitiveservices/v1';
    final voice = cfg.voiceName;
    final lang = voice.contains('-')
        ? voice.substring(0, voice.indexOf('-', voice.indexOf('-') + 1))
        : 'zh-CN';
    final ssml = '''
<speak version='1.0' xml:lang='$lang'>
  <voice xml:lang='$lang' name='$voice'>${_escape(text)}</voice>
</speak>''';

    final resp = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Ocp-Apim-Subscription-Key': cfg.apiKey,
        'Content-Type': 'application/ssml+xml',
        'X-Microsoft-OutputFormat': cfg.outputFormat,
        'User-Agent': 'ai-agent-client',
      },
      body: ssml,
    );
    if (resp.statusCode != 200) {
      throw Exception('Azure TTS ${resp.statusCode}: ${resp.body}');
    }
    return resp.bodyBytes;
  }

  @override
  Future<void> stop() => _stopInternal(interrupted: true);

  Future<void> _stopInternal({required bool interrupted}) async {
    _interrupted = interrupted;
    try {
      await _player.stop();
    } catch (_) {}
    if (interrupted) {
      _emit(const TtsEvent(type: TtsEventType.playbackInterrupted));
    }
  }

  @override
  Stream<TtsEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await _stopInternal(interrupted: false);
    await _stateSub?.cancel();
    await _posSub?.cancel();
    await _completeSub?.cancel();
    await _player.dispose();
    await _controller?.close();
    _controller = null;
    _config = null;
  }

  void _emit(TtsEvent e) => _controller?.add(e);

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&apos;')
      .replaceAll('"', '&quot;');
}
