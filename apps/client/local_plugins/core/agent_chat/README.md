# agent_chat — 对话内核

`local_plugins/core/agent_chat` · 纯 Dart · 建在 agent_kernel 上

管家路由的**兜底对话专员（id=`chat`）**，也是四大支柱里 **①强化对话** 的核心。
`RuleRouter` 未命中任何专项服务时 `fallback = 'chat'`——此前这个 id 没有对应专员、
兜底落空洞；本包把它补上：真正能多轮聊天、记得上文、带知识库上下文的对话。

## 结构

```
ChatAgent (SpecialistAgent, id=chat)
每轮 handle(task):
  载入会话(sessionId = params.sessionId ?? userId ?? 'default')
  拼装消息 = [system 人设]
           + [system: task.context 知识库/记忆]   ← 管家注入
           + 历史窗口(最近 windowTurns 轮)
           + [user 本轮]
  → LlmProvider.stream() 流式产出 → 每片 AgentPartial → 收尾 AgentResult
  → 本轮一问一答落库(SessionStore)，供下轮记忆

LlmProvider   端口：真模型(火山/OpenAI/本地)实现后注入；默认 EchoLlm / ScriptedLlm 可测
SessionStore  端口：默认 InMemorySessionStore；移动端注入 local_db → 后台/杀app 可读
```

## 已验证（`dart run example/self_check.dart`，全绿）

流式分片 · 多轮记忆 · 知识库上下文注入 · 记忆窗口裁剪 · 会话隔离 ·
**管家兜底闭环**（未命中专项 → 路由 chat → 真回复）。

## 接线

- 注册进 `Manager`：`mgr.register(ChatAgent(llm: <真LLM>))`，即补齐 `RuleRouter` 的 `fallback`。
- 知识库经管家 `ContextProvider.contextFor` 取到的上下文，会作为 `task.context` 注入本对话。
- `sessionId` 可用 `desktop_pet` / 设备唤醒会话等隔离多路对话。
