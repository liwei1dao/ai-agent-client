// 管家骨架自检（端到端，零外部依赖）。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

// ── 假专员 ──────────────────────────────────────────────
class ChatAgent extends SpecialistAgent {
  @override
  AgentCapability get capability => const AgentCapability(
        id: 'chat', name: '对话', keywords: ['聊', '你好', '介绍'], triggers: ['hotword']);
  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final withCtx = task.context != null ? '（据你的知识库：${task.context}）' : '';
    yield AgentResult(text: '好的，我在。$withCtx');
  }
}

class TranslateAgent extends SpecialistAgent {
  @override
  AgentCapability get capability =>
      const AgentCapability(id: 'translate', name: '翻译', keywords: ['翻译', 'translate']);
  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    yield const AgentResult(text: 'translated: hello world');
  }
}

class EmailAgent extends SpecialistAgent {
  @override
  AgentCapability get capability =>
      const AgentCapability(id: 'email', name: '邮件', keywords: ['邮件', '回复']);
  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    yield AgentProgress('起草中…');
    yield const AgentNeedConfirm(Confirm(
      id: 'c1', actionKind: 'send_email',
      summary: '给张总回复：同意条款三', preview: {'to': '张总', 'body': '同意，可推进'},
    ));
  }
}

class ScheduleAgent extends SpecialistAgent {
  @override
  AgentCapability get capability => const AgentCapability(
      id: 'schedule', name: '日程', keywords: ['日程', '提醒', '会', '安排'], triggers: ['device', 'hotword']);
  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    yield AgentResult(text: '已为你创建日程：${task.text}');
  }
}

// 假"现有 agent"运行器：模拟对话 agent 流式 chunk（对应 onLlmChunk → onLlmDone）
class FakeChatRunner implements LegacyAgentRunner {
  @override
  Stream<RunnerEvent> run(String text, {String? context, String? userId}) async* {
    yield RunnerEvent.chunk('这是');
    yield RunnerEvent.chunk('答案');
    yield RunnerEvent.done();
  }
}

// 知识库上下文提供者（假）
class FakeKb implements ContextProvider {
  @override
  Future<String?> contextFor(String query, {String? userId}) async {
    if (query.contains('密码') || query.contains('路由器')) return '管理密码 admin8899';
    return null;
  }
}

Future<void> main() async {
  final mgr = Manager(router: const RuleRouter(fallback: 'chat'), contextProvider: FakeKb())
    ..register(ChatAgent())
    ..register(TranslateAgent())
    ..register(EmailAgent())
    ..register(ScheduleAgent());

  check(mgr.capabilities.length == 4, '注册 4 个专员');

  stdout.writeln('▶ 意图路由');
  final r1 = await mgr.handle('帮我翻译 hello world');
  check(r1.usedAgents.contains('translate'), '“帮我翻译…” → 路由到 translate');
  check(r1.text.contains('translated'), '译文回传');

  final r2 = await mgr.handle('随便聊两句');
  check(r2.usedAgents.join(',') == 'chat', '闲聊 → chat');

  final r3 = await mgr.handle('讲个笑话呗');
  check(r3.usedAgents.join(',') == 'chat', '无关键词 → 兜底 chat');

  stdout.writeln('▶ 安全闸口（确认）');
  final r4 = await mgr.handle('给张总回复邮件说同意');
  check(r4.needsConfirm, '邮件发送 → 需用户确认（pendingConfirm）');
  check(r4.pendingConfirm!.actionKind == 'send_email', '确认动作类型正确');

  stdout.writeln('▶ 上下文注入（知识库）');
  final r5 = await mgr.handle('我家路由器密码是多少');
  check(r5.text.contains('admin8899'), '管家把 KB 上下文注入给专员');

  stdout.writeln('▶ 服务级唤醒');
  final bus = WakeBus();
  ManagerReply? woke;
  bus.on((e) async {
    woke = await mgr.onWake(e);
  });
  await bus.emit(const WakeEvent(
      source: WakeSource.device, sourceId: 'buds-01', utterance: '加个明早十点的会'));
  check(woke != null && woke!.usedAgents.contains('schedule'),
      '设备唤醒“加个明早十点的会” → schedule（无 UI 也走通）');

  stdout.writeln('▶ 现有 agent 经适配器纳管（SpecialistAdapter + LegacyAgentRunner）');
  mgr.register(SpecialistAdapter(
    const AgentCapability(id: 'explain', name: '讲解', keywords: ['讲讲', '解释', '什么是']),
    FakeChatRunner(),
  ));
  final ra = await mgr.handle('讲讲量子力学');
  check(ra.usedAgents.contains('explain'), '适配器专员被路由');
  check(ra.text == '这是答案', '流式 chunk 经适配器汇总为最终结果');

  stdout.writeln('\n✅ 全部通过：注册 · 路由 · 多专员汇总一个声音 · 确认闸口 · 上下文注入 · 服务级唤醒 · 适配器纳管。');
}
