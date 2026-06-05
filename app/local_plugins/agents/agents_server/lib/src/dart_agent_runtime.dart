import 'dart:async';

import 'agent_event.dart';
import 'agent_service_factory.dart';
import 'agents_server_api.dart';
import 'web/web_agent.dart';
import 'web/web_ast_translate_agent.dart';
import 'web/web_chat_agent.dart';
import 'web/web_sts_chat_agent.dart';
import 'web/web_translate_agent.dart';

/// 纯 Dart agent 运行时 —— web 与 desktop 共用。
///
/// 管理一组 [WebAgent] 实例（镜像 Android 的 Kotlin agent 运行时），通过注入的
/// [AgentServiceFactory] 构造各能力插件，使编排逻辑与具体厂商/平台解耦。
/// 公开 API 与移动端 MethodChannel 桥接保持一致（见 [AgentsServerApi]）。
class DartAgentRuntime implements AgentsServerApi {
  DartAgentRuntime(this._factory);

  final AgentServiceFactory _factory;

  final Map<String, WebAgent> _agents = {};
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();

  @override
  Stream<AgentEvent> get eventStream => _events.stream;

  WebAgent? _createAgentImpl(String type) {
    // Agent type strings 在所有平台一致：见 Android `NativeAgentRegistry.register`
    // 与 lib/core/voitrans_api.dart 的 VoitransAgent.type。
    switch (type) {
      case 'chat':
        return WebChatAgent(_events.add, _factory);
      case 'sts-chat':
        return WebStsChatAgent(_events.add, _factory);
      case 'translate':
        return WebTranslateAgent(_events.add, _factory);
      case 'ast-translate':
        return WebAstTranslateAgent(_events.add, _factory);
      default:
        return null;
    }
  }

  @override
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
    String? mcpServersJson,
    Map<String, String> extraParams = const {},
  }) async {
    // Release any existing agent with the same id.
    await _agents.remove(agentId)?.release();

    final agent = _createAgentImpl(agentType);
    if (agent == null) {
      _events.add(AgentErrorEvent(
        sessionId: agentId,
        errorCode: 'unknown_agent_type',
        message: 'No Dart implementation for agent type "$agentType"',
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
      mcpServersJson: mcpServersJson,
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

  @override
  Future<void> stopAgent(String agentId) async {
    await _agents.remove(agentId)?.release();
  }

  @override
  Future<void> deleteAgent(String agentId) => stopAgent(agentId);

  @override
  Future<void> sendText(String agentId, String requestId, String text) async {
    await _agents[agentId]?.sendText(requestId, text);
  }

  @override
  Future<void> setInputMode(String agentId, String mode) async {
    await _agents[agentId]?.setInputMode(mode);
  }

  @override
  Future<void> setAgentOption(String agentId, String key, String value) async {
    await _agents[agentId]?.setOption(key, value);
  }

  @override
  Future<void> startListening(String agentId) async {
    await _agents[agentId]?.startListening();
  }

  @override
  Future<void> stopListening(String agentId) async {
    await _agents[agentId]?.stopListening();
  }

  @override
  Future<void> interrupt(String agentId) async {
    await _agents[agentId]?.interrupt();
  }

  @override
  Future<void> pauseAudio(String agentId) => stopListening(agentId);

  @override
  Future<void> resumeAudio(String agentId) => startListening(agentId);

  @override
  Future<void> connectService(String agentId) async {
    await _agents[agentId]?.connectService();
  }

  @override
  Future<void> disconnectService(String agentId) async {
    await _agents[agentId]?.disconnectService();
  }

  @override
  Future<void> notifyAppForeground(bool isForeground) async {}

  @override
  Future<void> setAudioOutputMode(String mode) async {
    // 桌面/浏览器不暴露 earpiece/speaker 路由 —— no-op。
  }
}
