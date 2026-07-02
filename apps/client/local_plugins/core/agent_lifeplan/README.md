# agent_lifeplan — 生活计划业务服务

`local_plugins/core/agent_lifeplan` · 纯 Dart · 建在 [`agent_kernel`](../agent_kernel/) 上

主动式服务（`SpecialistAgent`）：长期计划（储蓄/阅读/健身/减脂…）创建、进度跟踪、复盘。

## 能力
```
handle("定个读10本书的阅读计划")   创建计划（自动识别类型/单位；取最大数字为目标，规避"6月"噪声）
handle("读完了3本" / "存了1200")    更新进度（按类型匹配计划）
handle("看看我的计划进度")          列出各计划进度%
onTrigger(到点)                    复盘：列进度 + 落后(<50%)提醒
```
- `LifePlanStore` 端口落地（默认内存 → 移动端 local_db）。
- 公开 API：`addPlan` / `updateProgress` / `store.all`（供 UI 用）。

## 已验证（`dart run example/self_check.dart`，全绿）
创建（API + 自然语言）· 进度更新（82% / 30%）· 管家路由 · 查询 · onTrigger 复盘含落后提醒。
