import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// STS chat agent — thin wrapper over the STS plugin. Ports StsChatAgentSession.kt.
class WebStsChatAgent implements WebAgent {
  WebStsChatAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.StsPlugin _sts;
  StreamSubscription<ai.StsEvent>? _sub;

  String? _currentAssistantId;

  @override
  Future<void> initialize(WebAgentConfig config) async {
    _config = config;
    _sts = WebServiceFactory.createSts(config.stsVendor ?? 'doubao');
    await _sts.initialize(
      WebConfigParser.parseSts(config.stsConfigJson ?? '{}'),
    );
  }

  @override
  Future<void> connectService() async {
    _sub?.cancel();
    _sub = _sts.eventStream.listen(_onStsEvent);
    try {
      await _sts.startCall();
    } catch (e) {
      _emit(AgentErrorEvent(
        sessionId: _config.agentId,
        errorCode: 'sts_connect_error',
        message: e.toString(),
      ));
    }
  }

  @override
  Future<void> disconnectService() async {
    await _sts.stopCall();
    _emit(ServiceConnectionStateEvent(
      sessionId: _config.agentId,
      connectionState: ServiceConnectionState.disconnected,
    ));
  }

  @override
  Future<void> sendText(String requestId, String text) async {
    // STS is voice-only; ignore text input.
  }

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Future<void> setInputMode(String mode) async {
    _config.inputMode = mode;
    // STS plugin manages mic lifecycle on web via startCall; no extra hooks.
  }

  @override
  Future<void> interrupt() async {
    // Rely on STS plugin's CLEAR_AUDIO handling; no direct API here.
  }

  @override
  Future<void> release() async {
    await _sub?.cancel();
    await _sts.dispose();
  }

  void _onStsEvent(ai.StsEvent e) {
    switch (e.type) {
      case ai.StsEventType.connected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.connected,
        ));
        break;
      case ai.StsEventType.audioChunk:
        // Web STS plays audio internally; nothing to do here.
        break;
      case ai.StsEventType.sentenceDone:
        final text = e.text ?? '';
        if (text.isEmpty) break;
        final id = _currentAssistantId ?? newRequestId();
        _currentAssistantId = id;
        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: id,
          kind: LlmEventKind.firstToken,
          textDelta: text,
        ));
        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: id,
          kind: LlmEventKind.done,
          fullText: text,
        ));
        _currentAssistantId = null;
        break;
      case ai.StsEventType.disconnected:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.disconnected,
        ));
        break;
      case ai.StsEventType.error:
        _emit(ServiceConnectionStateEvent(
          sessionId: _config.agentId,
          connectionState: ServiceConnectionState.error,
          errorMessage: e.errorMessage,
        ));
        _emit(AgentErrorEvent(
          sessionId: _config.agentId,
          errorCode: e.errorCode ?? 'sts_error',
          message: e.errorMessage ?? '',
        ));
        break;
    }
  }
}
