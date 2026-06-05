import 'agents_server_api.dart';
import 'dart_agent_runtime.dart';
import 'web/web_service_factory.dart';

/// Web implementation of [AgentsServerBridge]. 复用共享的纯 Dart 编排
/// [DartAgentRuntime]，注入浏览器侧的 [WebServiceFactory]。公开 API 与移动端
/// `agents_server_bridge.dart` 保持一致（见 [AgentsServerApi]），使 UI 层平台无关。
class AgentsServerBridge extends DartAgentRuntime {
  static final AgentsServerBridge _instance = AgentsServerBridge._();
  AgentsServerBridge._() : super(const WebServiceFactory());
  factory AgentsServerBridge() => _instance;
}
