/// 对话专员：管家路由的兜底对话（id=chat）。
/// 每轮：载入会话 → 拼装 [system + KB上下文 + 历史窗口 + 本轮] → 流式 LLM → 记忆落库。
library;

import 'package:agent_kernel/agent_kernel.dart';

import 'messages.dart';
import 'llm.dart';

class ChatAgent extends SpecialistAgent {
  final LlmProvider llm;
  final SessionStore sessions;
  final String systemPrompt;

  /// 记忆窗口（轮数）。移动端可调；防止历史无限增长。
  final int windowTurns;

  ChatAgent({
    required this.llm,
    SessionStore? sessions,
    this.systemPrompt = '你是 UniHelper，用户的随身全能助手。回答简洁、有用、说中文。',
    this.windowTurns = 8,
  }) : sessions = sessions ?? InMemorySessionStore();

  @override
  AgentCapability get capability => const AgentCapability(
        id: 'chat',
        name: '对话',
        description: '通用多轮对话；管家未命中专项服务时的兜底。',
        keywords: [], // 作为 fallback 无需关键词
      );

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final sessionId = (task.params['sessionId'] as String?) ?? task.userId ?? 'default';
    final session = await sessions.load(sessionId, userId: task.userId);

    // 拼装本轮送给 LLM 的消息序列（system/上下文不入库，仅历史入库）。
    final msgs = <ChatMessage>[ChatMessage.system(systemPrompt)];
    final ctx = task.context;
    if (ctx != null && ctx.trim().isNotEmpty) {
      msgs.add(ChatMessage.system('可参考的用户资料/知识库：\n$ctx'));
    }
    msgs.addAll(session.window(windowTurns));
    msgs.add(ChatMessage.user(task.text));

    final buf = StringBuffer();
    try {
      await for (final chunk in llm.stream(msgs)) {
        buf.write(chunk);
        yield AgentPartial(chunk); // 流式转发给 UI
      }
    } catch (e) {
      yield AgentError('llm_failed', '$e');
      return;
    }

    final reply = buf.toString();
    // 落库：本轮一问一答进历史，供下轮记忆。
    session.add(ChatMessage.user(task.text));
    session.add(ChatMessage.assistant(reply));
    await sessions.save(session);

    yield AgentResult(text: reply);
  }
}
