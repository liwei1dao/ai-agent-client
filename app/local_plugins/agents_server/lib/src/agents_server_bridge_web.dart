import 'dart:async';

import 'agent_event.dart';
import 'web/web_agent.dart';
import 'web/web_ast_translate_agent.dart';
import 'web/web_chat_agent.dart';
import 'web/web_sts_chat_agent.dart';
import 'web/web_translate_agent.dart';

/// Web implementation of [AgentsServerBridge]. Manages Dart-native agent
/// instances that mirror the Kotlin agent runtime on Android. Public API must
/// stay identical to `src/agents_server_bridge.dart` so the UI layer is
/// platform-agnostic.
class AgentsServerBridge {
  static final AgentsServerBridge _instance = AgentsServerBridge._();
  AgentsServerBridge._();
  factory AgentsServerBridge() => _instance;

  final Map<String, WebAgent> _agents = {};
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  Stream<AgentEvent> get eventStream => _events.stream;

  WebAgent? _createAgentImpl(String type) {
    // Agent type strings are canonical on both platforms: see
    // `NativeAgentRegistry.register("sts-chat" | "ast-translate" | ...)` on
    // Android and `VoitransAgent.type` in lib/core/voitrans_api.dart.
    switch (type) {
      case 'chat':
        return WebChatAgent(_events.add);
      case 'sts-chat':
        return WebStsChatAgent(_events.add);
      case 'translate':
        return WebTranslateAgent(_events.add);
      case 'ast-translate':
        return WebAstTranslateAgent(_events.add);
      default:
        return null;
    }
  }

  Future<void> createAgent({
    required String agentId,
    required String agentType,
    String inputMode = 'text',
    String? sttVendor,
    String? ttsVendor,
    String? llmVendor,
    String? stsVendor,
    String? astVendor,
    String? translationVendor,
    String? sttConfigJson,
    String? ttsConfigJson,
    String? llmConfigJson,
    String? stsConfigJson,
    String? astConfigJson,
    String? translationConfigJson,
    Map<String, String> extraParams = const {},
  }) async {
    // Release any existing agent with the same id.
    await _agents.remove(agentId)?.release();

    final agent = _createAgentImpl(agentType);
    if (agent == null) {
      _events.add(AgentErrorEvent(
        sessionId: agentId,
        errorCode: 'unknown_agent_type',
        message: 'No web implementation for agent type "$agentType"',
      ));
      return;
    }

    final config = WebAgentConfig(
      agentId: agentId,
      inputMode: inputMode,
      sttVendor: sttVendor,
      ttsVendor: ttsVendor,
      llmVendor: llmVendor,
      stsVendor: stsVendor,
      astVendor: astVendor,
      translationVendor: translationVendor,
      sttConfigJson: sttConfigJson,
      ttsConfigJson: ttsConfigJson,
      llmConfigJson: llmConfigJson,
      stsConfigJson: stsConfigJson,
      astConfigJson: astConfigJson,
      translationConfigJson: translationConfigJson,
      extraParams: extraParams,
    );

    try {
      await agent.initialize(config);
      _agents[agentId] = agent;
    } catch (e) {
      _events.add(AgentErrorEvent(
        sessionId: agentId,
        errorCode: 'agent_init_failed',
        message: e.toString(),
      ));
    }
  }

  Future<void> stopAgent(String agentId) async {
    await _agents.remove(agentId)?.release();
  }

  Future<void> deleteAgent(String agentId) => stopAgent(agentId);

  Future<void> sendText(String agentId, String requestId, String text) async {
    await _agents[agentId]?.sendText(requestId, text);
  }

  Future<void> setInputMode(String agentId, String mode) async {
    await _agents[agentId]?.setInputMode(mode);
  }

  Future<void> startListening(String agentId) async {
    await _agents[agentId]?.startListening();
  }

  Future<void> stopListening(String agentId) async {
    await _agents[agentId]?.stopListening();
  }

  Future<void> interrupt(String agentId) async {
    await _agents[agentId]?.interrupt();
  }

  Future<void> pauseAudio(String agentId) => stopListening(agentId);

  Future<void> resumeAudio(String agentId) => startListening(agentId);

  Future<void> connectService(String agentId) async {
    await _agents[agentId]?.connectService();
  }

  Future<void> disconnectService(String agentId) async {
    await _agents[agentId]?.disconnectService();
  }

  Future<void> notifyAppForeground(bool isForeground) async {}

  Future<void> setAudioOutputMode(String mode) async {
    // Browsers don't expose earpiece/speaker routing — no-op.
  }
}
