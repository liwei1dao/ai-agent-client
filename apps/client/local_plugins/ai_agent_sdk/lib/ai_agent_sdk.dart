/// AI Agent SDK 门面包。
///
/// 业务方只需 `import 'package:ai_agent_sdk/ai_agent_sdk.dart';` 即可访问：
///
/// - **接口层**：`ai_plugin_interface` + `device_plugin_interface` 的全部类型
///   （STT / TTS / LLM / STS / AST / Translation / MCP / Device）
/// - **容器层**：`agents_server` / `service_manager` / `translate_server` /
///   `assistant_server` / `device_manager` 五个调度入口
///
/// 厂商实现（`stt_*` / `tts_*` / `llm_*` / `sts_*` / `ast_*` / `translation_*`）
/// 由 `agents_server` 等容器透传依赖自动安装；它们在 native 层通过 Flutter
/// plugin attach 时自注册到 `NativeServiceRegistry`，业务方**不需要也不应该**
/// 直接 import 厂商包。
///
/// Agent 类型插件（`agent_chat` / `agent_sts_chat` / `agent_translate` /
/// `agent_ast_translate`）同理由本包列为依赖以触发 `NativeAgentRegistry`
/// 自注册。
library;

// 接口层
//
// 注意：`SttEvent` / `LlmEvent` / `TtsEvent` 在 `ai_plugin_interface` 与
// `agents_server` 中同名但语义不同——前者是原始厂商插件事件，后者是
// agent 级聚合事件（带 sessionId / requestId / kind）。umbrella 默认导出
// agent 级版本；写厂商插件的开发者请直接依赖 `ai_plugin_interface`。
export 'package:ai_plugin_interface/ai_plugin_interface.dart'
    hide SttEvent, LlmEvent, TtsEvent;
export 'package:device_plugin_interface/device_plugin_interface.dart';

// 容器层
export 'package:agents_server/agents_server.dart';
export 'package:service_manager/service_manager.dart';
export 'package:translate_server/translate_server.dart';
export 'package:assistant_server/assistant_server.dart';
export 'package:device_manager/device_manager.dart';
