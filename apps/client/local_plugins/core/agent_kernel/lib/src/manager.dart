/// 管家 Manager：单一外部面孔——路由 → 分派 → 汇总（一个声音）+ 上下文注入 + 确认闸口 + 唤醒。
library;

import 'models.dart';
import 'ports.dart';

class Manager {
  final Router router;

  /// 每轮对话前注入的上下文来源（如知识库）。
  final ContextProvider? contextProvider;

  final Map<AgentId, SpecialistAgent> _agents = {};
  int _seq = 0;

  Manager({required this.router, this.contextProvider});

  void register(SpecialistAgent agent) => _agents[agent.capability.id] = agent;

  List<AgentCapability> get capabilities =>
      _agents.values.map((a) => a.capability).toList();

  String _id(String p) => '$p-${_seq++}';

  /// 处理用户输入：注入上下文 → 路由 → 分派（可多专员）→ 汇总成一个回复。
  Future<ManagerReply> handle(String userText, {String? userId}) async {
    final requestId = _id('req');
    final context = await contextProvider?.contextFor(userText, userId: userId);
    final ids = await router.route(userText, capabilities, userId: userId);

    final used = <AgentId>[];
    final citations = <Citation>[];
    final buf = StringBuffer();
    Confirm? pending;

    for (final id in ids) {
      final agent = _agents[id];
      if (agent == null) continue;
      used.add(id);
      final task = TaskEnvelope(
        taskId: _id('task'),
        requestId: requestId,
        from: 'manager',
        to: id,
        intent: agent.capability.id,
        text: userText,
        context: context,
        userId: userId,
      );
      await for (final e in agent.handle(task)) {
        switch (e) {
          case AgentResult r:
            if (buf.isNotEmpty) buf.write('\n');
            buf.write(r.text);
            citations.addAll(r.citations);
          case AgentNeedConfirm c:
            pending = c.confirm;
          case AgentError err:
            if (buf.isNotEmpty) buf.write('\n');
            buf.write('（$id 出错：${err.message}）');
          case AgentPartial():
          case AgentProgress():
            // 骨架：流式片段/进度在此可转发到 UI，聚合回复时忽略。
            break;
        }
      }
    }

    return ManagerReply(
      text: buf.toString(),
      usedAgents: used,
      citations: citations,
      pendingConfirm: pending,
    );
  }

  /// 服务级唤醒入口（被 WakeBus 调起，可能无 Flutter 会话在场）。
  Future<ManagerReply?> onWake(WakeEvent e) async {
    final text = e.utterance;
    if (text == null || text.isEmpty) return null;
    return handle(text, userId: e.payload['userId'] as String?);
  }
}

/// 框架层唤醒总线：各唤醒源统一 emit，路由到管家/专员。
typedef WakeHandler = Future<void> Function(WakeEvent e);

class WakeBus {
  final List<WakeHandler> _handlers = [];
  void on(WakeHandler h) => _handlers.add(h);
  Future<void> emit(WakeEvent e) async {
    for (final h in _handlers) {
      await h(e);
    }
  }
}
