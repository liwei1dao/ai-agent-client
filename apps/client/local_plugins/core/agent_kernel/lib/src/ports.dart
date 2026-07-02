/// 端口：专员 / 上下文提供者 / 路由。框架/平台按需实现或替换。
library;

import 'models.dart';

/// 专员（业务服务的编排外观）。现有 agent（对话/翻译/…）经适配器实现本接口接入。
abstract class SpecialistAgent {
  AgentCapability get capability;

  /// 处理管家分派的任务，回传事件流（可含 Partial/Progress/NeedConfirm，末以 Result/Error 收尾）。
  Stream<AgentEvent> handle(TaskEnvelope task);

  /// 自治触发（调度/唤醒）；默认无。
  Stream<AgentEvent> onTrigger(TriggerContext ctx) => Stream<AgentEvent>.empty();
}

/// 上下文提供者：管家每轮对话前取相关上下文注入（知识库 KnowledgeBusinessService 在此接入）。
abstract interface class ContextProvider {
  Future<String?> contextFor(String query, {String? userId});
}

/// 路由：把用户输入映射到一个/多个专员。
abstract interface class Router {
  Future<List<AgentId>> route(String text, List<AgentCapability> caps, {String? userId});
}

/// 可选 LLM 路由器（规则未命中时兜底）。
abstract interface class LlmRouter {
  Future<AgentId?> pick(String text, List<AgentCapability> caps);
}
