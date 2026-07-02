// 生活计划服务自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_lifeplan/agent_lifeplan.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  final svc = LifePlanService();
  final mgr = Manager(router: const RuleRouter())..register(svc);

  stdout.writeln('▶ 公开 API 创建 + 进度');
  final p = await svc.addPlan(title: '6月储蓄', kind: PlanKind.saving, target: 5000, unit: '元');
  check(p.percent == 0, '新建储蓄计划 0%');
  await svc.updateProgress(p.id, 4100);
  check((await svc.store.get(p.id))!.percent == 82, '存 4100 → 82%');

  stdout.writeln('▶ 经管家：自然语言创建');
  final rc = await mgr.handle('帮我定个读10本书的阅读计划');
  check(rc.usedAgents.contains('lifeplan') && rc.text.contains('10'), '"定个读10本书" → 阅读计划 目标 10');

  stdout.writeln('▶ 经管家：更新进度');
  final ru = await mgr.handle('这周读完了3本');
  check(ru.text.contains('30%'), '"读完了3本" → 阅读 3/10 = 30%');

  stdout.writeln('▶ 经管家：查询进度');
  final rq = await mgr.handle('看看我的计划进度');
  check(rq.text.contains('储蓄') && rq.text.contains('82%') && rq.text.contains('阅读'), '列出储蓄82% + 阅读');

  stdout.writeln('▶ onTrigger 复盘');
  final rev = <AgentEvent>[];
  await for (final e in svc.onTrigger(const TriggerContext(kind: 'review', source: 'scheduler'))) {
    rev.add(e);
  }
  final txt = (rev.single as AgentResult).text;
  check(txt.contains('计划复盘') && txt.contains('阅读') && txt.contains('进度偏慢'), '复盘：列进度 + 落后(阅读30%)提醒');

  stdout.writeln('\n✅ 生活计划服务通过：创建 · 进度更新 · 管家路由 · 查询 · 复盘。');
}
