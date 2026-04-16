import 'dart:async';
import 'dart:convert';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// Translate agent — STT + Translation + TTS pipeline. Ports TranslateAgentSession.kt.
class WebTranslateAgent implements WebAgent {
  WebTranslateAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.SttPlugin _stt;
  late ai.TranslationPlugin _translation;
  late ai.TtsPlugin _tts;

  StreamSubscription<ai.SttEvent>? _sttSub;
  StreamSubscription<ai.TtsEvent>? _ttsSub;

  final _gate = RequestGate();
  String _inputMode = 'text';
  AgentSessionState _state = AgentSessionState.idle;
  String? _srcLang;
  String _dstLang = 'en';

  void _setState(AgentSessionState s, {String? requestId}) {
    _state = s;
    _emit(stateEvent(_config.agentId, s, requestId: requestId));
  }

  @override
  Future<void> initialize(WebAgentConfig config) async {
    _config = config;
    _inputMode = config.inputMode;
    _srcLang = config.extraParams['srcLang'];
    _dstLang = config.extraParams['dstLang'] ?? 'en';

    _stt = WebServiceFactory.createStt(config.sttVendor ?? 'azure');
    _translation = WebServiceFactory.createTranslation(
      config.translationVendor ?? 'deepl',
    );
    _tts = WebServiceFactory.createTts(config.ttsVendor ?? 'azure');

    await _stt.initialize(
      WebConfigParser.parseStt(config.sttConfigJson ?? '{}'),
    );
    final tCfg = config.translationConfigJson ?? '{}';
    final tMap = _decodeJson(tCfg);
    await _translation.initialize(
      apiKey: (tMap['apiKey'] as String?) ?? '',
      extra: {
        for (final e in (tMap['extra'] as Map? ?? {}).entries)
          e.key.toString(): e.value?.toString() ?? '',
      },
    );
    await _tts.initialize(
      WebConfigParser.parseTts(config.ttsConfigJson ?? '{}'),
    );

    _sttSub = _stt.eventStream.listen(_onStt);
    _ttsSub = _tts.eventStream.listen(_onTts);
  }

  @override
  Future<void> connectService() async {}

  @override
  Future<void> disconnectService() async {}

  @override
  Future<void> sendText(String requestId, String text) =>
      _runPipeline(requestId, text);

  @override
  Future<void> startListening() async {
    _setState(AgentSessionState.listening);
    await _stt.startListening();
  }

  @override
  Future<void> stopListening() async => _stt.stopListening();

  @override
  Future<void> setInputMode(String mode) async {
    _inputMode = mode;
    _config.inputMode = mode;
    if (mode == 'call') {
      await _tts.stop();
      _gate.clear();
      _setState(AgentSessionState.listening);
      await _stt.startListening();
    } else if (mode == 'text') {
      await _stt.stopListening();
    }
  }

  @override
  Future<void> interrupt() async {
    await _tts.stop();
    _gate.clear();
    _setState(AgentSessionState.idle);
  }

  @override
  Future<void> release() async {
    await _sttSub?.cancel();
    await _ttsSub?.cancel();
    await _stt.dispose();
    await _translation.dispose();
    await _tts.dispose();
  }

  void _onStt(ai.SttEvent e) {
    switch (e.type) {
      case ai.SttEventType.listeningStarted:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.listeningStarted,
        ));
        break;
      case ai.SttEventType.vadSpeechStart:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.vadSpeechStart,
        ));
        _interruptForVoiceInput();
        break;
      case ai.SttEventType.vadSpeechEnd:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.vadSpeechEnd,
        ));
        break;
      case ai.SttEventType.partialResult:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.partialResult,
          text: e.text,
        ));
        break;
      case ai.SttEventType.finalResult:
        final rid = newRequestId();
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: rid,
          kind: SttEventKind.finalResult,
          text: e.text,
        ));
        if (_inputMode == 'call' && (e.text ?? '').isNotEmpty) {
          _runPipeline(rid, e.text!);
        }
        break;
      case ai.SttEventType.listeningStopped:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.listeningStopped,
        ));
        break;
      case ai.SttEventType.error:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.error,
          errorCode: e.errorCode,
          errorMessage: e.errorMessage,
        ));
        break;
    }
  }

  void _onTts(ai.TtsEvent e) {
    final rid = _gate.current ?? '';
    final kind = switch (e.type) {
      ai.TtsEventType.synthesisStart => TtsEventKind.synthesisStart,
      ai.TtsEventType.synthesisReady => TtsEventKind.synthesisReady,
      ai.TtsEventType.playbackStart => TtsEventKind.playbackStart,
      ai.TtsEventType.playbackProgress => TtsEventKind.playbackProgress,
      ai.TtsEventType.playbackDone => TtsEventKind.playbackDone,
      ai.TtsEventType.playbackInterrupted => TtsEventKind.playbackInterrupted,
      ai.TtsEventType.error => TtsEventKind.error,
    };
    _emit(TtsEvent(
      sessionId: _config.agentId,
      requestId: rid,
      kind: kind,
      progressMs: e.progressMs,
      durationMs: e.durationMs,
      errorCode: e.errorCode,
      errorMessage: e.errorMessage,
    ));
  }

  Future<void> _runPipeline(String requestId, String text) async {
    _gate.start(requestId);
    _setState(AgentSessionState.llm, requestId: requestId);
    _emit(LlmEvent(
      sessionId: _config.agentId,
      requestId: requestId,
      kind: LlmEventKind.firstToken,
      textDelta: '',
    ));

    ai.TranslationResult result;
    try {
      result = await _translation.translate(
        text: text,
        targetLanguage: _dstLang,
        sourceLanguage: _srcLang,
      );
    } catch (e) {
      _emit(LlmEvent(
        sessionId: _config.agentId,
        requestId: requestId,
        kind: LlmEventKind.error,
        errorCode: 'translation_error',
        errorMessage: e.toString(),
      ));
      _setState(AgentSessionState.error);
      return;
    }

    if (!_gate.isActive(requestId)) return;

    final translated = result.translatedText;
    _emit(LlmEvent(
      sessionId: _config.agentId,
      requestId: requestId,
      kind: LlmEventKind.done,
      fullText: translated,
    ));

    if (!_gate.isActive(requestId)) return;

    if (translated.isNotEmpty) {
      _setState(AgentSessionState.tts, requestId: requestId);
      await _tts.speak(translated, requestId: requestId);
    }

    if (_gate.isActive(requestId)) {
      _setState(AgentSessionState.idle);
      if (_inputMode == 'call') {
        _setState(AgentSessionState.listening);
        await _stt.startListening();
      }
    }
  }

  void _interruptForVoiceInput() {
    if (_state == AgentSessionState.idle ||
        _state == AgentSessionState.listening) {
      return;
    }
    _tts.stop();
    _gate.clear();
    _setState(AgentSessionState.listening);
  }

  Map<String, dynamic> _decodeJson(String s) {
    if (s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }
}
