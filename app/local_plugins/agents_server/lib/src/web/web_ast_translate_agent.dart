import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// AST translate agent — thin wrapper over the AST plugin. Ports AstTranslateAgentSession.kt.
class WebAstTranslateAgent implements WebAgent {
  WebAstTranslateAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.AstPlugin _ast;
  StreamSubscription<ai.AstEvent>? _sub;

  String? _currentTranslationId;
  String _currentTranslationText = '';
  String _pendingSourceText = '';

  @override
  Future<void> initialize(WebAgentConfig config) async {
    _config = config;
    _ast = WebServiceFactory.createAst(config.astVendor ?? 'volcengine');
    await _ast.initialize(
      WebConfigParser.parseAst(
        config.astConfigJson ?? '{}',
        srcLang: config.extraParams['srcLang'],
        dstLang: config.extraParams['dstLang'],
      ),
    );
  }

  @override
  Future<void> connectService() async {
    _sub?.cancel();
    _sub = _ast.eventStream.listen(_onAstEvent);
    try {
      await _ast.startCall();
    } catch (e) {
      _emit(AgentErrorEvent(
        sessionId: _config.agentId,
        errorCode: 'ast_connect_error',
        message: e.toString(),
      ));
    }
  }

  @override
  Future<void> disconnectService() async {
    await _ast.stopCall();
    _emit(ServiceConnectionStateEvent(
      sessionId: _config.agentId,
      connectionState: ServiceConnectionState.disconnected,
    ));
  }

  @override
  Future<void> sendText(String requestId, String text) async {
    // AST is voice-only; ignore text input.
  }

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> setInputMode(String mode) async {
    _config.inputMode = mode;
  }

  @override
  Future<void> interrupt() async {}

  @override
  Future<void> release() async {
    await _sub?.cancel();
    await _ast.dispose();
  }

  void _onAstEvent(ai.AstEvent e) {
    switch (e.type) {
      case ai.AstEventType.connected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.connected,
        ));
        break;
      case ai.AstEventType.sourceSubtitle:
        final text = e.text ?? '';
        _pendingSourceText = text;
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.partialResult,
          text: text,
        ));
        // When new source subtitle arrives, finalize any pending translation.
        _commitPendingTranslation();
        _commitPendingSource();
        break;
      case ai.AstEventType.translatedSubtitle:
        final text = e.text ?? '';
        final id = _currentTranslationId ?? newRequestId();
        _currentTranslationId = id;
        _currentTranslationText = text;
        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: id,
          kind: LlmEventKind.firstToken,
          textDelta: text,
        ));
        break;
      case ai.AstEventType.ttsAudioChunk:
        // Played internally by the AST plugin on web.
        break;
      case ai.AstEventType.disconnected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.disconnected,
        ));
        break;
      case ai.AstEventType.error:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.error,
          errorMessage: e.errorMessage,
        ));
        _emit(AgentErrorEvent(
          sessionId: _config.agentId,
          errorCode: e.errorCode ?? 'ast_error',
          message: e.errorMessage ?? '',
        ));
        break;
    }
  }

  void _commitPendingTranslation() {
    final id = _currentTranslationId;
    final text = _currentTranslationText;
    if (id != null && text.isNotEmpty) {
      _emit(LlmEvent(
        sessionId: _config.agentId,
        requestId: id,
        kind: LlmEventKind.done,
        fullText: text,
      ));
    }
    _currentTranslationId = null;
    _currentTranslationText = '';
  }

  void _commitPendingSource() {
    final text = _pendingSourceText;
    if (text.isEmpty) return;
    final rid = newRequestId();
    _emit(SttEvent(
      sessionId: _config.agentId,
      requestId: rid,
      kind: SttEventKind.finalResult,
      text: text,
    ));
    _pendingSourceText = '';
  }
}
