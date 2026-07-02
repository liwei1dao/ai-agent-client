library;

enum PlanKind { saving, reading, fitness, diet, custom }

/// 一个长期生活计划。
class LifePlan {
  final String id;
  final String title;
  final PlanKind kind;
  final double target; // 目标量
  double current; // 当前进度量
  final String unit; // 元/本/次/天
  final String? note;
  LifePlan({
    required this.id,
    required this.title,
    required this.kind,
    required this.target,
    this.current = 0,
    this.unit = '',
    this.note,
  });

  double get progress {
    if (target <= 0) return 0;
    final r = current / target;
    return r > 1 ? 1 : (r < 0 ? 0 : r);
  }

  int get percent => (progress * 100).round();
}
