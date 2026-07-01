# UniHelper

> 一个常驻随身、能听会说、能看能查能办事的全能 AI 助手。

UniHelper（原 AI Agent Client）是一个面向用户的随身 AI 助手：以悬浮助理为核心入口，用户直接表达需求，助手自动路由并编排底层能力——对话、语音、翻译、看图、文档问答、办事自动化。

## 能力四支柱

1. **对话 + 语音 + 翻译**：原生执行引擎后台保活，文字/语音/通话/同传，流式与打断。
2. **任务自动化 / Agent 编排**：意图路由 + 多步规划 + MCP 工具调用，"帮我做事"而不仅是聊天。
3. **知识库 / 文档问答**：导入文档 → 嵌入 → 本地向量库 → RAG 检索（带引用）。
4. **多模态**：拍照/截屏视觉理解、文生图。

## 工程总览

```
apps/
├── client/     Flutter 客户端（iOS / Android / Web / macOS / Windows + 悬浮助理）
├── admin/      管理后台（React + Vite + AntD）
├── services/   后端服务（Go：console / app / configcenter）
└── proto/      接口定义

local_plugins/  能力插件集（stt_* / tts_* / llm_* / sts_* / translation_* …，melos 管理）
docs/           设计文档（见下）
```

## 设计文档

- [docs/UniHelper.md](docs/UniHelper.md) —— **产品与架构总纲**（定位 / 能力四支柱 / 形态 / 信息架构 / 架构演进 / 数据模型 / 路线图 / 更名方案）
- [docs/UniHelper-app-design.md](docs/UniHelper-app-design.md) —— **App 界面与信息架构详设**（4-Tab：首页聊天/订阅/生活/我的、5 个主动助手、调度引擎）
- [docs/UniHelper-agents.md](docs/UniHelper-agents.md) —— **多 Agent 团队协作架构**（对外一个管家 + 对内专员团队、四种协作模式、A2A 协议）
- [docs/UniHelper-agents-protocol.md](docs/UniHelper-agents-protocol.md) —— **多 Agent 接口协议草案**（专员注册/任务信封/A2A 事件/Pigeon API/调度·确认·唤醒协议/时序）
- [docs/UniHelper-knowledge.md](docs/UniHelper-knowledge.md) —— **本地用户级知识库方案**（本地优先 RAG、存储/嵌入选型、团队共享、唤醒集成）
- [design/client2.0/index.html](design/client2.0/index.html) —— App 界面效果图（可浏览器打开预览）
- [docs/PRD.md](docs/PRD.md) —— 产品需求
- [docs/architecture.md](docs/architecture.md) —— 架构设计
- [docs/api-spec.md](docs/api-spec.md) · [docs/sdk-usage.md](docs/sdk-usage.md) · [docs/native-plugin.md](docs/native-plugin.md) · [docs/dev-guide.md](docs/dev-guide.md)
