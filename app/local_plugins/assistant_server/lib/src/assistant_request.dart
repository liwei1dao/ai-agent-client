import 'package:flutter/foundation.dart';

/// AI 助理请求。
///
/// 单 chat agent 的会话：
/// - 用户说 [userLanguage] → 上行 PCM → chat agent 做 STT → LLM → TTS → 回灌耳机扬声器。
///
/// [agentType] 与 NativeAgentRegistry 注册的 type 对齐（当前为 `chat`）。
/// [agentConfig] 是 agent 的 native config map，shape 与 `NativeAgentConfig.fromMap`
/// 一致：`{agentId, inputMode, sttVendor, sttConfigJson, llmVendor, llmConfigJson, ttsVendor, ttsConfigJson, ...}`。
@immutable
class AssistantRequest {
  const AssistantRequest({
    required this.agentType,
    required this.agentConfig,
    required this.userLanguage,
    this.sessionId,
  });

  final String agentType;
  final Map<String, Object?> agentConfig;

  /// ISO 639-3 / IETF BCP-47 语言标签（仅作信息位透传）。
  final String userLanguage;

  /// 显式 sessionId；不传则由 native 生成。
  final String? sessionId;
}
