import 'package:agent_kernel/agent_kernel.dart';

import 'models.dart';
import 'store.dart';

/// 生活计划业务服务：
/// - [handle]：创建计划（"定个这个月存5000的储蓄计划"）/ 更新进度（"存了1200"/"读完3本"）/ 查询进度。
/// - [onTrigger]：调度到点复盘（列出计划进度 + 落后提醒）。
///
/// 数据经 [LifePlanStore] 落地（默认内存；移动端 local_db）。
class LifePlanService extends SpecialistAgent {
  final DateTime Function() clock;
  final LifePlanStore store;
  int _seq = 0;

  LifePlanService({LifePlanStore? store, DateTime Function()? clock})
      : store = store ?? InMemoryLifePlanStore(),
        clock = clock ?? DateTime.now;

  @override
  AgentCapability get capability => const AgentCapability(
        id: 'lifeplan',
        name: '生活计划',
        keywords: ['计划', '目标', '储蓄', '存钱', '阅读', '读', '健身', '减脂', '进度', '打卡', '完成', '定个'],
        description: '创建长期计划、跟踪进度、复盘',
        triggers: ['schedule'],
      );

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final t = task.text;
    if (_isUpdate(t)) {
      final p = await _findPlan(t);
      if (p == null) {
        yield AgentResult(text: '没找到对应的计划，先定一个吧。');
        return;
      }
      p.current += (_num(t) ?? 1).toDouble();
      await store.put(p);
      yield AgentResult(
        text: '已更新：${p.title} ${_fmt(p.current)}/${_fmt(p.target)}${p.unit}（${p.percent}%）',
        data: {'planId': p.id},
      );
      return;
    }
    if (_isCreate(t)) {
      final kind = _kindOf(t);
      final p = await addPlan(title: _title(t, kind), kind: kind, target: _target(t), unit: _unitOf(kind));
      yield AgentResult(
        text: '已创建计划：${p.title} 目标 ${_fmt(p.target)}${p.unit}',
        data: {'planId': p.id},
      );
      return;
    }
    // 查询
    final plans = await store.all();
    yield AgentResult(
      text: plans.isEmpty
          ? '你还没有生活计划，说"定个…计划"来创建。'
          : '你的计划：\n${plans.map((p) => '· ${p.title} ${_fmt(p.current)}/${_fmt(p.target)}${p.unit}（${p.percent}%）').join('\n')}',
    );
  }

  @override
  Stream<AgentEvent> onTrigger(TriggerContext ctx) async* {
    final plans = await store.all();
    if (plans.isEmpty) return;
    final lag = plans.where((p) => p.percent < 50).map((p) => p.title).toList();
    final body = plans.map((p) => '· ${p.title} ${p.percent}%').join('\n');
    yield AgentResult(
      text: '🎯 计划复盘\n$body${lag.isEmpty ? '' : '\n💡 ${lag.join('、')} 进度偏慢，今天推进一点？'}',
    );
  }

  // ── 公开 API ────────────────────────────────────────────
  Future<LifePlan> addPlan({
    required String title,
    required PlanKind kind,
    required double target,
    String unit = '',
    String? note,
  }) async {
    final p = LifePlan(id: 'plan-${_seq++}', title: title, kind: kind, target: target, unit: unit, note: note);
    await store.put(p);
    return p;
  }

  Future<LifePlan?> updateProgress(String id, num delta) async {
    final p = await store.get(id);
    if (p == null) return null;
    p.current += delta.toDouble();
    await store.put(p);
    return p;
  }

  // ── 内部 ────────────────────────────────────────────────
  bool _isUpdate(String t) => ['存了', '又存', '读完', '读了', '完成了', '打卡', '做了', '跑了', '推进'].any(t.contains);
  bool _isCreate(String t) =>
      ['定个', '制定', '新建', '建个', '定一个'].any(t.contains) || (t.contains('计划') && _num(t) != null);

  PlanKind _kindOf(String t) {
    if (t.contains('存') || t.contains('储蓄') || t.contains('钱')) return PlanKind.saving;
    if (t.contains('读') || t.contains('书') || t.contains('阅读')) return PlanKind.reading;
    if (t.contains('健身') || t.contains('运动') || t.contains('跑')) return PlanKind.fitness;
    if (t.contains('减脂') || t.contains('餐') || t.contains('瘦')) return PlanKind.diet;
    return PlanKind.custom;
  }

  String _unitOf(PlanKind k) => switch (k) {
        PlanKind.saving => '元',
        PlanKind.reading => '本',
        PlanKind.fitness => '次',
        PlanKind.diet => '天',
        PlanKind.custom => '',
      };

  /// 取文本中最大的数字作为目标量（规避"6月"等噪声）。
  double _target(String t) {
    final ns = RegExp(r'(\d+(?:\.\d+)?)').allMatches(t).map((m) => double.parse(m.group(1)!)).toList();
    return ns.isEmpty ? 0 : ns.reduce((a, b) => a > b ? a : b);
  }

  num? _num(String t) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(t);
    return m == null ? null : num.parse(m.group(1)!);
  }

  Future<LifePlan?> _findPlan(String t) async {
    final plans = await store.all();
    if (plans.isEmpty) return null;
    final kind = _kindOf(t);
    for (final p in plans) {
      if (p.kind == kind) return p;
    }
    return plans.first;
  }

  String _title(String t, PlanKind kind) {
    const label = {
      PlanKind.saving: '储蓄计划',
      PlanKind.reading: '阅读计划',
      PlanKind.fitness: '健身计划',
      PlanKind.diet: '减脂计划',
      PlanKind.custom: '生活计划',
    };
    return label[kind]!;
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}
