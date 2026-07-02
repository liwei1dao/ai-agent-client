import 'package:agent_kernel/agent_kernel.dart';

import 'models.dart';
import 'store.dart';

/// 健康业务服务：
/// - [handle]：记录（"今天走了6200步"/"睡了7.2小时"/"喝了3杯水"/"体重65"）；或查询当天健康。
/// - [onTrigger]：调度到点做目标提醒（喝水/步数未达）。
///
/// 数据经 [HealthStore] 落地（默认内存；移动端 local_db / 系统健康 HealthKit·Google Fit）。
class HealthService extends SpecialistAgent {
  final DateTime Function() clock;
  final HealthStore store;
  final HealthGoals goals;

  HealthService({HealthStore? store, DateTime Function()? clock, this.goals = const HealthGoals()})
      : store = store ?? InMemoryHealthStore(),
        clock = clock ?? DateTime.now;

  @override
  AgentCapability get capability => const AgentCapability(
        id: 'health',
        name: '健康',
        keywords: ['步数', '走了', '步', '睡', '睡眠', '喝水', '饮水', '喝了', '体重', '心率', '健康', '运动', '久坐'],
        description: '记录健康数据 + 目标提醒',
        triggers: ['schedule', 'device'],
      );

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final t = task.text;
    if (_isQuery(t)) {
      yield AgentResult(text: _summary(await store.dayOf(clock())));
      return;
    }
    final metric = _metricOf(t);
    if (metric == null) {
      yield AgentResult(text: _summary(await store.dayOf(clock())));
      return;
    }
    final d = await store.dayOf(clock());
    final n = _num(t);
    switch (metric) {
      case 'steps':
        if (n != null) d.steps = n.toInt();
      case 'sleep':
        if (n != null) d.sleepHours = n.toDouble();
      case 'water':
        d.waterCups += (n?.toInt() ?? 1);
      case 'weight':
        if (n != null) d.weightKg = n.toDouble();
      case 'hr':
        if (n != null) d.restingHr = n.toInt();
    }
    await store.put(d);
    yield AgentResult(text: '已记录 · ${_summary(d)}', data: {'date': d.date.toIso8601String().substring(0, 10)});
  }

  @override
  Stream<AgentEvent> onTrigger(TriggerContext ctx) async* {
    final d = await store.dayOf(clock());
    if (d.waterCups < goals.waterCups) {
      yield AgentResult(text: '💧 今天喝水 ${d.waterCups}/${goals.waterCups} 杯，记得补水～');
    }
    if (d.steps < goals.steps) {
      yield AgentResult(text: '🚶 今天步数 ${d.steps}/${goals.steps}，起来走走吧');
    }
  }

  // ── 内部 ────────────────────────────────────────────────
  bool _isQuery(String t) =>
      ['怎么样', '多少', '查', '这周', '健康吗', '看看', '情况'].any(t.contains) && _num(t) == null;

  String? _metricOf(String t) {
    if (t.contains('步')) return 'steps';
    if (t.contains('睡')) return 'sleep';
    if (t.contains('喝') || t.contains('饮水')) return 'water';
    if (t.contains('体重')) return 'weight';
    if (t.contains('心率')) return 'hr';
    return null;
  }

  num? _num(String t) {
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(t);
    return m == null ? null : num.parse(m.group(1)!);
  }

  String _summary(HealthDay d) {
    final w = d.weightKg != null ? ' · 体重 ${d.weightKg}kg' : '';
    return '步数 ${d.steps} · 睡眠 ${d.sleepHours}h · 饮水 ${d.waterCups}/${goals.waterCups} 杯$w';
  }
}
