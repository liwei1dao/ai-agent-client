import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// 厂商工厂抽象 —— 把 vendor 字符串映射到对应能力插件实例。
///
/// 纯 Dart 运行时（web / desktop）共用同一套 [DartAgentRuntime] 编排逻辑，
/// 唯一的平台差异是「能用哪些 vendor 实现」：
/// - web：`WebServiceFactory`（浏览器 API 实现，含 polychat 的 `_web.dart`）；
/// - desktop：`DesktopServiceFactory`（纯 Dart + record/audioplayers 音频）。
///
/// 上层编排（[DartAgentRuntime] / 各 agent）只依赖此接口，做到「无差别替换厂商」。
abstract interface class AgentServiceFactory {
  SttPlugin createStt(String vendor);
  TtsPlugin createTts(String vendor);
  LlmPlugin createLlm(String vendor);
  StsPlugin createSts(String vendor);
  AstPlugin createAst(String vendor);
  TranslationPlugin createTranslation(String vendor);

  /// MCP transport 选择（当前仅 streamable_http / http）。
  McpPlugin createMcp(String transport);
}
