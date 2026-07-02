/// 日程存储端口。默认内存（web/桌面/测试）；移动端注入 local_db DAO（权威源）。
library;

import 'models.dart';

abstract interface class ScheduleStore {
  Future<void> add(ScheduleEvent e);
  Future<List<ScheduleEvent>> all();
  Future<void> update(ScheduleEvent e);
}

class InMemoryScheduleStore implements ScheduleStore {
  final List<ScheduleEvent> _events = [];
  @override
  Future<void> add(ScheduleEvent e) async => _events.add(e);
  @override
  Future<List<ScheduleEvent>> all() async => List.of(_events);
  @override
  Future<void> update(ScheduleEvent e) async {
    final i = _events.indexWhere((x) => x.id == e.id);
    if (i >= 0) _events[i] = e;
  }
}
