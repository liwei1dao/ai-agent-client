# UniHelper 多 Agent 团队 · 接口与协议草案

**项目名称**：UniHelper
**文档定位**：`agents_server` 内「管家 + 专员团队」的**工程接口草案**——专员注册、任务信封、A2A 事件、Flutter↔管家 Pigeon API、调度/确认协议。是 [UniHelper-agents.md](UniHelper-agents.md) 的落地接口层。
**版本**：v0.1（草案，供评审）
**日期**：2026-07-01
**状态**：接口评审稿

> 类型用 Dart 表达（与现有 Pigeon 体系一致）。协议**逻辑上定义一次**，各平台各自实现：移动端在原生宿主（Kotlin/Swift）内进程运行；Web/桌面用 `agents_server` 的 Dart 运行时（沿用现有条件导入跨端方案）。

---

## 0. 分层与三条边界

```
┌── Flutter UI（只见管家）────────────────────────────────────┐
│                                                             │
│  边界①  Flutter ⇄ 管家   —— Pigeon（HostApi 命令 / FlutterApi 事件）│
│         移动端走 MethodChannel/EventChannel；Web/桌面走直接 Dart 调用 │
└───────────────┬─────────────────────────────────────────────┘
                ▼
┌── agents_server（团队宿主：Manager + 调度引擎 + AgentBus）──────┐
│                                                              │
│  边界②  管家 ⇄ 专员   —— AgentBus（TaskEnvelope 下发 / AgentEvent 回传）│
│         同进程内，专员实现 SpecialistAgent 接口                  │
└───────────────┬─────────────────────────────────────────────┘
                ▼
┌── 专员 ⇄ 能力 ──────────────────────────────────────────────┐
│  边界③  专员 ⇄ Provider/工具 —— service_manager（Provider 池）+ MCP │
│         （已存在，本文不展开）                                    │
└──────────────────────────────────────────────────────────────┘
```

- **管家（Manager）**：边界①的唯一对端，边界②的发起方。
- **专员（Specialist）**：由 `AgentBus` 调度、向管家回传 `AgentEvent`。
- 现有 `agent_chat / agent_sts_chat / agent_translate / agent_ast_translate` **通过适配器接入**（见 §0.1，**不改动其基础模板**）；新专员 `agent_schedule / agent_email / agent_news / agent_finance / agent_health` 同样在基础模板之上实现。

### 0.1 底线：现有 Agent 基础模板不动（本协议是叠加层）

> ⚠️ **现有的 Agent 基础模板（每个 agent 实现并注册进 `agents_server` 的既有契约，如 agent_chat/translate/… 的 `NativeAgent` 注册）是所有 agent 的共同底座，本协议一行都不改它、不取代它。** 翻译等现有 agent 继续跑在原模板上；以后要和**硬件配合**的 agent 也复用同一模板。

本协议的 `SpecialistAgent` **不是新的 agent 基类**，而是**管家看待一个 agent 的"协作外观"**——由一层 **`SpecialistAdapter` 把现有 agent 包进来**：

```
      现有 Agent 基础模板（不动）                本协议叠加层（新增）
   ┌──────────────────────────┐          ┌────────────────────────────┐
   │ NativeAgent 契约          │          │  SpecialistAdapter          │
   │  · 会话/管线(startSession │  ◄─包装─ │   实现 SpecialistAgent      │
   │    /sendText/interrupt…)  │          │   · capability 描述符        │
   │  · 事件(stt/llm/tts…)     │  ──映射─►│   · handle()→驱动底层 agent  │
   │  · 翻译/对话/硬件… 都用它  │          │   · onTrigger()（自治）      │
   └──────────────────────────┘          └────────────────────────────┘
```

- **基础模板**管"一个 agent 怎么跑自己的管线"（会话、STT/LLM/TTS、硬件 I/O…）——**保留**。
- **`SpecialistAdapter`** 管"管家怎么调它、它怎么向管家汇报、怎么被调度自治"——**新增**。
- 现有 agent 零改动即可被纳管；不想被管家托管的 agent（如某些纯硬件链路）也能继续独立用基础模板直连，二者并存。

### 0.2 术语对齐：框架 / 业务服务 / 大楼

本协议落在「服务为骨」分层里（见 [UniHelper.md](UniHelper.md) §5.0）：

| 分层 | 是什么 | 本协议里的对应 |
|------|--------|---------------|
| 🏗️ **框架层** | 稳定内核，尽量少改 | Agent 基础模板 / `agents_server`（Manager·AgentBus·Scheduler·**Wake Bus**）/ `service_manager` / 设备框架 / `local_db` / MCP |
| 🧱 **业务服务层** | 建在框架上的一个个"服务" | **一个专员 = 一个业务服务**（翻译服务/日程服务/…）= `SpecialistAdapter` + 领域逻辑 |
| 🏢 **大楼（Flutter）** | 业务管理/分类/定制/UI | 边界①的对端，不做核心执行 |

> 即：`SpecialistAgent`/`SpecialistAdapter`/`AgentCapability` 是**框架契约**；每个专员的领域实现是**业务服务**。"翻译助手"就是一个业务服务，跑在框架上、可被管家调、也可被 Wake 直唤。

---

## 1. 核心类型与枚举

```dart
typedef AgentId        = String;  // "manager" | "agent.email" | "agent.schedule" ...
typedef TaskId         = String;  // 单个子任务 uuid
typedef RequestId      = String;  // 用户一次请求的根 id（贯穿多专员协同）
typedef ConversationId = String;
typedef ConfirmId      = String;
typedef PushId         = String;

enum AgentStatus { ok, partial, needConfirm, rejected, failed, cancelled }
enum Priority    { low, normal, high, urgent }
enum TriggerKind { schedule, event, manual }          // 自治触发类型
enum ActionRisk  { none, low, high }                  // high = 必须用户确认

// 标准错误码（AgentError.code）
// AUTH_REQUIRED | SCOPE_DENIED | TOOL_UNAVAILABLE | PROVIDER_ERROR |
// RATE_LIMIT | TIMEOUT | CONFLICT | INVALID_PARAMS | UNSUPPORTED | INTERNAL
```

---

## 2. 专员注册：能力描述符（Capability Descriptor）

专员启动时向管家注册一份**能力描述符**——管家据此做**意图路由**、**权限校验**、**调度**与**模型分层**。等价于把"专员"暴露为管家可调用的能力（Agent-as-Tool）。

```dart
class AgentCapability {
  final AgentId agentId;              // "agent.email"
  final String  name;                 // "邮件专员"（用户可见/团队花名册）
  final String  domain;               // "email"
  final String  description;          // 供管家/LLM 路由的自然语言说明
  final List<IntentSpec> intents;     // 声明能处理的意图
  final List<String> requiredScopes;  // 权限：mailbox / calendar / health / phone ...
  final List<String> requiredTools;   // 依赖的 MCP 工具 / Provider 类型
  final bool autonomous;              // 是否可被调度自治（进"订阅"）
  final List<TriggerSpec> triggers;   // 默认触发声明（可被订阅覆盖）
  final ConfirmPolicy confirmPolicy;  // 哪些动作需用户确认
  final ModelHint model;              // 建议模型档位（成本/延迟分层）
  final int protocolVersion;          // 本协议版本，用于兼容校验
}

class IntentSpec {
  final String intent;                // "reply_email"
  final String description;           // "根据用户意图起草/发送邮件回复"
  final Map<String, dynamic> paramSchema; // JSON Schema
  final ActionRisk risk;              // 该意图默认风险级
  final List<String> examples;        // few-shot 例句，助管家路由
}

class TriggerSpec {
  final TriggerKind kind;             // schedule | event
  final String? cron;                 // kind=schedule："0 8 * * *"
  final String? eventType;            // kind=event："incoming_call" | "sit_2h"
  final Map<String, dynamic> params;  // 主题/频率/阈值等默认值
}

class ConfirmPolicy {
  // 需用户确认的动作类型：send_email / payment / delete / external_share ...
  final List<String> requireConfirm;
  final bool confirmByDefault;        // 未声明的高风险动作是否默认要确认（建议 true）
}

enum ModelTier { light, standard, strong }   // 管家=strong 规划；多数专员=light/standard
class ModelHint { final ModelTier tier; final String? preferredModel; }
```

管家侧注册接口：

```dart
abstract class AgentRegistry {
  void register(SpecialistAgent agent);       // 启动时
  void setEnabled(AgentId id, bool enabled);  // "我的→助手管理" 开关
  List<AgentCapability> list();               // 团队花名册
  SpecialistAgent? resolve(AgentId id);
}
```

---

## 3. 任务信封（TaskEnvelope）

管家分派给专员的**标准载荷**。跨多专员协同时共享同一 `requestId`。

```dart
class TaskEnvelope {
  final TaskId    taskId;
  final RequestId requestId;          // 用户根请求（多专员共享）
  final AgentId   from;               // "manager"（或专员再委派时的发起方）
  final AgentId   to;                 // 目标专员
  final String    intent;             // 命中的意图
  final Map<String, dynamic> params;  // 结构化参数（管家从用户输入抽取）
  final TaskContext context;          // 共享上下文/记忆
  final bool      needConfirm;        // 结果落地前是否必须用户确认
  final Priority  priority;
  final int?      deadlineTs;         // 截止（可选）
  final int       createdAt;
}

class TaskContext {
  final ConversationId conversationId;
  final List<MemoryRef>  memories;    // 相关长期记忆（管家检索后注入）
  final List<MessageRef> recentTurns; // 近 N 轮对话
  final Map<String, dynamic> blackboard; // 共享黑板快照（本 request 内多专员可见）
  final String? locale;
}

class MemoryRef  { final String id; final String scope; final String text; }
class MessageRef { final String id; final String role; final String text; }
```

---

## 4. A2A 事件（专员 → 管家）

专员处理任务时以**事件流**回传；管家据此聚合、决定是否呈现给用户、是否求确认。

```dart
sealed class AgentEvent {
  final TaskId  taskId;
  final RequestId requestId;
  final AgentId from;
  final int     ts;
}

class AgentProgress   extends AgentEvent { final String stage; final double? percent; final String? note; }
class AgentPartial    extends AgentEvent { final String chunk; }               // 流式中间结果
class AgentNeedConfirm extends AgentEvent { final ConfirmRequest request; }    // 上报确认（见 §9）
class AgentResult     extends AgentEvent {
  final AgentStatus status;             // ok / partial / rejected / failed ...
  final Map<String, dynamic> data;      // 结构化结果
  final RenderHint render;              // 建议呈现方式（气泡/卡片/模板）
  final List<QuickAction> actions;      // 结果附带的快捷动作
}
class AgentError      extends AgentEvent { final String code; final String message; final bool retriable; }
class AgentDelegate   extends AgentEvent { final TaskEnvelope subtask; }       // 请求再委派（经管家）

class RenderHint { final String kind; /* "bubble"|"card"|"template" */ final String? template; }
class QuickAction { final String id; final String label; final String intent; final Map<String,dynamic> params; }
```

**协作外观接口**（管家看到的每个专员长这样；由适配器实现，**不是** agent 基类）：

```dart
abstract class SpecialistAgent {
  AgentCapability get capability;

  /// 处理一个任务，回传事件流（可含 Partial/Progress/NeedConfirm，最终以 AgentResult/AgentError 收尾）
  Stream<AgentEvent> handle(TaskEnvelope task);

  /// 自治触发（调度引擎/事件总线调用）；产出经管家转推送
  Stream<AgentEvent> onTrigger(TriggerContext ctx);

  /// 取消某任务（用户打断 / 被抢占）
  Future<void> cancel(TaskId taskId);
}
```

**适配器**把现有 Agent 基础模板包成一个 `SpecialistAgent`——**现有 agent 不改**，适配器负责把 `TaskEnvelope` 翻成底层 agent 的既有调用（如 `startSession/sendText`），并把底层事件（stt/llm/tts…）映射成 `AgentEvent`：

```dart
/// 通用适配器：包住任何遵循现有基础模板的 agent（翻译/对话/硬件…）
class SpecialistAdapter implements SpecialistAgent {
  SpecialistAdapter(this._base, this._capability);   // _base = 现有 NativeAgent 实例（不改）
  final BaseAgent _base;                              // ← 现有基础模板类型（占位名）
  final AgentCapability _capability;

  @override AgentCapability get capability => _capability;

  @override
  Stream<AgentEvent> handle(TaskEnvelope task) async* {
    // 1) 把 intent/params 翻成底层 agent 的既有命令（startSession/sendText/…）
    // 2) 订阅底层既有事件(onLlmChunk/onTtsPlaybackDone/翻译结果/硬件回调)
    //    → 逐条映射为 AgentPartial / AgentProgress / AgentResult / AgentError
    // 3) 高风险动作 → yield AgentNeedConfirm
  }
  @override Stream<AgentEvent> onTrigger(TriggerContext ctx) async* { /* 自治映射 */ }
  @override Future<void> cancel(TaskId taskId) => _base.interrupt(/*…*/);
}
```

> `BaseAgent` 是**占位名**，落地时替换为你现有的基础模板类型（如 `NativeAgent`）。要点：**适配器向下用你既有的 agent 接口，向上暴露 `SpecialistAgent`**，两层解耦、基础模板零改动。

class TriggerContext {
  final TriggerKind kind; final String source;       // "subscription:news_daily"
  final RequestId requestId; final Map<String,dynamic> params;
  final TaskContext context; final int firedAt;
}
```

---

## 5. 管家与消息总线（内部）

```dart
abstract class ManagerAgent {
  /// 边界① 入口：收到用户输入 → 路由/分解 → dispatch → 聚合 → 通过 ManagerEventApi 回传
  Future<void> onUserInput(UserInput input);
  /// 用户对确认请求的回应
  Future<void> onUserConfirm(ConfirmId id, bool approved, {Map<String,dynamic>? edited});
  /// 打断一次请求（含其所有在途子任务）
  Future<void> cancel(RequestId requestId);
}

abstract class AgentBus {
  /// 把任务发给 to 指定专员，返回其事件流（管家订阅之）
  Stream<AgentEvent> dispatch(TaskEnvelope task);
  /// 并行分派一组子任务（多专员协同），返回合并事件流
  Stream<AgentEvent> dispatchAll(List<TaskEnvelope> tasks);
}
```

**管家处理主循环（伪码）**：

```
onUserInput(input):
  requestId = new()
  route = router.classify(input, registry.list())      // 规则 + 轻模型；命中一个或多个 intent
  ctx   = buildContext(input.conversationId)            // 检索记忆 + 近况 + 黑板
  if route.single:
     stream = bus.dispatch(TaskEnvelope(to=route.agent, ...))
  else:                                                  // 多专员协同
     plan   = planner.decompose(input, route)            // 串行/并行子任务图
     stream = bus.dispatchAll(plan.tasks)
  for e in stream:
     match e:
       AgentPartial     -> emit onAssistantChunk(...)    // 以管家口吻流式
       AgentNeedConfirm -> emit onConfirmRequest(...)    // 转给用户
       AgentResult      -> aggregate(e); persist(records)
       AgentError       -> policy(retry|degrade|surface)
  reply = aggregate.summarize()                          // 汇总成"一个声音"
  emit onAssistantMessage(reply)
```

---

## 6. 边界①：Flutter ⇄ 管家（Pigeon）

### 6.1 命令（Flutter → 管家）

```dart
@HostApi()
abstract class ManagerApi {
  // 发送用户消息（文本 / 语音转写结果 / 带附件）；requestId 由 Flutter 生成用于打断追踪
  void sendUserMessage(ConversationId conversationId, RequestId requestId, UserMessageDto msg);
  // 触发快捷动作（点击推送卡/结果卡上的按钮）
  void invokeQuickAction(RequestId requestId, String actionId, Map<String, Object?> params);
  // 回应确认请求（发邮件/支付…）
  void respondConfirm(ConfirmId confirmId, bool approved, String? editedPayload);
  // 打断
  void cancel(RequestId requestId);
  // 订阅开关（= 专员自治任务开关；对应"订阅"Tab）
  void setSubscription(String subscriptionId, bool enabled);
  void updateSubscription(String subscriptionId, Map<String, Object?> config);
  // 团队花名册 / 助手管理
  List<AgentCapabilityDto> listAgents();
  void setAgentEnabled(AgentId agentId, bool enabled);
  // 前后台通知（供宿主决策后台保活/通知栏）
  void notifyAppForeground(bool isForeground);
}

class UserMessageDto {
  final String? text;
  final String? inputMode;                 // "text"|"voice"|"call"
  final List<AttachmentDto> attachments;   // 图片/文件
}
class AttachmentDto { final String kind; final String uri; final String mime; }
```

### 6.2 事件（管家 → Flutter，EventChannel）

```dart
@FlutterApi()
abstract class ManagerEventApi {
  // ── 助手对话（统一由管家发声）──
  void onAssistantMessageStart(ConversationId c, RequestId r);
  void onAssistantChunk(ConversationId c, RequestId r, String chunk, bool done); // 流式
  void onAssistantMessage(ConversationId c, RequestId r, AssistantMessageDto msg); // 完整消息

  // ── 模板化主动推送（晨间简报/资讯/提醒/邮件摘要…）──
  void onPush(PushMessageDto push);

  // ── 团队协作可见性（可选 UI：谁在处理）──
  void onAgentActivity(RequestId r, AgentId agentId, String stage); // "邮件专员起草中…"

  // ── 需要用户确认（高风险动作闸口）──
  void onConfirmRequest(ConfirmRequestDto req);

  // ── 订阅/助手状态变化 ──
  void onSubscriptionState(String subscriptionId, bool enabled, int? nextRunTs);

  // ── 错误 ──
  void onError(RequestId r, String code, String message);
}

class AssistantMessageDto {
  final String text;
  final List<AgentTag> usedAgents;   // 本轮参与的专员（可在气泡上标注）
  final List<QuickActionDto> actions;
  final RenderHintDto render;
}
class AgentTag { final AgentId agentId; final String name; }

class PushMessageDto {
  final PushId pushId;
  final String template;             // "briefing" | "news" | "reminder" | "mail_summary" | "finance_report"
  final AgentId agentId;             // 来源专员（"咨询订阅"标签）
  final String title;
  final String body;
  final Map<String, Object?> data;   // 模板专用结构（如资讯条目数组）
  final List<QuickActionDto> actions;
  final int ts;
}

class ConfirmRequestDto {
  final ConfirmId confirmId;
  final AgentId agentId;
  final String actionKind;           // "send_email" | "payment" | "delete" | "calendar_write"
  final String summary;              // 给用户看的一句话
  final Map<String, Object?> preview;// 邮件草稿 / 支付详情 / 待删项
  final bool editable;               // 是否允许用户改后再确认
}

class QuickActionDto { final String id; final String label; final String intent; }
class RenderHintDto  { final String kind; final String? template; }
```

> **要点**：无论内部几个专员参与，Flutter 只收到 `onAssistantMessage`/`onPush`——**一个声音**。`usedAgents`/`onAgentActivity` 仅用于可选的"团队感"展示，默认可不显示。

---

## 7. 调度 / 自治触发协议

自治专员的触发由 `agents_server` 内的**调度引擎**驱动，数据源是 `tasks` 表（= 订阅）。

```dart
abstract class Scheduler {
  void loadFromDb();                          // 读 tasks（订阅）→ 建定时/事件监听
  void onSubscriptionChanged(String subscriptionId);
  // 到点/事件触发 → 组 TriggerContext → 调 specialist.onTrigger → 事件流 → 管家转推送
}
```

触发链：

```
tasks(订阅) ──► Scheduler 到点/事件
                    │ TriggerContext
                    ▼
           SpecialistAgent.onTrigger()  ──AgentResult──►  Manager
                                                            │ 按 template 包装
                                                            ├─► onPush(PushMessageDto)   // 进首页聊天
                                                            └─► 写 records（"生活/动态"可追溯）
```

- iOS 后台定时不保证精确（BGTaskScheduler）——协议层允许 `nextRunTs` 漂移，专员需幂等。
- Android 由 `agents_server` 前台服务保活，定时较准。

---

## 7.5 服务级唤醒协议（Wake）★

**核心能力：对话与办事必须能被服务层直接唤起并完成，无需 Flutter 在前台。** 框架层的 **Wake Bus** 统一接入各类唤醒源，唤起管家或直唤某业务服务。

```dart
enum WakeSource {
  device,        // 设备事件：连接/按键/设备端唤醒词（BLE/JieLi → 设备框架）
  hotword,       // 本机语音唤醒词（"你好 UniHelper"）
  schedule,      // 订阅到点（Scheduler）
  incomingCall,  // 来电（电话服务）
  geofence,      // 地理围栏 / 系统事件
  push,          // 远程静默推送
}

class WakeEvent {
  final WakeSource source;
  final String     sourceId;        // "device:buds-01" | "hotword" | "sub:news_daily"
  final String?    utterance;       // 若已带语音/文本意图（如设备端 STT 结果）
  final Map<String, dynamic> payload;
  final int        firedAt;
}

abstract class WakeBus {
  /// 框架内各唤醒源统一上报入口
  void emit(WakeEvent e);
  /// 订阅（管家/业务服务注册关注的唤醒源）
  void on(WakeSource source, WakeHandler handler);
}

abstract class WakeRouter {   // 框架层：决定唤醒后交给谁
  /// 默认 → 唤起管家(Manager) 走正常路由；
  /// 明确领域（如设备快捷键绑定"加日程"）→ 直唤对应业务服务
  FutureOr<void> route(WakeEvent e);   // 无 Flutter 也可执行
}
```

**唤醒→完成链路（无 UI 也走通）**：

```
WakeSource（设备/唤醒词/定时/来电）
   └─ WakeBus.emit(WakeEvent)
        └─ WakeRouter.route
             ├─ 交管家：Manager.onWake(e) → 路由 → 业务服务 handle()
             └─ 直唤：dispatch(TaskEnvelope{to: 业务服务, intent, params})
                  └─ 业务服务在服务层完成（加日程/起草/开始通话翻译）
                       ├─ 落 local_db（events/records/…）
                       ├─ 反馈：系统通知 / TTS 播报 / 设备指示灯
                       └─ Flutter 在场 → onAssistantMessage/onPush 更新 UI；不在场也已完成
```

管家补充入口（供框架唤醒调用）：

```dart
abstract class ManagerAgent {
  // …（前述）
  Future<void> onWake(WakeEvent e);   // 被 Wake Bus 唤起（可能无 Flutter 会话在场）
}
```

要点：
- **唤醒是框架能力**：唤醒源接入、路由、无 UI 执行都在框架层；业务服务只需声明"能被哪些唤醒源直唤"（写进 `AgentCapability.triggers` / 设备快捷键绑定）。
- **设备联动**：连上设备后，设备端唤醒词/按键 → `WakeSource.device` → 直唤对应业务服务（"加日程"），这正是本能力的典型场景。
- **反馈通道解耦**：结果通过通知/TTS/设备反馈给用户，Flutter 只是可选的富呈现层。

### 7.5.1 设备唤醒 + App 被杀存活（硬要求）

**目标**：连上设备后，**即使 Flutter App 进程被杀**，设备发来的唤醒指令也能启动音频对话、完成对话与办事（如加日程）。

**音频链路（全在服务层，与 Flutter 死活无关）**：

```
设备（BLE）──唤醒指令──► agents_server（原生宿主，持有 BLE 连接）
   ▲                         │ WakeEvent{source:device, ...}
   │ 用户语音(设备麦克风)      ▼
   └──音频流──► 设备框架(device_manager/JieLi) ──► STT ──► LLM/业务服务
                                                          │  加日程/查询/…
   TTS 语音 ◄──设备扬声器◄── agents_server ◄─────────────┘
              （对话界面：Flutter 在场则 onAssistantMessage 刷新；不在场也已完成）
```

- **BLE 连接与音频 I/O 由 `agents_server` 原生持有**，不经 Flutter；"对话界面"是可选的富呈现，掉线不影响任务完成。
- 设备唤醒后：`WakeSource.device → WakeBus → WakeRouter → Manager.onWake / 直唤业务服务 → 服务层完成 → 落库 + TTS 回设备 + 通知`。

**App 被杀后的存活性（平台现实，如实标注）**：

| 平台 | 场景 | 能否被设备唤醒完成任务 |
|------|------|----------------------|
| **Android** | 划掉后台（从最近任务移除） | ✅ 可以。`agents_server` 为 **ForegroundService**，进程存活、BLE 常连，唤醒→对话→办事全程完成（编译需 JDK21）。 |
| **Android** | 设置里「强行停止」/ 部分厂商激进清理 | ⚠️ 进程被系统杀死、前台服务同亡 → 唤醒失效，需用户重开。**系统级限制**：只能靠引导用户「忽略电池优化 + 加自启白名单」降低概率。 |
| **iOS** | 上划回主屏 / 锁屏 / 切后台 | ✅ 只是**挂起**，App 仍在（"看着像关了其实只是隐藏"）。`bluetooth-central` + 后台音频保活，BLE 事件在后台照常处理。 |
| **iOS** | App 切换器里上划划掉那张卡 | 🟡 **大概率可以**。苹果文档上算"用户强退"，但实测并非硬杀：有**活跃 BLE 连接 + 后台音频会话 + CoreBluetooth 状态恢复**（`CBCentralManager(restoreIdentifier:)` → `willRestoreState`）时，BLE 事件常能把进程**在后台重新拉起**处理。须真机验证（对应现有排查 project_ios_background）。 |
| **iOS** | 真正难恢复 | ⚠️ 设备重启后未解锁 / 用户在系统里关蓝牙 / 未开 restoration 且被极端回收。此类无解，降级为下次打开恢复。 |

**设计约束（据此定型）**：
- 设备唤醒的**全链路只依赖框架层**（agents_server + 设备框架 + STT/LLM/TTS + local_db），**不得依赖 Flutter 存活**。
- 高风险动作（发邮件/支付）在无 UI 唤醒场景下，走**语音确认**或**降级为"待确认"入库**，下次用户在场再确认（§8）。
- iOS：切后台/上划回主屏只是**挂起**（App 仍在，音频/BLE 照跑）；App 切换器上划划掉大概率也能靠**状态恢复**被 BLE 事件拉起；只有"真正强退 / 关蓝牙 / 设备重启未解锁"才无解并降级。**必须开启 CoreBluetooth 状态恢复 + 后台音频**，并真机验证。
- Android 前台服务是可靠主路径；两端都把"设备唤醒全链路"设计为**框架层自洽**，UI 缺席不影响完成。

---

## 8. 确认 / 上报协议（安全闸口）

高风险动作（发邮件/支付/删除/外发）**专员不得自动执行**，必须经管家向用户确认。

```
专员 handle(task)：拟好动作，风险=high
  └─ emit AgentNeedConfirm(ConfirmRequest{actionKind, summary, preview, editable})
       └─ 管家 → onConfirmRequest(ConfirmRequestDto) → 用户在聊天里看到确认卡
            ├─ 用户批准(可编辑) → ManagerApi.respondConfirm(id, true, edited)
            │     └─ 管家 → 专员 continue(confirmId, approved, edited) → 执行 → AgentResult(ok)
            └─ 用户拒绝 → respondConfirm(id, false) → 专员 AgentResult(rejected)
```

专员补充接口：

```dart
abstract class ConfirmableAgent {
  Stream<AgentEvent> continueAfterConfirm(ConfirmId id, bool approved, {Map<String,dynamic>? edited});
}
```

---

## 9. 时序示例

### 9.1 单点分派（回邮件）
```
用户 → ManagerApi.sendUserMessage("帮我回复张总，说同意")
Manager: route→agent.email, dispatch(TaskEnvelope{intent:reply_email, needConfirm:true})
agent.email: onAssistantChunk?…→ AgentNeedConfirm(draft)
Manager → onConfirmRequest(草稿预览)
用户 → respondConfirm(true)
agent.email.continue → 发送 → AgentResult(ok)
Manager → onAssistantMessage("已发送给张总 ✓")
```

### 9.2 多专员协同（订会议 + 发通知）
```
用户 → "订明天15点和张总的会，并邮件通知他"
Manager.planner.decompose → 两个子任务(同 requestId)：
   T1 to=agent.schedule intent=create_event
   T2 to=agent.email    intent=send_email needConfirm=true
bus.dispatchAll([T1,T2])
   agent.schedule → AgentResult(ok, 事件已建)          → onAgentActivity(schedule,"已建会议")
   agent.email    → AgentNeedConfirm(通知邮件草稿)       → onConfirmRequest
用户 → respondConfirm(true) → agent.email 发送 → AgentResult(ok)
Manager.aggregate → onAssistantMessage("会议已排明天15:00，通知邮件已发给张总 ✓")
```

### 9.3 自治推送（每日资讯）
```
08:00 Scheduler 触发 subscription:news_daily
agent.news.onTrigger → 搜集+摘要 → AgentResult(status:ok, data:{items:[…]})
Manager 按 template="news" 包装 → onPush(PushMessageDto{agentId:agent.news, actions:[展开,追问]})
→ 首页聊天出现"今日资讯"推送卡；同时写 records
```

### 9.4 打断
```
用户 → cancel(requestId)
Manager → 对该 requestId 所有在途子任务 specialist.cancel(taskId)
→ onError? 否；onAssistantMessage(已停止) 或静默
```

---

## 10. 平台实现与现有资产纳管

| 平台 | 管家 + 专员运行处 | 边界①实现 |
|------|------------------|-----------|
| Android | `agents_server` 前台服务（Kotlin 内进程） | Pigeon MethodChannel/EventChannel |
| iOS | `agents_server`（Swift，后台音频/BGTask） | Pigeon |
| Web / 桌面 | `agents_server` 的 Dart 运行时 | 直接 Dart 调用（条件导入，复用现有跨端方案） |

- **现有 agent 纳管（包装，不改写）**：`agent_chat / agent_sts_chat / agent_translate / agent_ast_translate` **保持现有基础模板不动**，各配一个 `SpecialistAdapter` + `AgentCapability` 即被管家纳管；对用户的发声改为经管家统一（底层 agent 接口原样保留）。
- **翻译等现有 agent** 继续跑在原基础模板上，随时可被管家调用，也可继续独立直连使用（二者并存）。
- **硬件配合的 agent（后续）**：BLE/设备类 agent 同样先用**现有基础模板**实现自己的管线（复用 `device_manager`/JieLi 等），再套 `SpecialistAdapter` 纳入团队——协议不对硬件链路做任何侵入。
- **service_manager** 作为专员取用 Provider 的池子不变；**MCP** 作为专员工具来源不变。
- **local_db** 承载共享黑板/记忆/records/tasks（订阅），见 [UniHelper-app-design.md](UniHelper-app-design.md) §9。

---

## 11. 版本与扩展

- `AgentCapability.protocolVersion` 做兼容校验；管家拒绝不兼容专员并降级。
- 新增专员 = 实现 `SpecialistAgent` + 注册 `AgentCapability` + （可选）声明 `TriggerSpec`，**无需改管家代码**（能力驱动路由）。
- 事件/DTO 均为可加字段的开放结构；`data`/`params`/`preview` 用 map 承载领域专有内容，避免频繁改 Pigeon 定义。

---

## 12. 待定 / 评审问题

1. 路由器：规则表 + 轻模型分类 的**边界与回退**策略（何时上强模型规划）。
2. 多专员协同的**任务图**表达（串/并/依赖）是否需要显式 DSL，还是由 planner LLM 产出。
3. 共享黑板的**一致性**：request 内快照 vs 实时读写；跨 request 的记忆写入时机。
4. 专员**再委派**（AgentDelegate）是否开放（默认仅管家可分派，避免环路）。
5. Pigeon 结构 vs 纯 JSON 通道：`data` 类字段是否统一走 JSON 字符串以减少 Pigeon 变更。
