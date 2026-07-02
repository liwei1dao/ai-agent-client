import 'package:agent_kernel/agent_kernel.dart';

import 'models.dart';
import 'store.dart';

/// 日程业务服务：
/// - [handle]：对话/唤醒创建或查询日程（自然语言）。
/// - [onTrigger]：调度引擎到点驱动，产出提醒（经管家推送）。
///
/// 数据经 [ScheduleStore] 端口落地：默认内存；移动端注入 local_db DAO（权威源，
/// 后台/唤醒时原生助理服务读写同一份）。[clock] 可注入以便测试。
class ScheduleService extends SpecialistAgent {
  final DateTime Function() clock;
  final Duration remindAdvance;
  final ScheduleStore store;
  int _seq = 0;

  ScheduleService({
    ScheduleStore? store,
    DateTime Function()? clock,
    this.remindAdvance = const Duration(minutes: 15),
  })  : store = store ?? InMemoryScheduleStore(),
        clock = clock ?? DateTime.now;

  @override
  AgentCapability get capability => const AgentCapability(
        id: 'schedule',
        name: '日程',
        keywords: ['日程', '提醒', '安排', '会议', '开会', '约', '记一下', '几点', '定个'],
        description: '创建日程与到点提醒',
        triggers: ['device', 'hotword', 'schedule'],
      );

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final t = task.text;
    if (_isQuery(t)) {
      final list = await upcoming();
      yield AgentResult(
        text: list.isEmpty
            ? '你暂时没有日程。'
            : '你接下来的日程：\n${list.map((e) => '· ${_fmt(e.startAt)} ${e.title}').join('\n')}',
      );
      return;
    }
    final ev = await addFromText(t);
    yield AgentResult(
      text: '已为你创建日程：${_fmt(ev.startAt)} ${ev.title}（提前 ${remindAdvance.inMinutes} 分钟提醒）',
      data: {'eventId': ev.id},
    );
  }

  @override
  Stream<AgentEvent> onTrigger(TriggerContext ctx) async* {
    final now = clock();
    for (final e in await store.all()) {
      if (!e.done && !e.remindAt.isAfter(now) && e.startAt.isAfter(now.subtract(const Duration(minutes: 1)))) {
        yield AgentResult(text: '⏰ 提醒：${_fmt(e.startAt)} ${e.title}', data: {'eventId': e.id});
      }
    }
  }

  // ── 公开 API ────────────────────────────────────────────
  Future<List<ScheduleEvent>> upcoming() async {
    final floor = clock().subtract(const Duration(hours: 1));
    final all = await store.all();
    return all.where((e) => !e.done && e.startAt.isAfter(floor)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
  }

  Future<ScheduleEvent> addFromText(String text) async {
    final startAt = _parseWhen(text, clock());
    final ev = ScheduleEvent(
      id: 'ev-${_seq++}',
      title: _title(text),
      startAt: startAt,
      remindAt: startAt.subtract(remindAdvance),
    );
    await store.add(ev);
    return ev;
  }

  // ── 内部 ────────────────────────────────────────────────
  bool _isQuery(String t) {
    const q = ['有什么', '看看', '查', '列一下', '有哪些', '安排吗', '日程吗'];
    const add = ['加', '提醒我', '安排一下', '约', '记一下', '创建', '定个'];
    return q.any(t.contains) && !add.any(t.contains);
  }

  DateTime _parseWhen(String text, DateTime base) {
    var dayOffset = 0;
    if (text.contains('后天')) {
      dayOffset = 2;
    } else if (text.contains('明天')) {
      dayOffset = 1;
    }
    var hour = 9;
    var minute = 0;
    final m = RegExp(r'(\d{1,2})\s*[点:：]\s*(\d{0,2})').firstMatch(text);
    if (m != null) {
      hour = int.parse(m.group(1)!);
      final mm = m.group(2) ?? '';
      if (mm.isNotEmpty) minute = int.parse(mm);
      if ((text.contains('下午') || text.contains('晚上')) && hour < 12) hour += 12;
    }
    final d = DateTime(base.year, base.month, base.day).add(Duration(days: dayOffset));
    return DateTime(d.year, d.month, d.day, hour, minute);
  }

  String _title(String text) {
    var t = text;
    for (final w in [
      '帮我', '请', '提醒我', '加个', '加一个', '安排一下', '安排', '创建', '定个',
      '日程', '今天', '明天', '后天', '大', '上午', '下午', '晚上',
    ]) {
      t = t.replaceAll(w, '');
    }
    t = t.replaceAll(RegExp(r'\d{1,2}\s*[点:：]\s*\d{0,2}'), '').trim();
    return t.isEmpty ? '（未命名日程）' : t;
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.month}/${d.day} ${two(d.hour)}:${two(d.minute)}';
  }
}
