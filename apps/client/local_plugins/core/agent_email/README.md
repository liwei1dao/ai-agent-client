# agent_email — 邮件业务服务

`local_plugins/core/agent_email` · 纯 Dart · 建在 [`agent_kernel`](../agent_kernel/) 上

第二个**主动式业务服务**（`SpecialistAgent`）：定时巡检 + 重要性判定 + 起草回复（**起草必须确认才发**）。

## 三条链路

```
onTrigger(调度到点)  拉未读 → 判重要性 → 重要才推送“📧 张总《合同确认》· 重要” + 落库（不打扰普通邮件）
handle("有什么重要邮件")  列出重要邮件
handle("帮我回复张总说…")  起草 → ⚠️ AgentNeedConfirm(草稿预览) —— 出确认卡时【不发送】
confirmSend(confirmId)     用户确认后的【唯一发送路径】→ MailProvider.sendDraft
```

## 端口（隔离外部依赖/模型，可换可测）

| 端口 | 默认（随包，可跑） | 生产实现 |
|------|------------------|----------|
| `MailProvider` | 测试用 FakeMail | **IMAP/SMTP**（`enough_mail`，见下）或 Gmail(OAuth/API/MCP) |
| `ImportanceJudge` | `RuleImportanceJudge`（VIP 发件人 + 关键词） | LLM 判定 |
| `ReplyDrafter` | `TemplateReplyDrafter`（占位） | `llm_openai` 起草 |

## 已验证（`dart run example/self_check.dart`，全绿）

巡检只推重要（银行账单不打扰）· 查询列出 · 回复需确认(send_email) · **出确认卡时未发送** · 确认后才发到正确地址。

## IMAP/SMTP 接入模板（用户选的通用方案）

```dart
// pubspec: dependencies: enough_mail: ^2.x
import 'package:enough_mail/enough_mail.dart';

class ImapMailProvider implements MailProvider {
  final String host, user, appPassword;               // 邮箱 + 授权码/应用专用密码
  ImapMailProvider(this.host, this.user, this.appPassword);

  @override
  Future<List<Email>> fetchUnread({DateTime? since}) async {
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer(host, 993, isSecure: true);
    await client.login(user, appPassword);
    await client.selectInbox();
    final res = await client.searchMessages(searchCriteria: 'UNSEEN');   // 或按 since
    // 拉取 res 的 envelope/正文 → 映射为 Email(id=messageId, sender/address/subject/body/receivedAt)
    await client.logout();
    return /* mapped */ [];
  }

  @override
  Future<void> sendDraft(Draft d) async {
    final smtp = SmtpClient('unihelper', isLogEnabled: false);
    await smtp.connectToServer(smtpHostOf(host), 465, isSecure: true);
    await smtp.authenticate(user, appPassword, AuthMechanism.login);
    final msg = MessageBuilder.buildSimpleMessage(
      MailAddress(user, user), [MailAddress(d.to, d.to)], d.body, subject: d.subject);
    await smtp.sendMessage(msg);
  }

  @override
  Future<void> markRead(String id) async { /* STORE +FLAGS \Seen */ }
}
```
> ⚠️ 未在本检出验证（需 `enough_mail` 依赖 + 真实邮箱凭据 + 网络）。服务逻辑（巡检/判重/起草/确认发送）已 `dart run` 跑绿；IMAP/SMTP 只是把 `MailProvider` 端口填上。

## 接线 / 落地

- 注册：`manager.register(EmailService(mail: ImapMailProvider(...)))`；关键词（邮件/回复/未读…）路由到此。
- 巡检由 Scheduler（前台服务）按频率（如每 30 分钟）调 `onTrigger`；`emails` 表持久化去重与处理状态（app-design §9）。
- 移动端原生：按此逻辑 Kotlin/Swift 实现 `SpecialistAgent`（同 agent_kernel_native 模式）。
- 凭据存本地加密（隐私本地优先）；发送前确认卡在管家统一弹出。
