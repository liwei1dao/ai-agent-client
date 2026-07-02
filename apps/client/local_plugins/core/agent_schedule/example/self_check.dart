// 日程服务自检（含管家路由 + 到点提醒）。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_schedule/agent_schedule.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  var now = DateTime(2026, 7, 1, 8, 0); // 固定时钟，便于断言
  final svc = ScheduleService(clock: () => now);

  stdout.writeln('▶ 自然语言解析 / 创建');
  final ev = await svc.addFromText('明天上午10点和张总开会');
  check(ev.startAt == DateTime(2026, 7, 2, 10, 0), '“明天上午10点” → 7/2 10:00');
  check(ev.title.contains('和张总开会'), '标题保留“和张总开会”（去掉时间词）');
  check(ev.remindAt == DateTime(2026, 7, 2, 9, 45), '提醒 = 提前 15 分钟（9:45）');

  stdout.writeln('▶ 经管家路由创建');
  final mgr = Manager(router: const RuleRouter())..register(svc);
  final r1 = await mgr.handle('提醒我后天下午3点去牙医');
  check(r1.usedAgents.contains('schedule'), '管家把“提醒我…”路由到日程');
  check(r1.text.contains('7/3 15:00'), '“后天下午3点” → 7/3 15:00');

  stdout.writeln('▶ 查询');
  final r2 = await mgr.handle('我最近有什么安排');
  check(r2.text.contains('和张总开会') && r2.text.contains('去牙医'), '列出两条日程');

  stdout.writeln('▶ 到点提醒（推进时钟触发 onTrigger）');
  now = DateTime(2026, 7, 2, 9, 46); // 越过张总会的提醒时刻 9:45
  final reminders = <AgentEvent>[];
  await for (final e in svc.onTrigger(const TriggerContext(kind: 'reminder', source: 'scheduler'))) {
    reminders.add(e);
  }
  check(
    reminders.any((e) => e is AgentResult && e.text.contains('和张总开会')),
    'onTrigger 到点触发“和张总开会”提醒',
  );
  check(
    !reminders.any((e) => e is AgentResult && e.text.contains('去牙医')),
    '未到点的“去牙医”不提醒',
  );

  stdout.writeln('\n✅ 日程服务通过：解析创建 · 管家路由 · 查询 · 到点提醒（无 UI 也走通）。');
}
