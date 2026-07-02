import 'package:agent_kernel/agent_kernel.dart';

import 'defaults.dart';
import 'models.dart';
import 'ports.dart';
import 'store.dart';

/// 财务业务服务：
/// - [handle]：自然语言记账（"午饭38块"）；或查询（"这个月花了多少" / "餐饮花了多少"）。
/// - [onTrigger]：调度到点产出月报 + 建议（经管家推送）。
///
/// 交易经 [FinanceStore] 落地（默认内存，移动端注入 local_db）。[clock] 可注入。
class FinanceService extends SpecialistAgent {
  final Categorizer categorizer;
  final AdvicePlanner planner;
  final DateTime Function() clock;
  final FinanceStore store;
  final Map<String, double> budgets; // category→limit；'总' 为总预算
  int _seq = 0;

  FinanceService({
    FinanceStore? store,
    Categorizer? categorizer,
    AdvicePlanner? planner,
    DateTime Function()? clock,
    Map<String, double>? budgets,
  })  : store = store ?? InMemoryFinanceStore(),
        categorizer = categorizer ?? const RuleCategorizer(),
        planner = planner ?? const RuleAdvicePlanner(),
        clock = clock ?? DateTime.now,
        budgets = budgets ?? {};

  @override
  AgentCapability get capability => const AgentCapability(
        id: 'finance',
        name: '财务',
        keywords: ['记一笔', '记账', '花了', '花销', '开销', '支出', '收入', '工资', '预算', '月报', '账单', '多少钱', '结余'],
        description: '记账 + 月度收支 + 预算预警 + 月报建议',
        triggers: ['schedule'],
      );

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final t = task.text;
    if (_isQuery(t)) {
      final r = await monthReport(clock());
      final cat = _mentionedCategory(t);
      if (cat != null) {
        yield AgentResult(text: '本月「$cat」支出 ¥${(r.byCategory[cat] ?? 0).toStringAsFixed(0)}。');
      } else {
        yield AgentResult(text: _summary(r));
      }
      return;
    }
    if (_hasAmount(t)) {
      final tx = await addFromText(t);
      final sign = tx.kind == TxnKind.income ? '+' : '-';
      yield AgentResult(
        text: '已记一笔：${tx.category} $sign¥${tx.amount.toStringAsFixed(0)}（${tx.note}）',
        data: {'txnId': tx.id},
      );
      return;
    }
    yield AgentResult(text: _summary(await monthReport(clock())));
  }

  @override
  Stream<AgentEvent> onTrigger(TriggerContext ctx) async* {
    final r = await monthReport(clock());
    yield AgentResult(text: '📊 ${r.month} 月财务月报\n${_summary(r)}\n💡 ${planner.advise(r)}');
  }

  // ── 公开 API ────────────────────────────────────────────
  Future<Transaction> addTransaction(Transaction tx) async {
    await store.add(tx);
    return tx;
  }

  Future<Transaction> addFromText(String text) async {
    final kind = _isIncome(text) ? TxnKind.income : TxnKind.expense;
    final tx = Transaction(
      id: 'tx-${_seq++}',
      kind: kind,
      amount: _amount(text) ?? 0,
      category: kind == TxnKind.income ? '收入' : categorizer.categoryOf(text),
      note: text.trim(),
      occurredAt: clock(),
    );
    await store.add(tx);
    return tx;
  }

  Future<MonthReport> monthReport(DateTime now) async {
    var income = 0.0;
    var expense = 0.0;
    final byCat = <String, double>{};
    for (final tx in await store.all()) {
      if (tx.occurredAt.year != now.year || tx.occurredAt.month != now.month) continue;
      if (tx.kind == TxnKind.income) {
        income += tx.amount;
      } else {
        expense += tx.amount;
        byCat[tx.category] = (byCat[tx.category] ?? 0) + tx.amount;
      }
    }
    return MonthReport(
      year: now.year, month: now.month,
      income: income, expense: expense, byCategory: byCat, budgets: budgets,
    );
  }

  // ── 内部 ────────────────────────────────────────────────
  static final _numRe = RegExp(r'(\d+(?:\.\d+)?)');
  bool _hasAmount(String t) => _numRe.hasMatch(t);
  double? _amount(String t) {
    final m = _numRe.firstMatch(t);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  bool _isIncome(String t) => ['收入', '工资', '报销', '奖金', '进账', '到账'].any(t.contains);
  bool _isQuery(String t) => ['多少', '月报', '账单', '结余', '预算执行', '看看', '查一下'].any(t.contains);

  String? _mentionedCategory(String t) {
    for (final c in ['餐饮', '交通', '购物', '居住', '娱乐', '医疗']) {
      if (t.contains(c)) return c;
    }
    return null;
  }

  String _summary(MonthReport r) {
    final b = StringBuffer()
      ..write('收入 ¥${r.income.toStringAsFixed(0)}，支出 ¥${r.expense.toStringAsFixed(0)}，结余 ¥${r.balance.toStringAsFixed(0)}。');
    if (r.byCategory.isNotEmpty) {
      final top = r.byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      b.write('\n分类：${top.take(4).map((e) => '${e.key} ¥${e.value.toStringAsFixed(0)}').join('，')}');
    }
    if (r.overBudget.isNotEmpty) b.write('\n⚠️ 超预算：${r.overBudget.join('、')}');
    return b.toString();
  }
}
