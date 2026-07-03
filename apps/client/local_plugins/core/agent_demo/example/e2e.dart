// UniHelper 端到端演示：管家 + 团队 + 知识库 + 连接中心 + 唤醒。
// 运行：dart run example/e2e.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_schedule/agent_schedule.dart';
import 'package:agent_email/agent_email.dart';
import 'package:agent_finance/agent_finance.dart';
import 'package:agent_health/agent_health.dart';
import 'package:agent_lifeplan/agent_lifeplan.dart';
import 'package:agent_integrations/agent_integrations.dart';
import 'package:knowledge/knowledge.dart' hide Citation;

DateTime _now = DateTime(2026, 7, 1, 8, 0);

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
}

/// 知识库 → 管家的上下文提供者（每轮对话前注入相关资料）。
class KbContext implements ContextProvider {
  final KnowledgeService kb;
  KbContext(this.kb);
  @override
  Future<String?> contextFor(String query, {String? userId}) async {
    final ctx = await kb.answerContext(query, userId: userId ?? 'u1');
    return ctx.isEmpty ? null : ctx.toPromptContext();
  }
}

/// 兜底对话专员：有知识库上下文就据此作答。
class ChatAgent extends SpecialistAgent {
  @override
  AgentCapability get capability =>
      const AgentCapability(id: 'chat', name: '对话', keywords: ['聊', '你好', '谢谢']);
  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    if (task.context != null) {
      yield AgentResult(text: '根据你的资料 → ${task.context!.replaceAll('\n', ' ')}', citations: const [Citation('知识库')]);
    } else {
      yield const AgentResult(text: '好的，我在，有什么可以帮你？');
    }
  }
}

class FakeMail implements MailProvider {
  final List<Email> inbox;
  final List<Draft> sent = [];
  FakeMail(this.inbox);
  @override
  Future<List<Email>> fetchUnread({DateTime? since}) async => inbox;
  @override
  Future<void> sendDraft(Draft d) async => sent.add(d);
  @override
  Future<void> markRead(String id) async {}
}

Future<void> main() async {
  stdout.writeln('════════ UniHelper 端到端演示 ════════\n');

  // 知识库：存一条个人资料
  final kb = KnowledgeService(
    vault: InMemoryVault(),
    store: InMemoryKnowledgeStore(),
    vectors: InMemoryVectorStore(),
    embedder: const HashingEmbedding(),
  );
  await kb.ingestMarkdown(
    userId: 'u1',
    title: '家庭网络',
    markdown: '# 家庭网络配置\n路由器管理后台 192.168.1.1，密码 admin8899。',
  );

  // 邮箱（假）
  final mail = FakeMail([
    Email(id: 'm1', account: 'me', sender: '张总', address: 'zhang@corp.com', subject: '合同确认', body: '条款三请今天确认', receivedAt: _now),
    Email(id: 'm2', account: 'me', sender: '招商银行', address: 'no-reply@bank.com', subject: '账单', body: '应还 3860', receivedAt: _now),
  ]);

  // 业务服务
  final schedule = ScheduleService(clock: () => _now);
  final email = EmailService(mail: mail);
  final finance = FinanceService(clock: () => _now, budgets: {'餐饮': 30});
  final health = HealthService(clock: () => _now);
  final lifeplan = LifePlanService();

  // 管家：路由 + 知识库上下文注入
  final mgr = Manager(router: const RuleRouter(fallback: 'chat'), contextProvider: KbContext(kb))
    ..register(ChatAgent())
    ..register(schedule)
    ..register(email)
    ..register(finance)
    ..register(health)
    ..register(lifeplan);
  check(mgr.capabilities.length == 6, '管家纳管 6 个专员');
  stdout.writeln('👥 管家已纳管 ${mgr.capabilities.length} 个专员：${mgr.capabilities.map((c) => c.name).join('、')}\n');

  // 连接中心：授权邮箱
  final reg = IntegrationRegistry();
  await reg.connect('email', AuthPayload.imap('imap.corp.com', 'me@corp.com', 'app-pass'));
  check(reg.feeding(Feed.mail).isNotEmpty, '连接中心：邮箱已连');
  stdout.writeln('🔗 连接中心：邮箱已连 → feeding(mail)=${reg.feeding(Feed.mail).map((c) => c.id).toList()}\n');

  Future<ManagerReply> say(String user) async {
    stdout.writeln('👤 $user');
    final r = await mgr.handle(user);
    final tail = r.needsConfirm ? '  ⚠️[待确认:${r.pendingConfirm!.actionKind}]' : '';
    stdout.writeln('🤖 ${r.text}$tail   〔${r.usedAgents.join(',')}〕\n');
    return r;
  }

  // 1) 设备唤醒（App 未开）→ 加日程
  stdout.writeln('── ① 设备唤醒（App 未开，服务层直办）──');
  final bus = WakeBus();
  ManagerReply? woke;
  bus.on((e) async => woke = await mgr.onWake(e));
  await bus.emit(const WakeEvent(source: WakeSource.device, sourceId: 'buds-01', utterance: '加个明天上午10点和张总开会'));
  stdout.writeln('🎧 唤醒 → 🤖 ${woke!.text}   〔${woke!.usedAgents.join(',')}〕\n');
  check(woke!.usedAgents.contains('schedule'), '唤醒创建日程');

  // 2) 记账
  stdout.writeln('── ② 记账 ──');
  final rf = await say('记一笔 午饭 38');
  check(rf.usedAgents.contains('finance'), '路由到财务');

  // 3) 知识库问答（管家注入上下文）
  stdout.writeln('── ③ 知识库问答（管家注入资料）──');
  final rk = await say('我家路由器管理密码是多少');
  check(rk.text.contains('admin8899'), '答出知识库里的密码');

  // 4) 健康 / 5) 生活计划
  stdout.writeln('── ④⑤ 健康 & 生活计划 ──');
  await say('今天走了 6200 步');
  await say('制定一个读 12 本书的阅读计划');

  // 6) 邮件定时巡检（主动）
  stdout.writeln('── ⑥ 邮件定时巡检（重要才推）──');
  await for (final e in email.onTrigger(const TriggerContext(kind: 'poll', source: 'sched'))) {
    if (e is AgentResult) stdout.writeln('🔔 ${e.text}');
  }
  stdout.writeln('');

  // 7) 回复邮件 → 确认闸口 → 确认发送
  stdout.writeln('── ⑦ 回复邮件（发信必须确认）──');
  final rr = await say('帮我回复张总说条款三没问题');
  check(rr.needsConfirm, '发信 → 需确认');
  await email.confirmSend(rr.pendingConfirm!.id);
  check(mail.sent.length == 1, '确认后发送');
  stdout.writeln('   ✅ 已确认发送给 ${mail.sent.first.to}\n');

  // 8) 到点提醒（推进时钟）
  stdout.writeln('── ⑧ 到点提醒 ──');
  _now = DateTime(2026, 7, 2, 9, 46);
  await for (final e in schedule.onTrigger(const TriggerContext(kind: 'remind', source: 'sched'))) {
    if (e is AgentResult) stdout.writeln('⏰ ${e.text}');
  }
  stdout.writeln('');

  // 9) 查询
  stdout.writeln('── ⑨ 查询 ──');
  await say('看看我最近的安排');

  stdout.writeln('════════ ✅ 端到端跑通 ════════');
  stdout.writeln('唤醒→加日程 · 记账 · 知识库问答 · 健康 · 计划 · 邮件巡检+确认发送 · 到点提醒 · 查询');
}
