# agent_integrations — 第三方连接与授权中心

`local_plugins/core/agent_integrations` · 纯 Dart · 核心零依赖

统一授权 **邮件 / 钉钉 / 企业微信 / 飞书 / 日历 / MCP …**，打通**生活↔工作生态**；连接后把数据源**喂给业务服务端口**。对应 UI「服务授权中心」（design/client2.0，聊天右上 🔗）与 [docs/UniHelper-integrations-persistence.md](../../../../../docs/UniHelper-integrations-persistence.md)。

## 结构

```
Connector           一个第三方连接器：authType(oauth/token/imap/mcp/system) · status · account · scopes · credRef · feeds
IntegrationRegistry connect / disconnect / refresh · credentialsOf · feeding(能力) · restore · addConnector(动态MCP)
ConnectionStore     连接状态持久化（默认内存；移动端 local_db 的 connections 表）
CredentialVault     凭据保险箱（默认内存；移动端平台钥匙串/加密存储；connections 只存 credRef 引用）
Feed                mail/calendar/tasks/messages/approval/tool/docs/health —— 连接器"能喂什么"
```

## 关键逻辑：连接 → 喂业务服务

业务服务不直接持有凭据，而是问注册中心"谁能喂我这个能力"：

```dart
final reg = IntegrationRegistry();
await reg.connect('email', AuthPayload.imap('imap.x.com', 'me@x.com', 'app-pass'));

// EmailService 找邮件数据源：
final mailConns = reg.feeding(Feed.mail);              // → [email]
final cred = await reg.credentialsOf('email');         // 从保险箱取凭据
// 用 cred 构建 ImapMailProvider → new EmailService(mail: provider)
```

| 连接器 | feeds | 喂给 |
|--------|-------|------|
| 邮箱(IMAP/Gmail) | mail | `EmailService.MailProvider` |
| 系统日历/Google Calendar | calendar | `ScheduleService`（双向） |
| 钉钉/企业微信/飞书 | tasks/messages/approval/… | `WorkConnector` → 待办/日程/记录 |
| MCP（动态添加） | tool/docs | 对 LLM 暴露工具（含"联网 MCP"） |

## 已验证（`dart run example/self_check.dart`，全绿）

默认目录 6 个 · 授权邮箱（凭据入保险箱、可取回）· `feeding(mail)` 喂业务 · 跨会话 `restore` · 动态加 MCP → `feeding(tool)` · 断开回收凭据。

## 落地

- 移动端实现 `ConnectionStore`(local_db connections 表) + `CredentialVault`(钥匙串) —— **凭据本地加密、不明文落库**。
- OAuth 类连接器走系统浏览器授权回调后 `connect(...)`；IMAP 填授权码；系统日历走系统权限。
- 与 UI：连接中心页调 `list()/connect()/disconnect()`；业务服务启动时用 `feeding()` 装配端口。
