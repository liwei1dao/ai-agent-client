import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:web/web.dart' as web;

/// Web implementation backed by the browser's SpeechRecognition API.
///
/// Azure WebSocket STT would require implementing the proprietary binary
/// protocol in Dart; for web testing we use the browser's native recognizer
/// which gives equivalent streaming semantics (partial/final results, VAD).
/// The Azure config is still accepted so switching back to native Azure STT
/// on mobile is transparent.
class SttAzurePluginDart implements SttPlugin {
  JSObject? _recognition;
  StreamController<SttEvent>? _controller;
  bool _listening = false;

  @override
  Future<void> initialize(SttConfig config) async {
    _controller ??= StreamController<SttEvent>.broadcast();

    final ctor = _speechRecognitionCtor();
    if (ctor == null) {
      _emit(const SttEvent(
        type: SttEventType.error,
        errorCode: 'stt.not_supported',
        errorMessage: 'SpeechRecognition API not available in this browser',
      ));
      return;
    }

    final rec = ctor.callAsConstructor<JSObject>();
    rec['lang'] = config.language.toJS;
    rec['continuous'] = true.toJS;
    rec['interimResults'] = true.toJS;
    _recognition = rec;

    rec['onstart'] = ((JSAny _) {
      _listening = true;
      _emit(const SttEvent(type: SttEventType.listeningStarted));
    }).toJS;
    rec['onspeechstart'] = ((JSAny _) {
      _emit(const SttEvent(type: SttEventType.vadSpeechStart));
    }).toJS;
    rec['onspeechend'] = ((JSAny _) {
      _emit(const SttEvent(type: SttEventType.vadSpeechEnd));
    }).toJS;
    rec['onerror'] = ((JSObject evt) {
      final code = (evt['error'] as JSString?)?.toDart ?? 'unknown';
      _emit(SttEvent(
        type: SttEventType.error,
        errorCode: 'stt.$code',
        errorMessage: code,
      ));
    }).toJS;
    rec['onend'] = ((JSAny _) {
      _listening = false;
      _emit(const SttEvent(type: SttEventType.listeningStopped));
    }).toJS;
    rec['onresult'] = ((JSObject evt) {
      final results = evt['results'] as JSObject;
      final length = (results['length'] as JSNumber).toDartInt;
      for (var i = 0; i < length; i++) {
        final res = results[i.toString()] as JSObject;
        final isFinal = (res['isFinal'] as JSBoolean).toDart;
        final alt0 = res['0'] as JSObject;
        final transcript = (alt0['transcript'] as JSString).toDart;
        if (transcript.isEmpty) continue;
        _emit(SttEvent(
          type: isFinal ? SttEventType.finalResult : SttEventType.partialResult,
          text: transcript,
          isFinal: isFinal,
        ));
      }
    }).toJS;
  }

  @override
  Future<void> startListening() async {
    if (_recognition == null || _listening) return;
    try {
      _recognition!.callMethod('start'.toJS);
    } catch (e) {
      _emit(SttEvent(
        type: SttEventType.error,
        errorCode: 'stt.start_failed',
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> stopListening() async {
    if (_recognition == null || !_listening) return;
    try {
      _recognition!.callMethod('stop'.toJS);
    } catch (_) {}
  }

  @override
  Stream<SttEvent> get eventStream =>
      _controller?.stream ?? const Stream.empty();

  @override
  Future<void> dispose() async {
    await stopListening();
    await _controller?.close();
    _controller = null;
    _recognition = null;
  }

  void _emit(SttEvent e) => _controller?.add(e);

  JSFunction? _speechRecognitionCtor() {
    final window = web.window as JSObject;
    final sr = window['SpeechRecognition'];
    if (sr.isDefinedAndNotNull) return sr as JSFunction;
    final wsr = window['webkitSpeechRecognition'];
    if (wsr.isDefinedAndNotNull) return wsr as JSFunction;
    return null;
  }
}
