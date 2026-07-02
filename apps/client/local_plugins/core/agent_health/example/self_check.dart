// 健康服务自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_health/agent_health.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  final now = DateTime(2026, 7, 15, 20);
  final svc = HealthService(clock: () => now);
  final mgr = Manager(router: const RuleRouter())..register(svc);

  stdout.writeln('▶ 记录健康数据（经管家）');
  await mgr.handle('今天走了 6200 步');
  await mgr.handle('昨晚睡了 7.2 小时');
  await mgr.handle('喝了 3 杯水');
  await mgr.handle('体重 65.2');
  final d = await svc.store.dayOf(now);
  check(d.steps == 6200 && d.sleepHours == 7.2 && d.waterCups == 3 && d.weightKg == 65.2,
      '步数/睡眠/饮水/体重 均记录');

  stdout.writeln('▶ 查询');
  final q = await mgr.handle('今天健康怎么样');
  check(q.usedAgents.contains('health') && q.text.contains('6200') && q.text.contains('7.2'),
      '管家路由并汇总当天健康');

  stdout.writeln('▶ 无数字追加饮水');
  await mgr.handle('又喝了一杯水');
  check((await svc.store.dayOf(now)).waterCups == 4, '"又喝了一杯水" → 饮水 +1 = 4');

  stdout.writeln('▶ onTrigger 目标提醒');
  final rem = <AgentEvent>[];
  await for (final e in svc.onTrigger(const TriggerContext(kind: 'nudge', source: 'scheduler'))) {
    rem.add(e);
  }
  final texts = rem.whereType<AgentResult>().map((e) => e.text).join('|');
  check(texts.contains('喝水') && texts.contains('步数'), '未达目标 → 喝水 + 步数提醒');

  stdout.writeln('\n✅ 健康服务通过：记录 · 查询 · 追加饮水 · 目标提醒。');
}
