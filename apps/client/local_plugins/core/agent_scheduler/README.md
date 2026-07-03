# agent_scheduler — 调度引擎

`local_plugins/core/agent_scheduler` · 纯 Dart · 建在 agent_kernel 上

把「订阅」按时驱动成主动式服务的 `onTrigger`——补上 **订阅 Tab → 定时触发 → 推送** 这条线。

## 概念

```
Subscription（订阅项，来自「订阅 Tab」）
├─ every(Duration)   如 邮件巡检每 30 分钟
└─ dailyAt(h, m)     如 资讯每日 08:00、健康提醒每日 20:00

Scheduler.tick(now)
  对每条到点(isDue)的订阅 → 调其 agentId 对应业务服务的 onTrigger
  → 收集 AgentResult → Push（→ 管家按模板推进首页聊天）
  → 推进 lastRun（当天/本周期不重复）
```

## 已验证（`dart run example/self_check.dart`，全绿）

every 间隔到点 · dailyAt 到点 · 当天不重复 · 停用生效 · 触发 onTrigger 收集推送。

## 接线

- **订阅 Tab** 的每一项 = 一条 `Subscription`（持久化到 local_db，见 UniHelper-app-design §9 tasks 表）。
- **业务服务**（日程/邮件/财务/健康/咨询）注册进 Scheduler；`tick()` 由 `agents_server` 前台服务定时调用（Android/iOS 后台保活）。
- **推送** 交给管家按模板生成首页聊天里的主动消息。
- `clock` 可注入以便测试；`tick(at)` 可传显式时刻。
