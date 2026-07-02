# agent_finance — 财务业务服务

`local_plugins/core/agent_finance` · 纯 Dart · 建在 [`agent_kernel`](../agent_kernel/) 上

第三个**主动式业务服务**（`SpecialistAgent`）：记账 + 月度收支 + 预算预警 + 月报建议。

## 能力

```
handle("午饭38块" / "记一笔 咖啡22")   自然语言记账 → 归类（餐饮/交通/购物…）
handle("这个月花了多少" / "餐饮花了多少")  月度小结 / 分类查询
onTrigger(月度)                        产出月报 + 预算预警 + 建议（经管家推送）
```

- 纯逻辑（记账/分类/统计/预算）**可测**；OCR 拍小票、LLM 建议经端口接入。
- 预算：`budgets`（分类 limit，`'总'` 为总预算）；超预算自动预警。
- `clock` 可注入（测试/回溯）。

## 端口

| 端口 | 默认（跑绿） | 生产 |
|------|-------------|------|
| `Categorizer` | `RuleCategorizer`（关键词归类） | LLM 归类 |
| `AdvicePlanner` | `RuleAdvicePlanner`（超预算/结余建议） | LLM 理财建议 |
| 拍小票记账 | — | 多模态 OCR/Vision（`knowledge`/vendors）→ 提取金额分类 |

## 已验证（`dart run example/self_check.dart`，全绿）

记账分类（午饭→餐饮、工资→收入）· 月度统计（收/支/结余/分类）· 预算预警（餐饮超预算）· 管家记账/查询 · onTrigger 月报。

## 落地

- 注册：`manager.register(FinanceService(budgets: {...}))`；关键词（记一笔/花了/收入/月报…）路由到此。
- 持久化：内存换 `transactions`/`budgets` 表（app-design §9）；`onTrigger` 由 Scheduler 每月 1 日驱动。
- 移动端原生：按此逻辑 Kotlin/Swift 实现（同 agent_kernel_native 模式）。
