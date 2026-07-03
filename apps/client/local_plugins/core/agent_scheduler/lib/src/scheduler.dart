import 'package:agent_kernel/agent_kernel.dart';

enum ScheduleKind { every, dailyAt }

/// 一条订阅 = 一个到点/定期触发规则（对应「订阅 Tab」的一项）。
class Subscription {
  final String id;
  final AgentId agentId; // 触发哪个业务服务的 onTrigger
  final ScheduleKind kind;
  final Duration? interval; // every
  final int hour; // dailyAt
  final int minute;
  bool enabled;
  DateTime? lastRun;
  final Map<String, dynamic> params;

  Subscription.every(this.id, this.agentId, Duration this.interval,
      {this.enabled = true, this.params = const {}})
      : kind = ScheduleKind.every,
        hour = 0,
        minute = 0;

  Subscription.dailyAt(this.id, this.agentId, this.hour, this.minute,
      {this.enabled = true, this.params = const {}})
      : kind = ScheduleKind.dailyAt,
        interval = null;
}

/// 一条产出推送（→ 管家按模板推进首页聊天）。
class Push {
  final String subscriptionId;
  final AgentId agentId;
  final String text;
  const Push(this.subscriptionId, this.agentId, this.text);
}

/// 调度引擎：按订阅到点触发对应业务服务的 [SpecialistAgent.onTrigger]，收集推送。
///
/// 生产上跑在 `agents_server` 前台服务里（Android/iOS 后台保活）；此为可测的纯逻辑核心。
class Scheduler {
  final DateTime Function() clock;
  final Map<AgentId, SpecialistAgent> _agents = {};
  final List<Subscription> subscriptions = [];

  Scheduler({DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  void register(SpecialistAgent a) => _agents[a.capability.id] = a;
  void add(Subscription s) => subscriptions.add(s);

  bool isDue(Subscription s, DateTime now) {
    if (!s.enabled) return false;
    switch (s.kind) {
      case ScheduleKind.every:
        final last = s.lastRun;
        return last == null || now.difference(last) >= (s.interval ?? Duration.zero);
      case ScheduleKind.dailyAt:
        final target = DateTime(now.year, now.month, now.day, s.hour, s.minute);
        if (now.isBefore(target)) return false;
        final last = s.lastRun;
        return last == null || last.isBefore(target);
    }
  }

  /// 触发到点订阅：调用对应专员 onTrigger，收集推送，推进 lastRun。
  Future<List<Push>> tick([DateTime? at]) async {
    final now = at ?? clock();
    final pushes = <Push>[];
    for (final s in subscriptions) {
      if (!isDue(s, now)) continue;
      final agent = _agents[s.agentId];
      if (agent != null) {
        await for (final e in agent.onTrigger(
            TriggerContext(kind: s.id, source: 'scheduler', params: s.params))) {
          if (e is AgentResult) pushes.add(Push(s.id, s.agentId, e.text));
        }
      }
      s.lastRun = now;
    }
    return pushes;
  }
}
