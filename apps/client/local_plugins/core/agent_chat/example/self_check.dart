// 对话内核自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_chat/agent_chat.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

/// 记录型 LLM：捕获最近一次收到的消息序列，便于断言上下文/历史拼装是否正确。
class RecordingLlm implements LlmProvider {
  List<ChatMessage> last = const [];
  final String reply;
  RecordingLlm(this.reply);
  @override
  Stream<String> stream(List<ChatMessage> messages) async* {
    last = List.of(messages);
    yield reply;
  }
  bool sawUserText(String s) => last.any((m) => m.role == Role.user && m.text.contains(s));
  bool sawSystemText(String s) => last.any((m) => m.role == Role.system && m.text.contains(s));
}

TaskEnvelope task(String text, {String? context, String? userId, String? sessionId}) => TaskEnvelope(
      taskId: 't', requestId: 'r', from: 'manager', to: 'chat', intent: 'chat',
      text: text, context: context, userId: userId,
      params: sessionId != null ? {'sessionId': sessionId} : const {},
    );

Future<(List<String>, AgentResult?)> run(ChatAgent a, TaskEnvelope t) async {
  final partials = <String>[];
  AgentResult? res;
  await for (final e in a.handle(t)) {
    if (e is AgentPartial) partials.add(e.text);
    if (e is AgentResult) res = e;
  }
  return (partials, res);
}

Future<void> main() async {
  stdout.writeln('▶ 基础对话 + 流式');
  {
    final a = ChatAgent(llm: const ScriptedLlm({'你好': '你好，我是 UniHelper。'}));
    final (partials, res) = await run(a, task('你好呀'));
    check(res != null && res.text == '你好，我是 UniHelper。', '按剧本回复正确');
    check(partials.isNotEmpty, '有流式分片(AgentPartial)先于结果');
  }

  stdout.writeln('▶ 多轮记忆（第二轮能看到第一轮）');
  {
    final rec = RecordingLlm('好的');
    final a = ChatAgent(llm: rec);
    await run(a, task('记住：我叫李伟', sessionId: 's1'));
    await run(a, task('我叫什么？', sessionId: 's1'));
    check(rec.sawUserText('李伟'), '第二轮送给 LLM 的消息里含第一轮「李伟」→ 记忆生效');
    check(rec.sawUserText('我叫什么'), '同时含本轮问题');
  }

  stdout.writeln('▶ 知识库上下文注入');
  {
    final rec = RecordingLlm('嗯');
    final a = ChatAgent(llm: rec);
    await run(a, task('我职业是啥', context: '李伟是一名软件工程师。', sessionId: 's2'));
    check(rec.sawSystemText('软件工程师'), 'task.context 作为 system 资料注入 LLM');
  }

  stdout.writeln('▶ 记忆窗口裁剪（windowTurns=2）');
  {
    final rec = RecordingLlm('ok');
    final a = ChatAgent(llm: rec, windowTurns: 2);
    for (var i = 1; i <= 5; i++) {
      await run(a, task('第$i句', sessionId: 's3'));
    }
    // 窗口=2 轮 → 最多带最近 4 条历史 + 本轮1条 user；更早的「第1句」应被裁掉。
    check(!rec.sawUserText('第1句'), '超窗口的早期历史被裁剪');
    check(rec.sawUserText('第4句') && rec.sawUserText('第5句'), '最近两轮仍在窗口内');
  }

  stdout.writeln('▶ 会话隔离（不同 sessionId 互不串味）');
  {
    final rec = RecordingLlm('ok');
    final a = ChatAgent(llm: rec);
    await run(a, task('A的秘密', sessionId: 'A'));
    await run(a, task('继续', sessionId: 'B'));
    check(!rec.sawUserText('A的秘密'), 'B 会话看不到 A 会话历史');
  }

  stdout.writeln('▶ 端到端：管家兜底 fallback=chat 现在真的能应答');
  {
    final mgr = Manager(router: const RuleRouter()); // fallback 默认 'chat'
    mgr.register(ChatAgent(llm: const ScriptedLlm({'讲个笑话': '为什么程序员分不清万圣节和圣诞节？因为 Oct 31 == Dec 25。'})));
    final reply = await mgr.handle('给我讲个笑话');
    check(reply.usedAgents.join(',') == 'chat', '未命中专项 → 路由到 chat 专员');
    check(reply.text.contains('程序员'), '管家汇总出对话回复（此前 fallback 落空洞，现已补上）');
  }

  stdout.writeln('\n✅ 对话内核通过：流式 · 多轮记忆 · KB上下文注入 · 窗口裁剪 · 会话隔离 · 管家兜底闭环。');
}
