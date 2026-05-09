import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// Chat agent — STT + LLM + TTS pipeline. Ports ChatAgentSession.kt.
/// Message persistence is skipped on web; history is maintained in-memory only.
class WebChatAgent implements WebAgent {
  WebChatAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.SttPlugin _stt;
  late ai.LlmPlugin _llm;
  late ai.TtsPlugin _tts;

  StreamSubscription<ai.SttEvent>? _sttSub;
  StreamSubscription<ai.TtsEvent>? _ttsSub;

  final _gate = RequestGate();
  final List<ai.LlmMessage> _history = [];
  String _inputMode = 'text';
  AgentSessionState _state = AgentSessionState.idle;

  void _setState(AgentSessionState s, {String? requestId}) {
    _state = s;
    _emit(stateEvent(_config.agentId, s, requestId: requestId));
  }

  @override
  Future<void> initialize(WebAgentConfig config) async {
    _config = config;
    _inputMode = config.inputMode;

    _stt = WebServiceFactory.createStt(config.sttVendor ?? 'azure');
    _llm = WebServiceFactory.createLlm(config.llmVendor ?? 'openai');
    _tts = WebServiceFactory.createTts(config.ttsVendor ?? 'azure');

    await _stt.initialize(
      WebConfigParser.parseStt(config.sttConfigJson ?? '{}'),
    );
    await _llm.initialize(
      WebConfigParser.parseLlm(config.llmConfigJson ?? '{}'),
    );
    await _tts.initialize(
      WebConfigParser.parseTts(config.ttsConfigJson ?? '{}'),
    );

    _sttSub = _stt.eventStream.listen(_onStt);
    _ttsSub = _tts.eventStream.listen(_onTts);

    // Seed system prompt into history if present.
    final llmCfg = WebConfigParser.parseLlm(config.llmConfigJson ?? '{}');
    final sys = llmCfg.systemPrompt;
    if (sys != null && sys.isNotEmpty) {
      _history.add(ai.LlmMessage(role: ai.MessageRole.system, content: sys));
    }
  }

  @override
  Future<void> connectService() async {
    // 三段式 agent 无远端长连接：服务在 initialize 阶段已就位，立即上报 ready。
    _emit(AgentReadyEvent(sessionId: _config.agentId, ready: true));
  }

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
  Future<void> setOption(String key, String value) async {}

  @override
  Future<void> setInputMode(String mode) async {
    _inputMode = mode;
    _config.inputMode = mode;
    if (mode == 'call') {
      final id = _gate.current;
      if (id != null) _llm.cancel(id);
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
    final id = _gate.current;
    if (id != null) _llm.cancel(id);
    await _tts.stop();
    _gate.clear();
    _setState(AgentSessionState.idle);
  }

  @override
  Future<void> release() async {
    await _sttSub?.cancel();
    await _ttsSub?.cancel();
    await _stt.dispose();
    await _tts.dispose();
    await _llm.dispose();
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
    _history.add(ai.LlmMessage(role: ai.MessageRole.user, content: text));

    _setState(AgentSessionState.llm, requestId: requestId);

    final buffer = StringBuffer();
    try {
      await for (final event in _llm.chat(
        requestId: requestId,
        messages: _history,
      )) {
        if (!_gate.isActive(requestId)) return;
        switch (event.type) {
          case ai.LlmEventType.firstToken:
          case ai.LlmEventType.done:
            final delta = event.textDelta ?? '';
            if (delta.isNotEmpty) {
              buffer.write(delta);
              _emit(LlmEvent(
                sessionId: _config.agentId,
                requestId: requestId,
                kind: LlmEventKind.firstToken,
                textDelta: delta,
              ));
            }
            if (event.type == ai.LlmEventType.done) {
              final full = event.fullText ?? buffer.toString();
              _emit(LlmEvent(
                sessionId: _config.agentId,
                requestId: requestId,
                kind: LlmEventKind.done,
                fullText: full,
              ));
              if (full.isNotEmpty) {
                _history.add(ai.LlmMessage(
                  role: ai.MessageRole.assistant,
                  content: full,
                ));
              }
            }
            break;
          case ai.LlmEventType.thinking:
            _emit(LlmEvent(
              sessionId: _config.agentId,
              requestId: requestId,
              kind: LlmEventKind.thinking,
              thinkingDelta: event.thinkingDelta,
            ));
            break;
          case ai.LlmEventType.cancelled:
            _emit(LlmEvent(
              sessionId: _config.agentId,
              requestId: requestId,
              kind: LlmEventKind.cancelled,
            ));
            return;
          case ai.LlmEventType.error:
            _emit(LlmEvent(
              sessionId: _config.agentId,
              requestId: requestId,
              kind: LlmEventKind.error,
              errorCode: event.errorCode,
              errorMessage: event.errorMessage,
            ));
            return;
          case ai.LlmEventType.toolCallStart:
          case ai.LlmEventType.toolCallArguments:
          case ai.LlmEventType.toolCallResult:
            break;
        }
      }
    } catch (e) {
      _emit(LlmEvent(
        sessionId: _config.agentId,
        requestId: requestId,
        kind: LlmEventKind.error,
        errorCode: 'llm.exception',
        errorMessage: e.toString(),
      ));
      return;
    }

    if (!_gate.isActive(requestId)) return;

    final full = buffer.toString();
    if (full.isNotEmpty) {
      _setState(AgentSessionState.tts, requestId: requestId);
      await _tts.speak(full, requestId: requestId);
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
    final prev = _gate.current;
    if (prev != null) _llm.cancel(prev);
    _tts.stop();
    _gate.clear();
    _setState(AgentSessionState.listening);
  }
}
