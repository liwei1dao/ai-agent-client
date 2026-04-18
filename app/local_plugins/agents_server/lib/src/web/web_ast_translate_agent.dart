import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// AST translate agent — bridges the AST recognition five-piece lifecycle
/// (see [ai.AstEventType]) onto the chat provider's [SttEvent] / [LlmEvent]
/// streams.
///
/// Mapping:
/// - `recognizing(source)`  → `SttEvent.partialResult` (text = snapshot)
/// - `recognized(source)`   → `SttEvent.finalResult`   (requestId, text = final)
/// - `recognizing(translated)` → `LlmEvent.firstToken` (textDelta = snapshot, requestId)
/// - `recognized(translated)`  → `LlmEvent.firstToken` (textDelta = final, requestId)
/// - `recognitionEnd`       → `LlmEvent.done`          (requestId, fullText = last translated)
class WebAstTranslateAgent implements WebAgent {
  WebAstTranslateAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.AstPlugin _ast;
  StreamSubscription<ai.AstEvent>? _sub;

  /// Last `recognized` text seen on the translated role of the current round —
  /// emitted as `LlmEvent.done.fullText` when the round closes.
  String _lastTranslatedText = '';
  String? _activeTranslationRequestId;

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

      case ai.AstEventType.disconnected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.disconnected,
        ));
        break;

      case ai.AstEventType.recognitionStart:
        // No-op — chat provider lazily creates the message on the first
        // partial / firstToken event.
        break;

      case ai.AstEventType.recognizing:
        _onRecognizing(e);
        break;

      case ai.AstEventType.recognized:
        _onRecognized(e);
        break;

      case ai.AstEventType.recognitionDone:
        // No-op — round-level closure is signalled by recognitionEnd.
        break;

      case ai.AstEventType.recognitionEnd:
        _onRecognitionEnd(e);
        break;

      case ai.AstEventType.recognitionError:
        _emit(AgentErrorEvent(
          sessionId: _config.agentId,
          errorCode: e.errorCode ?? 'ast_recognition_error',
          message: e.errorMessage ?? '',
          requestId: e.requestId,
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

  void _onRecognizing(ai.AstEvent e) {
    final text = e.text ?? '';
    if (text.isEmpty) return;
    switch (e.role) {
      case ai.AstRole.source:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.partialResult,
          text: text,
        ));
        break;
      case ai.AstRole.translated:
        final rid = e.requestId ?? '';
        if (rid.isEmpty) return;
        _activeTranslationRequestId = rid;
        _lastTranslatedText = text;
        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: rid,
          kind: LlmEventKind.firstToken,
          textDelta: text,
        ));
        break;
      case null:
        break;
    }
  }

  void _onRecognized(ai.AstEvent e) {
    final text = e.text ?? '';
    if (text.isEmpty) return;
    switch (e.role) {
      case ai.AstRole.source:
        final rid = e.requestId ?? '';
        if (rid.isEmpty) return;
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: rid,
          kind: SttEventKind.finalResult,
          text: text,
        ));
        break;
      case ai.AstRole.translated:
        final rid = e.requestId ?? '';
        if (rid.isEmpty) return;
        _activeTranslationRequestId = rid;
        _lastTranslatedText = text;
        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: rid,
          kind: LlmEventKind.firstToken,
          textDelta: text,
        ));
        break;
      case null:
        break;
    }
  }

  void _onRecognitionEnd(ai.AstEvent e) {
    final rid = _activeTranslationRequestId;
    if (rid != null && _lastTranslatedText.isNotEmpty) {
      _emit(LlmEvent(
        sessionId: _config.agentId,
        requestId: rid,
        kind: LlmEventKind.done,
        fullText: _lastTranslatedText,
      ));
    }
    _activeTranslationRequestId = null;
    _lastTranslatedText = '';
  }
}
