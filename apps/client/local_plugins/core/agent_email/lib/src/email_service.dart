import 'package:agent_kernel/agent_kernel.dart';

import 'defaults.dart';
import 'models.dart';
import 'ports.dart';
import 'store.dart';

/// 邮件业务服务：
/// - [onTrigger]：调度到点巡检 → 拉未读 → 判重要性 → 重要才推送（经管家）+ 落库。
/// - [handle]：查询重要邮件；或起草回复 → **必须确认才发**（[AgentNeedConfirm]）。
/// - [confirmSend]：用户确认后的**唯一发送路径**。
///
/// 邮箱接入经 [MailProvider]；数据经 [EmailStore] 落地（默认内存，移动端注入 local_db）。
class EmailService extends SpecialistAgent {
  final MailProvider mail;
  final ImportanceJudge judge;
  final ReplyDrafter drafter;
  final EmailStore store;

  final Map<String, Draft> _pending = {}; // confirmId -> 待发草稿（会话态，不落库）
  final Map<String, Email> _pendingTarget = {};
  int _seq = 0;

  EmailService({
    required this.mail,
    EmailStore? store,
    ImportanceJudge? judge,
    ReplyDrafter? drafter,
  })  : store = store ?? InMemoryEmailStore(),
        judge = judge ?? const RuleImportanceJudge(),
        drafter = drafter ?? const TemplateReplyDrafter();

  @override
  AgentCapability get capability => const AgentCapability(
        id: 'email',
        name: '邮件',
        keywords: ['邮件', '邮箱', '回复', '回信', '回一下', '答复', '未读'],
        description: '定时巡检、重要提醒、起草回复（需确认才发）',
        triggers: ['schedule'],
      );

  @override
  Stream<AgentEvent> onTrigger(TriggerContext ctx) async* {
    final unread = await mail.fetchUnread();
    for (final e in unread) {
      if (await store.isProcessed(e.id)) continue;
      await store.markProcessed(e.id);
      final (imp, reason) = await judge.judge(e);
      final rec = EmailRecord(e, imp, reason);
      await store.putRecord(rec);
      if (imp == Importance.high) {
        await store.setAction(e.id, 'notified');
        yield AgentResult(
          text: '📧 ${e.sender}《${e.subject}》· 重要（$reason）',
          data: {'emailId': e.id},
        );
      }
    }
  }

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    final t = task.text;
    if (_isReply(t)) {
      final target = await _findTarget(t);
      if (target == null) {
        yield AgentResult(text: '没找到要回复的邮件，先巡检一下或指个发件人。');
        return;
      }
      final body = await drafter.draft(target, _instruction(t));
      final confirmId = 'cf-${_seq++}';
      final draft = Draft(
        id: confirmId,
        to: target.address,
        subject: 'Re: ${target.subject}',
        body: body,
        inReplyTo: target.id,
      );
      _pending[confirmId] = draft;
      _pendingTarget[confirmId] = target;
      yield AgentNeedConfirm(Confirm(
        id: confirmId,
        actionKind: 'send_email',
        summary: '给 ${target.sender} 回复《${target.subject}》',
        preview: {'to': target.address, 'subject': draft.subject, 'body': body},
      ));
      return;
    }
    final imp = (await store.records()).where((r) => r.importance == Importance.high).take(5).toList();
    yield AgentResult(
      text: imp.isEmpty
          ? '暂无重要邮件。'
          : '重要邮件：\n${imp.map((r) => '· ${r.email.sender}《${r.email.subject}》').join('\n')}',
    );
  }

  /// 用户确认后发送（唯一发送路径；无自动发送）。返回是否成功。
  Future<bool> confirmSend(String confirmId) async {
    final d = _pending.remove(confirmId);
    if (d == null) return false;
    await mail.sendDraft(d);
    final tgt = _pendingTarget.remove(confirmId);
    if (tgt != null) await store.setAction(tgt.id, 'replied');
    return true;
  }

  bool _isReply(String t) => ['回复', '回信', '回一下', '帮我回', '答复'].any(t.contains);

  String _instruction(String t) {
    final i = t.indexOf('说');
    return i >= 0 ? t.substring(i + 1).trim() : '';
  }

  Future<Email?> _findTarget(String t) async {
    final recs = await store.records();
    for (final r in recs) {
      if (t.contains(r.email.sender)) return r.email;
    }
    for (final r in recs) {
      if (r.importance == Importance.high && r.action != 'replied') return r.email;
    }
    return recs.isNotEmpty ? recs.first.email : null;
  }
}
