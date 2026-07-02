/// 规则 + LLM 兜底路由（MVP）。
library;

import 'models.dart';
import 'ports.dart';

/// 关键词命中 → 候选专员；未命中 → LLM 兜底 → 再不行落 [fallback]（默认对话）。
class RuleRouter implements Router {
  final AgentId fallback;
  final LlmRouter? llm;

  const RuleRouter({this.fallback = 'chat', this.llm});

  @override
  Future<List<AgentId>> route(String text, List<AgentCapability> caps, {String? userId}) async {
    final lower = text.toLowerCase();
    final matched = <AgentId>[
      for (final c in caps)
        if (c.keywords.any((k) => lower.contains(k.toLowerCase()))) c.id,
    ];
    if (matched.isNotEmpty) return matched;

    final byLlm = await llm?.pick(text, caps);
    if (byLlm != null) return [byLlm];

    return [fallback];
  }
}
