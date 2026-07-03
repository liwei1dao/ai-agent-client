// 调度引擎自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_scheduler/agent_scheduler.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

/// 假业务服务：每次 onTrigger 计数并产出一条推送。
class Pinger extends SpecialistAgent {
  final String id;
  int calls = 0;
  Pinger(this.id);
  @override
  AgentCapability get capability => AgentCapability(id: id, name: id);
  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {}
  @override
  Stream<AgentEvent> onTrigger(TriggerContext ctx) async* {
    calls++;
    yield AgentResult(text: '$id 触发 #$calls');
  }
}

Future<void> main() async {
  final sch = Scheduler();
  final news = Pinger('news');
  final health = Pinger('health');
  sch.register(news);
  sch.register(health);
  sch.add(Subscription.every('news_poll', 'news', const Duration(minutes: 30)));
  sch.add(Subscription.dailyAt('health_nudge', 'health', 20, 0));

  final t = (int h, int m) => DateTime(2026, 7, 1, h, m);

  stdout.writeln('▶ 首次 tick 08:00');
  var p = await sch.tick(t(8, 0));
  check(p.length == 1 && p.first.agentId == 'news', '资讯(every)首次到点触发，健康(20:00)未到不触发');
  check(news.calls == 1 && health.calls == 0, '计数正确');

  stdout.writeln('▶ 08:10 tick（间隔未到）');
  p = await sch.tick(t(8, 10));
  check(p.isEmpty && news.calls == 1, '资讯 30 分钟未到 → 不触发');

  stdout.writeln('▶ 08:31 tick（间隔已到）');
  p = await sch.tick(t(8, 31));
  check(p.length == 1 && news.calls == 2, '资讯 31 分钟 → 再次触发');

  stdout.writeln('▶ 20:01 tick（每日 20:00 到点）');
  p = await sch.tick(t(20, 1));
  check(p.any((x) => x.agentId == 'health') && health.calls == 1, '健康 dailyAt 20:00 到点触发');
  check(p.any((x) => x.agentId == 'news') && news.calls == 3, '资讯也再次到点');

  stdout.writeln('▶ 同日 20:30 tick（每日任务当天不重复）');
  p = await sch.tick(t(20, 30));
  check(!p.any((x) => x.agentId == 'health') && health.calls == 1, '健康当天不重复触发');

  stdout.writeln('▶ 停用订阅');
  sch.subscriptions.firstWhere((s) => s.id == 'news_poll').enabled = false;
  p = await sch.tick(t(23, 0));
  check(!p.any((x) => x.agentId == 'news'), '停用后不再触发');

  stdout.writeln('\n✅ 调度引擎通过：every 间隔 · dailyAt 到点 · 当天不重复 · 停用生效 · 触发 onTrigger 收集推送。');
}
