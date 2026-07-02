/// 生活计划存储端口。默认内存；移动端注入 local_db DAO。
library;

import 'models.dart';

abstract interface class LifePlanStore {
  Future<void> put(LifePlan p);
  Future<List<LifePlan>> all();
  Future<LifePlan?> get(String id);
}

class InMemoryLifePlanStore implements LifePlanStore {
  final Map<String, LifePlan> _m = {};
  @override
  Future<void> put(LifePlan p) async => _m[p.id] = p;
  @override
  Future<List<LifePlan>> all() async => _m.values.toList();
  @override
  Future<LifePlan?> get(String id) async => _m[id];
}
