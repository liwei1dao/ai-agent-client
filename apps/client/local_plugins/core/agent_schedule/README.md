# agent_schedule — 日程业务服务

`local_plugins/core/agent_schedule` · 纯 Dart · 建在 [`agent_kernel`](../agent_kernel/) 上

第一个**主动式业务服务**（`SpecialistAgent`）：对话/唤醒创建日程 + 查询 + `onTrigger` 到点提醒。

## 能力

- `handle(task)`：自然语言创建（"提醒我后天下午3点去牙医" → 7/3 15:00 + 提前15分钟提醒）或查询（"我最近有什么安排"）。
- `onTrigger(ctx)`：调度引擎到点驱动，产出 `⏰ 提醒`（经管家推送到聊天/通知）。
- 公开 API：`addFromText` / `upcoming` / `events`（供 UI 与其它服务用）。
- `clock` 可注入（测试用）；`remindAdvance` 提醒提前量可配。

## 已验证（`dart run example/self_check.dart`，全绿）

解析创建（明天/后天 + 上午/下午 + N点）· 管家路由 · 查询列出 · 到点提醒（未到点不提醒）。

## 接线 / 落地

- 注册进管家：`manager.register(ScheduleService())`；关键词命中（日程/提醒/安排/开会/约…）即路由到此。
- 设备唤醒："加个明早十点的会" → WakeBus → `Manager.onWake` → 本服务创建（无 UI 也走通）。
- 生产化：内存换 `local_db` 持久化；`onTrigger` 由 Scheduler（前台服务）按 cron/到点驱动；对接**系统日历 / Google Calendar MCP**（读写双向）。
- 移动端原生：按此逻辑用 Kotlin/Swift 实现 `SpecialistAgent`（同 agent_kernel_native 模式）。
