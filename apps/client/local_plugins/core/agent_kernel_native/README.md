# agent_kernel_native — 多 Agent 团队编排内核（Kotlin / Swift）

`local_plugins/core/agent_kernel_native` · Flutter 插件（Android Kotlin ✅ / iOS Swift ✅）

移动端 `agents_server`（纯原生）**直接使用**的管家编排内核——逻辑忠实镜像已跑绿的纯 Dart 包
[`agent_kernel`](../agent_kernel/)（算法规范 + web/桌面运行时）。

## 谁调它

```
移动端 agents_server（纯原生 Kotlin/Swift）
  ├─ Manager(RuleRouter(), contextProvider = 知识库)          // 单一发声
  ├─ register(chatAdapter / translateAdapter / scheduleSvc)   // 现有/新专员
  ├─ manager.handle(userText, userId)  → ManagerReply         // 路由→分派→汇总
  └─ wakeBus.on { manager.onWake(it) }                        // 服务级唤醒(无 UI 也走通)
web / 桌面：用纯 Dart 包 agent_kernel（同 API）
```

## 结构

```
android/src/main/kotlin/ai/unihelper/agentkernel/
├── AgentKernel.kt        模型 + AgentEvent(sealed) + 端口(SpecialistAgent/ContextProvider/Router)
│                         + RuleRouter + Manager + WakeBus
└── AgentKernelPlugin.kt  占位 FlutterPlugin（内核由原生直调，无需通道）
android/src/test/kotlin/… ManagerTest.kt   端到端单测（镜像 Dart 自检）
ios/Classes/AgentKernel.swift · AgentKernelPlugin.swift · agent_kernel_native.podspec
```

## 接现有 agent（SpecialistAdapter + LegacyAgentRunner）

`SpecialistAdapter` 把现有 agent 包成专员（流式 chunk→汇总、工具→进度、错误、确认），**不改基础模板**。你只需用现有 agent 的既有接口实现 `LegacyAgentRunner`（方法名以你真实 NativeAgent 为准）：

```kotlin
// 把 agent_chat 包成 runner（下列 startSession/sendText/onLlmChunk/onLlmDone 为占位，替换成你真实签名）
class ChatRunner(private val chat: /*你的*/ NativeChatAgent) : LegacyAgentRunner {
    override fun run(text: String, context: String?, userId: String?): List<RunnerEvent> {
        val events = ArrayList<RunnerEvent>()
        val sid = chat.startSession(systemPrompt = context)          // 复用既有会话
        chat.sendTextBlocking(sid, text,                             // 或订阅回调收集
            onChunk = { events.add(RunnerEvent.chunk(it)) },
            onDone  = { events.add(RunnerEvent.done()) },
            onError = { c, m -> events.add(RunnerEvent.error(c, m)) })
        return events
    }
}
// 注册：
manager.register(SpecialistAdapter(AgentCapability("chat","对话", listOf("聊","你好")), ChatRunner(chat)))
manager.register(SpecialistAdapter(AgentCapability("translate","翻译", listOf("翻译")), TranslateRunner(tr)))
```
> 骨架用同步 List；真实流式改成回调/Flow 累积再返回，或让 adapter 支持 Flow（后续）。翻译 agent 同理（结果作一个 chunk+done，或直接 done(译文)）。
- **知识库**：`KnowledgeBusinessService.contextFor` → 实现 `ContextProvider`（管家主动注入）；`kb.search` 作专员/工具。
- **主动式服务**（日程/邮件/资讯/财务/健康）：各实现 `SpecialistAgent` + `onTrigger`，调度/唤醒驱动。
- 骨架用同步 `List<AgentEvent>`；需要流式再换 Flow(Kotlin)/回调或 Combine(Swift)。

## ⚠️ 验证状态

Kotlin/Swift 逐行对照**已 `dart run` 跑绿**的 Dart `agent_kernel` 移植；本检出无 Android/Xcode 工具链，**未编译验证**。请在真实环境跑 `./gradlew :agent_kernel_native:test`（`ManagerTest`，覆盖 路由/确认闸口/上下文注入/唤醒），iOS 用 XCTest 按同用例。Kotlin 包名 `ai.unihelper.agentkernel` 为占位，对齐真实 applicationId。
