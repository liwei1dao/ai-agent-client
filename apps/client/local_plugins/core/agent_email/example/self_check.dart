// 邮件服务自检。运行：dart run example/self_check.dart
import 'dart:io';

import 'package:agent_kernel/agent_kernel.dart';
import 'package:agent_email/agent_email.dart';

class FakeMail implements MailProvider {
  final List<Email> inbox;
  final List<Draft> sent = [];
  FakeMail(this.inbox);
  @override
  Future<List<Email>> fetchUnread({DateTime? since}) async => inbox;
  @override
  Future<void> sendDraft(Draft d) async => sent.add(d);
  @override
  Future<void> markRead(String id) async {}
}

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  final mail = FakeMail([
    Email(id: 'm1', account: 'me@x.com', sender: '张总', address: 'zhang@corp.com',
        subject: '合同确认', body: '条款三请今天确认', receivedAt: DateTime(2026, 7, 1, 9)),
    Email(id: 'm2', account: 'me@x.com', sender: '招商银行', address: 'no-reply@bank.com',
        subject: '账单提醒', body: '本期应还 3860', receivedAt: DateTime(2026, 7, 1, 8)),
  ]);
  final svc = EmailService(mail: mail);
  final mgr = Manager(router: const RuleRouter())..register(svc);

  stdout.writeln('▶ 定时巡检 → 重要才推送');
  final pushes = <AgentEvent>[];
  await for (final e in svc.onTrigger(const TriggerContext(kind: 'mail_poll', source: 'scheduler'))) {
    pushes.add(e);
  }
  check(pushes.length == 1, '巡检只推送 1 封重要（张总/合同），银行账单不打扰');
  check(pushes.first is AgentResult && (pushes.first as AgentResult).text.contains('张总'), '重要邮件=张总');

  stdout.writeln('▶ 查询');
  final r1 = await mgr.handle('有什么重要邮件');
  check(r1.usedAgents.contains('email') && r1.text.contains('合同确认'), '管家路由并列出重要邮件');

  stdout.writeln('▶ 起草回复 → 必须确认才发');
  check(mail.sent.isEmpty, '起草前未发送');
  final r2 = await mgr.handle('帮我回复张总说条款三没问题');
  check(r2.needsConfirm && r2.pendingConfirm!.actionKind == 'send_email', '回复 → 需确认(send_email)');
  check(r2.pendingConfirm!.preview['to'] == 'zhang@corp.com', '草稿收件人=张总地址');
  check('${r2.pendingConfirm!.preview['body']}'.contains('条款三没问题'), '草稿含用户意图');
  check(mail.sent.isEmpty, '出确认卡时仍未发送（安全闸口）');

  stdout.writeln('▶ 用户确认 → 发送（唯一发送路径）');
  final ok = await svc.confirmSend(r2.pendingConfirm!.id);
  check(ok && mail.sent.length == 1 && mail.sent.first.to == 'zhang@corp.com', '确认后发送到张总');

  stdout.writeln('\n✅ 邮件服务通过：巡检重要推送 · 查询 · 起草需确认 · 确认后发送。');
}
