library;

/// 某一天的健康快照。
class HealthDay {
  final DateTime date; // 归一到当天 0 点
  int steps;
  double sleepHours;
  int waterCups;
  double? weightKg;
  int? restingHr;
  HealthDay({
    required this.date,
    this.steps = 0,
    this.sleepHours = 0,
    this.waterCups = 0,
    this.weightKg,
    this.restingHr,
  });
}

class HealthGoals {
  final int steps;
  final int waterCups;
  final double sleepHours;
  const HealthGoals({this.steps = 8000, this.waterCups = 8, this.sleepHours = 8});
}
