# agent_kernel — 多 Agent 团队编排内核

`local_plugins/core/agent_kernel` · 纯 Dart · 核心零依赖

**对外一个 [Manager]（管家，单一发声）+ 对内一支 [SpecialistAgent]（专员）团队。** 是
[`docs/UniHelper-agents-protocol.md`](../../../../../docs/UniHelper-agents-protocol.md) 的可运行实现骨架。

同知识库策略：本纯 Dart 包 = **算法规范 + web/桌面运行时**；移动端 `agents_server`（纯原生）按此镜像。

## 组成

```
Manager                路由 → 分派(可多专员) → 汇总成"一个声音" + 上下文注入 + 确认闸口 + onWake
├─ Router / RuleRouter  关键词命中 → 候选专员；未命中 → LlmRouter 兜底 → fallback(chat)
├─ SpecialistAgent      专员接口：handle(TaskEnvelope)→Stream<AgentEvent>；onTrigger(自治)
├─ ContextProvider      每轮注入上下文（知识库 KnowledgeBusinessService.contextFor 在此接入）
├─ TaskEnvelope/AgentEvent  A2A 任务信封 + 事件(Partial/Progress/Result/NeedConfirm/Error)
└─ WakeBus/WakeEvent     服务级唤醒（device/hotword/schedule/…）→ Manager.onWake（无 UI 也走通）
```

## 已验证（`dart run example/self_check.dart`，全绿）

注册 4 专员 · 意图路由（翻译/闲聊/兜底）· **安全闸口**（邮件发送→NeedConfirm）· **KB 上下文注入** · **服务级唤醒**（设备"加个明早十点的会"→schedule）。

## 接线

- **现有 agent 纳管**：`agent_chat/translate/…` 各写一个实现 `SpecialistAgent` 的适配器（底层调其既有接口，不改基础模板；见 agents-protocol §0.1/§5）。
- **知识库**：`KnowledgeBusinessService.contextFor` 实现 `ContextProvider`（主动注入）；`kb.search` 作为一个专员/工具（被动检索）。
- **主动式服务**（日程/邮件/资讯/财务/健康）：各实现 `SpecialistAgent` + `onTrigger`，由调度/唤醒驱动。
- **移动端原生**：`agents_server`（Kotlin/Swift）按本包类型镜像 Manager/Router/SpecialistAgent/WakeBus。

## 用法

```dart
final mgr = Manager(router: const RuleRouter(), contextProvider: kb)
  ..register(chatAdapter)
  ..register(translateAdapter)
  ..register(scheduleService);

final reply = await mgr.handle('帮我把牙医改到明天');   // 单一回复：text/usedAgents/citations/pendingConfirm
if (reply.needsConfirm) { /* 弹确认卡 */ }

// 服务级唤醒
wakeBus.on((e) async => await mgr.onWake(e));
```
