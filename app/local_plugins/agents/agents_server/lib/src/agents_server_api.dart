import 'agent_event.dart';

/// agents_server 对外的统一命令/事件契约。
///
/// 三个平台后端都实现它，保证 UI 层平台无关：
/// - 移动端：MethodChannel → 原生 agent 运行时（`agents_server_bridge.dart`）；
/// - web / desktop：纯 Dart [DartAgentRuntime]。
///
/// 方法签名只在这里声明一次，避免在多个实现/分派类里重复罗列 createAgent 的长参数表。
abstract interface class AgentsServerApi {
  /// Native/Dart 运行时事件流（广播流，可多处监听）。
  Stream<AgentEvent> get eventStream;

  Future<void> createAgent({
    required String agentId,
    required String agentType,
    String inputMode,
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
    Map<String, String> extraParams,
  });

  Future<void> stopAgent(String agentId);
  Future<void> deleteAgent(String agentId);
  Future<void> sendText(String agentId, String requestId, String text);
  Future<void> setInputMode(String agentId, String mode);
  Future<void> setAgentOption(String agentId, String key, String value);
  Future<void> startListening(String agentId);
  Future<void> stopListening(String agentId);
  Future<void> interrupt(String agentId);
  Future<void> pauseAudio(String agentId);
  Future<void> resumeAudio(String agentId);
  Future<void> connectService(String agentId);
  Future<void> disconnectService(String agentId);
  Future<void> notifyAppForeground(bool isForeground);
  Future<void> setAudioOutputMode(String mode);
}
