# UniHelper 数据落地（原生层）+ 第三方连接架构

**项目名称**：UniHelper
**文档定位**：两条横切架构决策——① 业务数据落地原生层（local_db），② 第三方服务授权/连接中心（打通生活↔工作生态）。配合 [UniHelper-app-design.md](UniHelper-app-design.md) §9 数据模型、[UniHelper-agents-protocol.md](UniHelper-agents-protocol.md)。
**版本**：v0.1 · **日期**：2026-07-01

---

## 1. 业务数据落地原生层（持久化）

> **要求（用户定调）**：所有业务数据都要落到**原生层 local_db**，不只在内存——方便业务模块读取，**尤其是后台/设备唤醒时运行的助理服务（纯原生 agents_server，无 Flutter 也要能读写）**。

### 1.1 原则

- **单一事实源 = 原生 `local_db`(SQLite)**：日程/邮件/交易+预算/资讯/记录/记忆/知识库 全部持久化到 local_db。
- **谁写**：业务服务（可在后台/唤醒时）写；**谁读**：管家、各业务服务、Flutter UI 都读同一份。Flutter UI 只读 + 监听变化，不做权威写。
- **为什么**：设备唤醒"加个日程/回封邮件"要在服务层直接落库（App 被杀也不丢）；`generateReport`、跨服务引用（如财务查日程、管家注入记忆）都要读到同一份持久数据。

### 1.2 抽象：Store 端口（可测、可换）

每个服务的数据访问抽象成 **Store 端口**（如 `ScheduleStore/EmailStore/FinanceStore/NewsStore`）：

```
业务服务(ScheduleService/EmailService/FinanceService/…)
   │ 依赖
   ▼
XxxStore（端口）  ──默认──►  内存实现（web/桌面/单测，已跑绿）
                 ──原生──►  local_db DAO（Kotlin/Swift，移动端权威实现）
```

- 现状：schedule/email/finance/知识库 的核心逻辑已用内存跑绿；**下一步把内存换成 Store 端口**（纯 Dart 仍默认内存；移动端注入 local_db 实现）。这样"落地原生层"不改业务逻辑，只换端口实现——与 `EmbeddingProvider`/`MailProvider`/`OnnxSession` 一致的套路。

### 1.3 local_db 表（对齐 app-design §9，补充）

```
events / reminders            日程
emails / drafts               邮件（去重 message_id、处理状态）
transactions / budgets        财务
news_digests / news_items     资讯
records                       统一记录时间轴（各服务产出）
memories                      长期记忆
documents / doc_chunks / embeddings   知识库（或 knowledge_native 自带库）
connections                   第三方连接（见 §2）
```

### 1.4 移动端一致性

移动端 agents_server（纯原生）里的助理服务**直接读写 local_db DAO**；Flutter「生活/我的」页经 Pigeon 只读 + 监听。→ 后台服务改了数据，UI 回到前台即见；App 被杀期间服务照常落库。

### 1.5 原生 local_db DAO 落地模板（Kotlin 参考，Swift 同理）

每个 Dart `Store` 端口 → 一个原生 DAO（在 local_db SQLite 上实现同名接口）。以 `ScheduleStore` 为例（其余 email/finance/connections **照此复制**）：

```kotlin
// 原生 ScheduleStore（与 Dart 端口同签名；接进原生 ScheduleService）。
// 用法：new ScheduleService(store = SqliteScheduleStore(db))
class SqliteScheduleStore(private val db: SQLiteDatabase) : ScheduleStore {
    // 表：events(id TEXT PK, title TEXT, start_at INTEGER, remind_at INTEGER, done INTEGER)
    override suspend fun add(e: ScheduleEvent) {
        db.insertWithOnConflict("events", null, ContentValues().apply {
            put("id", e.id); put("title", e.title)
            put("start_at", e.startAt); put("remind_at", e.remindAt); put("done", if (e.done) 1 else 0)
        }, SQLiteDatabase.CONFLICT_REPLACE)
    }
    override suspend fun all(): List<ScheduleEvent> =
        db.query("events", null, null, null, null, null, "start_at ASC").use { c ->
            buildList { while (c.moveToNext()) add(rowToEvent(c)) }
        }
    override suspend fun update(e: ScheduleEvent) = add(e) // upsert
}
```

- **凭据/连接**：`ConnectionStore` → local_db `connections` 表；`CredentialVault` → **Android EncryptedSharedPreferences / iOS Keychain**（`connections` 只存 credRef，密钥进钥匙串，不明文落库）。
- **复用现有 local_db**：优先在既有 `local_db` 插件里加 `events/emails/transactions/budgets/records/connections` 表与 DAO（与其 `ServiceConfigDao/AgentDao/...` 同处），而非另起 db。
- **前置**：需先有各服务的**原生版（Kotlin/Swift）+ 原生 Store 接口**（同 knowledge_native/agent_kernel_native 模式）；本模板是把该原生 Store 接落到 local_db 的参考。⚠️ 未在本检出编译验证（无 Android/Xcode 工具链 + 无 local_db 真实 API），请在真实环境按此接。

---

## 2. 第三方服务授权 / 连接中心（生活↔工作生态）

> **要求**：助理界面右上加"连接/授权"菜单，用户在此授权 **邮件 / 钉钉 / 企业微信 / 飞书 / …** 及后续**一切第三方**——**打通生活到工作的生态**。

### 2.1 入口与形态

- **主入口**：首页聊天右上 🔗「连接与授权」；**副入口**：我的 → 连接与授权。
- **一屏统一管理**（见 design/client2.0 效果图「服务授权中心」）：按 通讯·邮件 / 工作协同 / 日历·任务 / 更多 分组，每项显示连接状态 + 连接/管理。

### 2.2 抽象：Connector + IntegrationRegistry

每个第三方 = 一个 **Connector**：

```dart
class Connector {
  String id;                 // "email" | "dingtalk" | "wecom" | "feishu" | "gcal" | "mcp:xxx"
  String name;
  AuthType authType;         // oauth | token | imap | mcp | system
  ConnStatus status;         // connected | disconnected | expired
  String? account;           // 展示用（zhang@x.com）
  List<String> scopes;       // 授权范围
  String? credRef;           // 凭据引用（本地加密存储，不明文落库）
  List<String> feeds;        // 它能喂给哪些业务：mail|calendar|tasks|messages|approval|tool
}

abstract interface class IntegrationRegistry {
  Future<List<Connector>> list();
  Future<void> connect(String id, AuthPayload payload);   // OAuth 回调 / token / IMAP 授权码
  Future<void> disconnect(String id);
  Future<void> refresh(String id);                        // 刷新 token
}
```

- **持久化**：`connections` 表（id/kind/name/auth_type/account/status/scopes/cred_ref/created_at）；**凭据本地加密**（隐私本地优先），不明文落库。
- **远程 MCP**：走现有 `McpServerConfig`（后续「联网 MCP」也在此挂）。

### 2.3 连接 → 喂给业务服务（关键逻辑）

连接中心是"数据/能力源"，业务服务的端口实现由**已连接的 Connector 提供**：

| Connector | 授权方式 | 喂给（feeds） | 对接的业务/端口 |
|-----------|---------|--------------|----------------|
| 邮箱 | IMAP 授权码 / Gmail OAuth | mail | `EmailService.MailProvider` |
| 系统日历 / Google Calendar | 系统权限 / OAuth(或 MCP) | calendar | `ScheduleService`（双向同步） |
| 钉钉 | OAuth | tasks/calendar/messages/approval | 新增 `WorkConnector` → 待办/日程/记录 |
| 企业微信 | OAuth | messages/approval/meeting | 同上 |
| 飞书 | OAuth | docs/calendar/messages | 同上 |
| 任意第三方 | MCP | tool | 对 LLM 暴露 MCP 工具（管家可调） |

- **打通生活↔工作**：生活侧（个人邮箱/日历/健康）+ 工作侧（钉钉/企业微信/飞书）连进来后，数据统一落 `local_db`，由**同一个管家 + 同一套业务服务**调度——用户在一条对话里既能"回工作邮件"又能"记生活账"，跨域协同（如"把钉钉这条待办加进我的日程并提醒"）。

### 2.4 授权流程

```
连接中心选服务 → 授权（OAuth 跳转 / 填 token / IMAP 授权码 / 系统权限）
  → 凭据本地加密存 connections → 对应业务服务端口即可用（如 MailProvider 就绪）
  → 状态置 connected；断开则回收凭据、置 disconnected
  → token 过期 → status=expired → 提示重新授权
```

---

## 3. 落地顺序

1. **retrofit 现有服务到 Store 端口** + 移动端 local_db DAO（schedule/email/finance）。
2. **连接中心**：`IntegrationRegistry` + `connections` 表 + UI（已出效果图）。
3. **邮箱 Connector（IMAP）** 打通 → `EmailService.MailProvider`。
4. **系统日历 Connector** → `ScheduleService` 双向同步。
5. **钉钉/企业微信/飞书 Connector**（OAuth/MCP）→ `WorkConnector` 喂待办/日程/消息。
6. **联网 MCP** → 资讯（`NewsSource`）与通用工具。
