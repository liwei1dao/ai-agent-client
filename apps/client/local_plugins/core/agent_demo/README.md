# agent_demo — 端到端演示

`local_plugins/core/agent_demo` · 纯 Dart · 把整套架构串成一条可运行的线

把 **管家 + 5 个业务服务 + 知识库 + 连接中心 + 服务级唤醒** 组装起来，`dart run` 跑一遍完整体验。

## 跑

```bash
dart pub get
dart run example/e2e.dart
```

## 覆盖的全链路（全绿）

1. **连接中心**授权邮箱 → `feeding(mail)`
2. **设备唤醒**（App 未开）"加个明天上午10点和张总开会" → 服务层直接建日程
3. **记账** "记一笔 午饭 38" → 财务归类餐饮
4. **知识库问答** "路由器密码是多少" → 管家注入资料 → 答出 admin8899
5. **健康** 记步数 · **生活计划** 建阅读计划
6. **邮件巡检**（主动）→ 只推重要（张总）
7. **回复邮件** → 确认闸口(send_email) → 确认后发送
8. **到点提醒** → 推进时钟触发日程提醒
9. **查询** → 列出日程

## 说明

- 依赖全部 `core/` 纯 Dart 包（agent_kernel + 5 业务服务 + agent_integrations + knowledge），path 依赖。
- 邮箱用假 `MailProvider`；其余服务用默认内存 Store。移动端把这些换成 local_db/真 Provider 即为生产形态（业务代码不变）。
- 这是**架构自洽性的活证据**：管家单一发声、意图路由、上下文注入、确认闸口、服务级唤醒、主动式 onTrigger —— 全部端到端跑通。
