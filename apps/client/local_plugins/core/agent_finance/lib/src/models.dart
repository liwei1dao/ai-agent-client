library;

enum TxnKind { income, expense }

class Transaction {
  final String id;
  final TxnKind kind;
  final double amount;
  final String category;
  final String note;
  final DateTime occurredAt;
  const Transaction({
    required this.id,
    required this.kind,
    required this.amount,
    required this.category,
    required this.note,
    required this.occurredAt,
  });
}

/// 月度报表（月报 / 查询用）。
class MonthReport {
  final int year;
  final int month;
  final double income;
  final double expense;
  final Map<String, double> byCategory; // 支出分类合计
  final Map<String, double> budgets; // 分类预算（category→limit）
  const MonthReport({
    required this.year,
    required this.month,
    required this.income,
    required this.expense,
    required this.byCategory,
    required this.budgets,
  });

  double get balance => income - expense;

  /// 超预算的分类。
  List<String> get overBudget => [
        for (final e in budgets.entries)
          if ((byCategory[e.key] ?? 0) > e.value) e.key,
      ];

  /// 总预算执行率（0~1+），无总预算时为 null。
  double? get execRatio {
    final total = budgets['总'] ?? budgets['total'];
    if (total == null || total <= 0) return null;
    return expense / total;
  }
}
