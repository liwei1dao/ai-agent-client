/// 健康存储端口。默认内存；移动端注入 local_db / 系统健康（HealthKit/Google Fit）。
library;

import 'models.dart';

abstract interface class HealthStore {
  Future<HealthDay> dayOf(DateTime date); // 取当天记录，无则新建空
  Future<void> put(HealthDay d);
  Future<List<HealthDay>> range(DateTime from, DateTime to);
}

class InMemoryHealthStore implements HealthStore {
  final Map<String, HealthDay> _m = {};
  String _k(DateTime d) => '${d.year}-${d.month}-${d.day}';

  @override
  Future<HealthDay> dayOf(DateTime date) async =>
      _m.putIfAbsent(_k(date), () => HealthDay(date: DateTime(date.year, date.month, date.day)));

  @override
  Future<void> put(HealthDay d) async => _m[_k(d.date)] = d;

  @override
  Future<List<HealthDay>> range(DateTime from, DateTime to) async {
    final lo = DateTime(from.year, from.month, from.day);
    final hi = DateTime(to.year, to.month, to.day);
    return _m.values.where((d) => !d.date.isBefore(lo) && !d.date.isAfter(hi)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }
}
