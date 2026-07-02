# agent_health — 健康业务服务

`local_plugins/core/agent_health` · 纯 Dart · 建在 [`agent_kernel`](../agent_kernel/) 上

主动式服务（`SpecialistAgent`）：记录健康数据 + 目标提醒。

## 能力
```
handle("今天走了6200步" / "睡了7.2小时" / "喝了3杯水" / "体重65")  记录当天指标
handle("今天健康怎么样")                                        当天汇总
onTrigger(到点)                                                喝水/步数等目标未达 → 提醒
```
- `HealthStore` 端口落地（默认内存 → 移动端 local_db / 系统健康 HealthKit·Google Fit）。
- `HealthGoals`（步数/饮水/睡眠目标）可配；`clock` 可注入。

## 已验证（`dart run example/self_check.dart`，全绿）
记录（步数/睡眠/饮水/体重）· 查询汇总 · "又喝了一杯水"无数字 +1 · onTrigger 未达目标提醒。
