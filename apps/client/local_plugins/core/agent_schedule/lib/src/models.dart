library;

/// 一条日程。
class ScheduleEvent {
  final String id;
  final String title;
  final DateTime startAt;
  final DateTime remindAt;
  bool done;
  ScheduleEvent({
    required this.id,
    required this.title,
    required this.startAt,
    required this.remindAt,
    this.done = false,
  });
}
