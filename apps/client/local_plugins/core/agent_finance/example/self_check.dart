// 财务服务自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_finance/agent_finance.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  final now = DateTime(2026, 7, 15, 12);
  final svc = FinanceService(clock: () => now, budgets: {'餐饮': 30, '总': 10000});

  stdout.writeln('▶ 自然语言记账 + 分类');
  final t1 = await svc.addFromText('午饭 38 块');
  check(t1.category == '餐饮' && t1.amount == 38 && t1.kind == TxnKind.expense, '"午饭38块" → 餐饮 支出 38');
  await svc.addFromText('打车 25');
  await svc.addFromText('买鞋 320');
  final inc = await svc.addFromText('这月工资 18000');
  check(inc.kind == TxnKind.income && inc.category == '收入' && inc.amount == 18000, '"工资18000" → 收入 18000');

  stdout.writeln('▶ 月度统计 + 预算预警');
  final r = await svc.monthReport(now);
  check(r.income == 18000, '收入合计 18000');
  check(r.expense == 383, '支出合计 383（38+25+320）');
  check(r.balance == 17617, '结余 = 收入-支出');
  check(r.byCategory['餐饮'] == 38, '分类餐饮 38');
  check(r.overBudget.contains('餐饮'), '餐饮 38 > 预算 30 → 超预算');

  stdout.writeln('▶ 经管家：记账 / 查询');
  final mgr = Manager(router: const RuleRouter())..register(svc);
  final rr = await mgr.handle('记一笔 咖啡 22');
  check(rr.usedAgents.contains('finance') && rr.text.contains('餐饮'), '"记一笔 咖啡22" → 路由到财务、归类餐饮');

  final q1 = await mgr.handle('这个月花了多少');
  check(q1.text.contains('结余'), '"花了多少" → 月度小结');
  final q2 = await mgr.handle('餐饮花了多少');
  check(q2.text.contains('60'), '"餐饮花了多少" → 60（38+22）');

  stdout.writeln('▶ onTrigger 月报');
  final push = <AgentEvent>[];
  await for (final e in svc.onTrigger(const TriggerContext(kind: 'monthly', source: 'scheduler'))) {
    push.add(e);
  }
  final txt = (push.single as AgentResult).text;
  check(txt.contains('月财务月报') && txt.contains('超预算：餐饮'), 'onTrigger 产出月报 + 超预算建议');

  stdout.writeln('\n✅ 财务服务通过：记账分类 · 月度统计 · 预算预警 · 管家记账/查询 · 月报。');
}
