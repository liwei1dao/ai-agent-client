import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

/// Web implementation of Azure TTS — calls the Azure Speech REST endpoint
/// to synthesize audio, then plays the MP3 via an HTMLAudioElement so we get
/// playback events (timeupdate, ended) for free without decoding PCM.
class TtsAzurePluginDart implements TtsPlugin {
  TtsConfig? _config;
  StreamController<TtsEvent>? _controller;
  web.HTMLAudioElement? _audio;
  Timer? _progressTimer;
  bool _interrupted = false;

  @override
  Future<void> initialize(TtsConfig config) async {
    _config = config;
    _controller ??= StreamController<TtsEvent>.broadcast();
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
    await _stopInternal(interrupted: true);
    _interrupted = false;

    _emit(const TtsEvent(type: TtsEventType.synthesisStart));

    try {
      final bytes = await _synthesize(cfg, text);
      if (_interrupted) return;
      _emit(const TtsEvent(type: TtsEventType.synthesisReady));
      await _play(bytes);
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

  Future<void> _play(Uint8List bytes) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'audio/mpeg'),
    );
    final url = web.URL.createObjectURL(blob);
    final audio = web.HTMLAudioElement();
    audio.src = url;
    _audio = audio;

    final startCompleter = Completer<void>();
    audio['onplay'] = ((JSAny _) {
      _emit(const TtsEvent(type: TtsEventType.playbackStart));
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        final ms = (audio.currentTime * 1000).round();
        _emit(TtsEvent(type: TtsEventType.playbackProgress, progressMs: ms));
      });
      if (!startCompleter.isCompleted) startCompleter.complete();
    }).toJS;
    audio['onended'] = ((JSAny _) {
      _progressTimer?.cancel();
      _emit(const TtsEvent(type: TtsEventType.playbackDone));
      web.URL.revokeObjectURL(url);
    }).toJS;
    audio['onerror'] = ((JSAny _) {
      _progressTimer?.cancel();
      _emit(const TtsEvent(
        type: TtsEventType.error,
        errorCode: 'tts.playback_failed',
        errorMessage: 'Audio element error',
      ));
      web.URL.revokeObjectURL(url);
      if (!startCompleter.isCompleted) startCompleter.complete();
    }).toJS;

    final playPromise = audio.play();
    try {
      await playPromise.toDart;
    } catch (e) {
      _emit(TtsEvent(
        type: TtsEventType.error,
        errorCode: 'tts.autoplay_blocked',
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> stop() => _stopInternal(interrupted: true);

  Future<void> _stopInternal({required bool interrupted}) async {
    _interrupted = interrupted;
    _progressTimer?.cancel();
    _progressTimer = null;
    final a = _audio;
    _audio = null;
    if (a != null) {
      try {
        a.pause();
      } catch (_) {}
      if (interrupted) {
        _emit(const TtsEvent(type: TtsEventType.playbackInterrupted));
      }
    }
  }

  @override
  Stream<TtsEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await _stopInternal(interrupted: false);
    await _controller?.close();
    _controller = null;
    _config = null;
  }

  static Future<void> setAudioOutputMode(String mode) async {
    // Browsers don't expose earpiece/speaker routing; ignore.
  }

  void _emit(TtsEvent e) => _controller?.add(e);

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll("'", '&apos;')
      .replaceAll('"', '&quot;');
}
