# UniHelper 产品与架构设计

**项目名称**：UniHelper（原 AI Agent Client）
**文档定位**：UniHelper 全能 AI 助手的总纲设计（愿景 → 定位 → 能力四支柱 → 产品形态 → 信息架构 → 架构演进 → 数据模型 → 路线图 → 更名方案）
**版本**：v1.0
**日期**：2026-06-30
**状态**：方案稿（本文为后续 PRD.md / architecture.md 演进的上位依据）

> 本文是一次**定位升级**：把现有"面向开发者的多厂商 AI 能力测试/集成平台"，正式重塑为"**面向用户的随身全能 AI 助手 UniHelper**"。现有的原生 Agent 执行引擎、MCP、多厂商插件体系、本地数据库、悬浮助理与系统麦克风链路，都是这次升级的**地基而非推倒重来**。

---

## 1. 愿景与定位

### 1.1 一句话定位

> **UniHelper —— 一个常驻随身、能听会说、能看能查能办事的个人 AI 助手。**

不是"让用户去配置 Agent 的工具箱"，而是"一个随叫随到、自己会判断该用什么能力的助手"。用户表达需求，助手自动编排底层能力（对话 / 翻译 / 看图 / 查文档 / 办事），而不是让用户先选"我要打开翻译 Agent"。

### 1.2 定位迁移

| 维度 | 旧：AI Agent Client | 新：UniHelper |
|------|--------------------|---------------|
| 目标用户 | AI 应用开发者、技术评估者 | 普通用户（消费端） |
| 核心隐喻 | 多厂商能力测试台 / 脚手架 | 随身全能助手 |
| 交互范式 | 先建 Agent → 选 Agent → 运行 | 直接说需求 → 助手自动路由编排 |
| 首屏 | Agent 列表 / 服务库 | 悬浮助理唤起 + 助手对话工作台 |
| 服务配置 | 一等公民（Services Tab） | 下沉为高级设置（预置默认、零配置可用） |
| 能力边界 | 对话 / 翻译 / STS / 同传 | 上述 + 任务自动化 + 知识库 + 多模态 |
| 扩展对象 | 开发者按接口接入 Provider/Agent | 用户安装/启用"技能(Skill)"与 MCP |

### 1.3 设计原则（继承 + 新增）

> **0. 服务为骨（最高架构原则）**：UniHelper 的核心是**服务层**，不是 Flutter。
> - **底座 = 框架 + 业务服务**：底层再分两层——**框架层**（稳定、可扩展的内核：Agent 基础模板 / `agents_server` 宿主 / `service_manager` / 设备框架 / `local_db` / MCP / **服务级唤醒总线**）+ **业务服务层**（建在框架上的一个个服务，**翻译助手、对话、日程、邮件… 每个都是一个业务服务**）。
> - **Flutter = 大楼**：负责业务管理与分类、定制、UI/交互逻辑，**不承担核心执行**。
> - **服务级唤醒是核心能力**：设备事件 / 唤醒词 / 定时 / 来电可**直接在服务层唤起业务服务并完成任务**（如"连上设备后唤醒服务加日程"），Flutter 不在场也照常完成。
> 详见 §5.0 与 [UniHelper-agents-protocol.md](UniHelper-agents-protocol.md)（服务级唤醒协议）。

**继承现有架构的硬核原则**：

1. **执行引擎在原生层、后台可独立运行**：Agent 管线（VAD→STT→LLM→TTS、状态机、会话）跑在原生 Service，Flutter 退后台/被回收也不中断。这是"随身助手"的命门，必须保留。
2. **Provider 可热切换、接口化**：STT/TTS/LLM/翻译统一接口，运行时换厂商不改业务代码。
3. **隐私本地优先**：密钥、会话、知识库、记忆默认存本地（`local_db` + 加密），不强制上云。

**为消费化新增的原则**：

4. **零配置可用**：预置一套可直接用的默认服务/技能，新用户无需填 API Key 即可开始（厂商密钥可由 `configcenter` 下发或内置体验额度）。
5. **随身唤起优先**：悬浮助理 / 全局快捷键 / 系统级唤起是第一入口，App 主体是配置与记忆中心。
6. **统一会话 + 统一记忆**：一条连续对话流贯穿所有能力；跨会话的长期记忆（偏好、事实、画像）喂回助手。
7. **意图自动路由**：用户不选能力，助手判断该用哪个技能并自行编排。

---

## 2. 目标用户与核心场景

### 2.1 用户画像（消费端）

- **效率人群 / 知识工作者**：随手提问、整理资料、自动办事。
- **跨语言 / 出海用户**：实时对话翻译、同传、文档翻译。
- **学生 / 研究者**：拍照/截屏问题、文档问答、知识库沉淀。
- **轻办公用户**：让助手设提醒、查日历、发消息、跨应用自动化。

### 2.2 核心场景 → 能力支柱映射

| 场景 | 体验 | 支柱 |
|------|------|------|
| 随时问答 | 点悬浮球，说一句话，连续语音/文字对话，可打断 | ① 对话+语音 |
| 实时翻译 | 通话/同传模式逐句翻译朗读，后台保活 | ① 翻译 |
| 拍照/截屏问它 | 拍张照或截个屏，问"这是什么/怎么解" | ④ 多模态 |
| 让它画 | "画一张……"，文生图返回 | ④ 多模态 |
| 喂文档问它 | 导入 PDF/网页/笔记，基于内容问答、总结 | ③ 知识库 |
| 让它办事 | "明早八点提醒我开会"、"把这段发给老王" | ② 任务自动化 |
| 它记得我 | 记住偏好/称呼/常用信息，跨会话延续 | ② 编排 + 长期记忆 |

---

## 3. 产品形态与信息架构（悬浮助理为主）

### 3.1 双形态：悬浮助理（主入口） + App 主体（配置与记忆中心）

**形态 A —— 悬浮助理（核心入口，复用并升级现有 `desktop_pet` + 系统麦克风链路）**

```
┌─────────────────────────────────────────┐
│   桌面 / 任意应用之上                      │
│                                           │
│                         ╭───────╮         │
│                         │  🟣   │ ← 常驻悬浮球/桌宠（可拖动）
│                         ╰───┬───╯         │
│         单击 → 直接发起语音对话(系统麦克风)   │
│         长按 → 进入 App 主体               │
│         状态：待命 / 监听 / 思考 / 播报      │
└─────────────────────────────────────────┘
```

- **唤起方式**：悬浮球单击（直接语音对话，沿用 `sessionId=desktop_pet` 链路）；全局快捷键 / 手势；Android 快捷开关；桌面端系统热键。
- **状态可视化**：复用 `agent_runtime` 的状态机事件（LISTENING/思考/PLAYING）驱动悬浮球动效。
- **轻交互卡片**：悬浮态可弹出极简对话气泡/结果卡，不必每次进 App。

**形态 B —— App 主体（标准助手 App，配置 + 记录 + 知识中心）**

消费端信息架构重构（从开发者式的 Agents/Services/Settings 三 Tab → 标准助手式四 Tab）：

```
UniHelper App（底部导航）
├── 🏠 首页        助理工作台：今日概览 feed + 助手入口 + 全局唤起 [默认 Tab]
├── 💬 对话        统一会话（被动技能自动路由）
├── 📋 动态        日程·订阅·任务·记录 综合管理中心（过去/现在/未来）
└── 👤 我的        设置中枢：助手管理 / 服务库 / Agent / 知识库 / 通用设置(二级页)
```

> 关键变化：**首页 = 助理工作台**（不再是 Agent 列表）；**服务库与 Agent 列表下沉到"我的"设置中枢**——消费端用户不应一上来面对 Provider/密钥；新增**"动态"综合管理中心**承载日程/订阅/任务/记录。
>
> 助手分两类：**被动式（对话技能：对话/翻译/看图/文档/画图，用户发起）** 与 **主动式（电话/咨询/日程/邮件/财务，定时或事件触发、后台运行、产出记录与推送）**。
>
> 📐 **完整界面与各助手详设见 [UniHelper-app-design.md](UniHelper-app-design.md)**（信息架构、首页工作台、综合管理中心、设置中枢、5 个主动助手、调度/触发引擎、数据模型增量）。

### 3.2 统一会话：从"选 Agent"到"说需求"

旧模型让用户显式创建并挑选 Agent（chat-agent / translate-agent…）。新模型用**一个统一助手 + 意图路由**取代：

```
用户输入（文字/语音/图片/文件）
        │
        ▼
  ┌───────────────────────────┐
  │  Orchestrator（意图路由+规划） │  ← 新增层
  └───────────────────────────┘
        │ 判定意图，编排技能
        ├── 闲聊/问答  → Chat 技能（现有 chat 管线）
        ├── 翻译/同传  → Translate / AST 技能（现有）
        ├── 看图/截屏  → Vision 技能（新增 VLM）
        ├── 文档问答   → Knowledge/RAG 技能（新增）
        ├── 办事/多步  → Task 技能（MCP 工具 + 规划）
        └── 画图       → ImageGen 技能（新增）
```

"技能"是比"Agent"更高层的可复用单元：一个技能封装"何时触发 + 用哪些 Provider + 调哪些工具 + 如何呈现"。现有四类 Agent 自然成为内置技能。

---

## 4. 能力四支柱（详细设计）

### 支柱 ① 强化现有对话 + 语音 + 翻译

**地基**：现有 `agent_runtime`（原生执行引擎、状态机、VAD、后台保活）+ chat / sts / translate / ast 四管线 + 多模态输入栏。

**强化点**：
- 统一多模态输入栏支持**文字 + 图片 + 文件附件**（为支柱③④铺路），不再只是文字/语音切换。
- 随身通话模式后台保活打磨（Android 前台服务 / iOS 后台音频），打断与"最新优先"抢占已就绪。
- 流式全链路（思考流 / TTFT / 字边界高亮）已在 `AgentRuntimeEventApi` 定义，继续打磨为主线体验。
- 翻译/同传作为"技能"接入统一会话，可在对话中随口切换"翻译一下这段"。

### 支柱 ② 任务自动化 / Agent 编排

**地基**：现有 MCP（本地工具 `LocalMcpRegistry` + 远程 `RemoteMcpRegistry`）+ `llm_openai` 内置工具调用 + `agent_runtime` 的 ToolCall 事件流。

**新增**：
- **Orchestrator（意图路由 + 多步规划）**：识别意图、拆解多步任务、调度工具、汇总结果。MVP 可"规则前置 + LLM 兜底"，后续升级为 LLM 规划器。
- **Skill 抽象**：技能 = 触发条件 + 所需 Provider + 工具集 + 呈现模板。内置技能 + 用户可启用的 MCP 技能。
- **系统能力工具集**（扩展本地 MCP 工具）：提醒/闹钟、日历读写、联系人、发短信（已有 `send-sms` 函数）、文件、定位、剪贴板；桌面端可接系统自动化（AppleScript / Shortcuts / 命令）。
- **长期记忆工具**：读写用户画像与事实记忆（见 §5.5）。

### 支柱 ③ 知识库 / 文档问答（RAG）

> 📐 **本地用户级知识库完整方案见 [UniHelper-knowledge.md](UniHelper-knowledge.md)**（本地优先/用户级/作为业务服务/团队共享/存储与嵌入选型/唤醒集成/分期）。

**全新子系统**：

```
文档导入（PDF / Word / 网页 / 图片OCR / 笔记）
   └─ 解析 + 切块（chunking）
        └─ 嵌入（Embedding Provider，新增接口）
             └─ 本地向量存储（local_db 扩展 / 独立 vector 插件）
                  └─ 检索（向量 + 关键词混合）
                       └─ 注入上下文 → LLM 生成（带引用溯源）
```

**新增组件**：
- `EmbeddingProvider` 接口 + 厂商实现（OpenAI / 阿里 / 豆包 / 本地 BGE）。
- 向量存储：优先扩展 `local_db`（SQLite + 向量扩展 / 余弦近邻），或独立 `vector_store` 插件。
- 文档解析管线（各端）：PDF/网页提取、图片 OCR（系统/厂商 OCR）。
- RAG 技能：检索 → 重排 → 带引用回答。

### 支柱 ④ 多模态（图像 / 视觉 / 屏幕理解）

**新增能力族**：
- **视觉理解（VLM）**：拍照/选图/截屏 → 问答。新增 `VisionProvider`（Claude / GPT-4o / Gemini / Qwen-VL / 豆包 Vision）。
- **屏幕理解**：截屏采集（各端实现）→ OCR + VLM，桌面端尤其强（"这个报错怎么解"）。
- **图像生成**：文生图。新增 `ImageGenProvider`（即梦/豆包、通义万相、DALL·E/GPT-image、SD）。
- **多模态消息**：消息体支持图片/文件附件（数据模型新增 `attachments`），输入栏支持附件。

---

## 5. 架构演进

### 5.0 分层骨架：服务为骨（框架 + 业务服务），Flutter 为大楼

UniHelper 的骨架是**服务层**。底座内部再分「框架」与「业务服务」两层；Flutter 是建在底座之上的"大楼"，做业务管理与定制，不承担核心执行。

```
🏢 大楼 —— Flutter（业务管理 / 分类 / 定制 / UI·交互逻辑）
        · 首页聊天 · 订阅 · 生活 · 我的
        · 只做"管理与展示"，服务层能力即使 Flutter 不在也能跑
        ▲  Pigeon 命令↓ / 事件↑（Web/桌面走 Dart 直调）
════════╪══════════════════ 底座（服务层，稳 + 可扩展）═══════════
        │
🧱 业务服务层 Business Services —— 建在框架上的一个个"服务"
        · 翻译服务 · 对话服务 · STS · 同传
        · 日程服务 · 邮件服务 · 咨询服务 · 财务 · 健康
        · 每个业务服务 = 框架契约的一个实现 + 领域逻辑 + 可被唤醒
        ▲  实现框架契约 / 被框架调度与唤醒
────────┼──────────────────────────────────────────────────────
🏗️ 框架层 Framework —— 稳定、可扩展的内核（尽量少改）
        · Agent 基础模板（NativeAgent 契约，所有服务的共同底座）
        · agents_server 宿主：Manager（管家）· AgentBus · Scheduler
        · ★ 服务级唤醒总线 Wake Bus（设备/唤醒词/定时/来电 → 直唤业务服务）
        · service_manager（Provider 池）· 设备框架（BLE/JieLi）
        · local_db（记忆/记录/订阅）· MCP 运行时
```

**三条铁律**：
1. **框架稳、业务活**：框架层是稳定内核，尽量少改、对上提供契约；业务服务在框架上快速增删（翻译/日程/邮件… 各是一个业务服务），互不影响。
2. **Flutter 不持有核心逻辑**：对话、编排、办事、唤醒都在服务层完成；Flutter 只管理与呈现。这样后台/悬浮/设备/无 UI 场景都能独立工作。
3. **服务级唤醒（Wake）是一等能力**：见 §5.0.1。

#### 5.0.1 服务级唤醒（Wake）

核心对话与办事能力必须能被**服务层直接唤起并完成**，无需 Flutter 在前台：

```
唤醒源（框架 Wake Bus 统一接入）
  · 设备事件（连上耳机/吊坠、按键、设备端唤醒词）
  · 语音唤醒词（"你好 UniHelper"）
  · 定时/事件（订阅到点、来电、地理围栏）
        │
        ▼
  Wake Bus → 唤起管家(Manager) 或 直唤某业务服务
        │
        ▼
  业务服务在服务层直接完成（例：加日程 / 起草邮件 / 开始通话翻译）
        │
        ├─ 结果落 local_db（记录/日程/…）+ 系统通知/TTS 播报
        └─ Flutter 在场则更新 UI；不在场也已完成
```

> 例：用户连上耳机后说"帮我加个明早十点的会" → 设备唤醒 → Wake Bus → 日程业务服务在服务层建好日程并 TTS 确认，**全程不需要打开 App**。

**硬要求：连上设备后即使 App 被杀，设备唤醒也要能完成对话与办事。** 音频链路（设备麦克风↔BLE↔STT/LLM/TTS↔设备扬声器）与整条管线全在 `agents_server` 原生持有，与 Flutter 进程死活无关；对话界面只是"活着就刷新、没活着也不影响完成"。存活性：**Android** 前台服务是可靠主路径（划掉后台仍在；「强行停止」是系统级限制）；**iOS** 靠 CoreBluetooth 状态恢复 + 后台音频，用户强退是已知风险点、须真机验证。详见 [UniHelper-agents-protocol.md](UniHelper-agents-protocol.md) §7.5.1。

### 5.1 演进后的分层架构

在现有"Flutter UI（纯展示）→ agent_runtime（原生执行引擎）→ local_plugins（能力插件）→ 外部服务"四层之上，**叠加**编排层、知识子系统与多模态 Provider 族，不改动既有分层契约：

```
┌──────────────────────────────────────────────────────────────┐
│  Flutter UI（纯展示层）                                          │
│  悬浮助理(desktop_pet++)  │  对话工作台  │  技能  │  知识  │  我的   │
└───────────────┬──────────────────────────────────────────────┘
                │ 命令(Pigeon) ↓ / 事件(EventChannel) ↑
┌───────────────▼──────────────────────────────────────────────┐
│  ★ Orchestrator（意图路由 + 规划 + 技能调度）  ← 新增            │
│     统一会话 │ 意图识别 │ 多步规划 │ 工具/技能编排 │ 长期记忆注入     │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│  agent_runtime（原生执行引擎，后台保活）                          │
│  VAD → STT → [工具/MCP] → LLM/VLM → TTS  状态机/会话              │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│  local_plugins（能力插件集，接口化、可热切换）                     │
│  现有: stt_* / tts_* / llm_* / sts_* / translation_*            │
│  新增: embedding_* / vision_*(VLM) / image_gen_* / ocr_*         │
│  扩展: 本地 MCP 工具集(提醒/日历/联系人/截屏/文件/记忆)             │
├───────────────────────────────────────────────────────────────┤
│  ★ Knowledge 子系统：文档解析 → 切块 → 嵌入 → 向量库 → 检索        │
│  local_db（扩展：documents/chunks/embeddings/attachments/        │
│            skills/memories/conversations）                       │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│  外部服务  +  后端(apps/services: console/app/configcenter)      │
│  configcenter 下发默认配置/体验额度，admin 后台运营技能与厂商       │
└──────────────────────────────────────────────────────────────┘
```

### 5.2 Orchestrator = 管家 Agent（多 Agent 团队）

Orchestrator 正式升级为 **管家 Manager Agent**：UniHelper 不是单个 agent，而是**"对外一个管家 + 对内一支专员团队"**。现状 `local_plugins/agents/` 已按能力拆成 `agent_chat/agent_sts_chat/agent_translate/agent_ast_translate` + `agents_server` 宿主——已是多 agent 基座；升级即在其上加管家层与协作协议（分派/协同/自治/上报）。

- **MVP**：管家先只做"路由"，包住现有 4 个专员；意图路由用"规则 + LLM 兜底"。
- **演进**：管家下沉进 `agents_server`（原生前台服务），支持多专员协同 + 后台自治 + 用户确认闸口，无 Flutter 也能跑。

> 📐 完整设计见 **[UniHelper-agents.md](UniHelper-agents.md)**（管家+专员模型、四种协作模式、A2A 协议、落地映射、权衡）。

### 5.3 Provider 接口族扩展

| 新接口 | 用途 | 候选厂商 |
|--------|------|----------|
| `EmbeddingProvider` | 文本向量化（RAG） | OpenAI text-embedding-3 / 阿里 / 豆包 / 本地 BGE |
| `VisionProvider`(VLM) | 图像/截屏理解 | Claude / GPT-4o / Gemini / Qwen-VL / 豆包 Vision |
| `ImageGenProvider` | 文生图 | 即梦·豆包 / 通义万相 / GPT-image / SD |
| `OcrProvider` | 图片转文字 | 系统 OCR / 百度 / 阿里 |

接入方式与现有一致：实现接口 → 注册到对应 Registry → 运行时按 `ServiceConfig` 工厂创建。`ServiceType` 枚举新增 `embedding / vision / imageGen / ocr`。

### 5.4 MCP / 工具扩展

在 `LocalMcpRegistry` 现有工具（UserInfo / DateTime / Calculator / DeviceInfo）基础上，新增**系统能力工具集**：`ReminderTool / CalendarTool / ContactsTool / SmsTool(对接 send-sms) / FileTool / ScreenshotTool / ClipboardTool / MemoryTool`。桌面端追加系统自动化工具（Shortcuts/AppleScript/命令）。远程 MCP 沿用现有 `McpServerConfig`。

### 5.5 长期记忆

新增 `memories` 表与 `MemoryTool`：
- 写入：助手在对话中识别"值得记住的事实/偏好"，调用 `MemoryTool` 落库。
- 读取：Orchestrator 在每轮对话前检索相关记忆，注入系统提示。
- 范畴：用户画像、偏好、长期事实、常用信息；与 `UserInfoProvider` 合并演进。

---

## 6. 数据模型增量

在现有 `service_configs / agents / messages / mcp_servers` 基础上新增/扩展：

```sql
-- 统一会话（泛化原 per-agent messages）
CREATE TABLE conversations (
  id TEXT PRIMARY KEY, title TEXT, created_at INTEGER, updated_at INTEGER
);
-- 消息扩展：归属会话、支持多模态附件、记录所用技能
ALTER TABLE messages ADD COLUMN conversation_id TEXT;   -- 关联 conversations
ALTER TABLE messages ADD COLUMN skill TEXT;             -- 本轮命中的技能
-- 多模态附件
CREATE TABLE attachments (
  id TEXT PRIMARY KEY, message_id TEXT, kind TEXT,       -- image|file|audio|screenshot
  uri TEXT, mime TEXT, meta_json TEXT, created_at INTEGER
);
-- 技能定义
CREATE TABLE skills (
  id TEXT PRIMARY KEY, name TEXT, kind TEXT,             -- builtin|mcp|custom
  enabled INTEGER, config_json TEXT, sort_order INTEGER
);
-- 知识库
CREATE TABLE documents (
  id TEXT PRIMARY KEY, title TEXT, source TEXT, mime TEXT,
  status TEXT, created_at INTEGER                        -- importing|ready|failed
);
CREATE TABLE doc_chunks (
  id TEXT PRIMARY KEY, document_id TEXT, ordinal INTEGER, text TEXT
);
CREATE TABLE embeddings (
  chunk_id TEXT PRIMARY KEY, dim INTEGER, vector BLOB, model TEXT
);
-- 长期记忆
CREATE TABLE memories (
  id TEXT PRIMARY KEY, scope TEXT, key TEXT, value TEXT,  -- profile|preference|fact
  weight REAL, updated_at INTEGER
);

-- service_configs.type 扩展取值：stt|tts|sts|llm|translation|embedding|vision|imageGen|ocr
```

---

## 7. 路线图（分期）

| 里程碑 | 内容 | 支柱 |
|--------|------|------|
| **M0 收口**（本次） | 更名 UniHelper + 本设计定稿 + 信息架构重构方案 | — |
| **M1 助手主线** | 统一会话 + 悬浮助理升级 + 意图路由(规则+LLM, MVP) + 多模态输入栏(附件) | ①② |
| **M2 多模态** | VisionProvider(拍照/截屏问答) + ImageGenProvider(文生图) + 附件数据模型 | ④ |
| **M3 知识库** | 文档导入/解析 + EmbeddingProvider + 本地向量库 + RAG 技能(带引用) | ③ |
| **M4 任务自动化** | 系统能力工具集 + Skill 编排 + 多步规划器升级 | ② |
| **M5 记忆与同步** | 长期记忆 + 跨端同步(可选, 走后端) | ② |

每个里程碑都建立在现有 `agent_runtime` / `local_plugins` / `local_db` / MCP 之上，**增量叠加，不推翻地基**。

---

## 8. 更名方案（AI Agent Client → UniHelper）

### 8.1 命名体系

| 维度 | 取值 |
|------|------|
| 产品名（展示） | **UniHelper** |
| 标识符（包/目录） | `unihelper` |
| Bundle/包名建议 | `com.<org>.unihelper`（沿用现有组织前缀，避免改签名/上架标识时再动） |
| 应用显示名 | UniHelper |
| 文档/README 标题 | UniHelper |

### 8.2 分两档执行（避开当前工作树的迁移中途状态）

> 当前工作树正处于 `apps/flutter_client → apps/client` 迁移中途（git 有大量未提交的路径变更）。**深层标识符更名应在该重构提交后再做**，避免与未提交变更纠缠。

**第一档 · 现在就做（低风险、改了即生效）**：
- README.md、docs/*.md、design/*.html 中的 "AI Agent Client" 文案 → UniHelper。
- 应用**显示名**（用户可见）：Android `android:label`、iOS `CFBundleDisplayName`、macOS/Windows 应用名 → UniHelper。
- 本设计文档（已用 UniHelper 命名）。

**第二档 · 现有重构提交后再做（牵动代码/构建，需谨慎）**：
- Dart workspace 名 `ai_agent_sdk_workspace` / melos `name`（按需）。
- iOS/Android/桌面 **Bundle Identifier / applicationId**（改动影响签名、推送、上架标识，需评估，建议保留现有 ID 仅改显示名）。
- Admin 前端 `package.json` name（`ai-agent-admin`）与可见标题。
- Go 后端 module 名为 `yunyan`（与 ai_agent 无关，**无需改**）。

**第三档 · 用户在终端执行（会改变工作目录与远端，工具内不便操作）**：
```bash
# 物理目录改名（先关闭占用，再改）
mv /Users/liwei/work/flutter/ai-agent-client /Users/liwei/work/flutter/UniHelper
# git 远端改名（在 GitHub 改仓库名后）
git remote set-url origin https://github.com/liwei1dao/UniHelper.git
```

---

## 9. 与现有文档的关系

- 本文为 UniHelper 的**上位总纲**。`docs/PRD.md`、`docs/architecture.md` 后续按本文方向分模块演进（标题已更名为 UniHelper）。
- 现有架构契约（`AgentRuntimeApi` 事件体系、`local_db` 表结构、Provider Registry、MCP 模型）继续有效，本文新增内容均为**向后兼容的叠加**。
