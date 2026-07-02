/// 财务存储端口。默认内存；移动端注入 local_db DAO（transactions 持久化）。
library;

import 'models.dart';

abstract interface class FinanceStore {
  Future<void> add(Transaction t);
  Future<List<Transaction>> all();
}

class InMemoryFinanceStore implements FinanceStore {
  final List<Transaction> _txns = [];
  @override
  Future<void> add(Transaction t) async => _txns.add(t);
  @override
  Future<List<Transaction>> all() async => List.of(_txns);
}
