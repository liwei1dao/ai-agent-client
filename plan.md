# AI Agent Client — 实现计划

**参考文档**：`docs/architecture.md` (v1.8)
**项目根目录**：`./app/`（Flutter 工程全部在此，repo 根目录只放文档和配置）

---

## 目录结构规范

```
ai-agent-client/          ← repo 根目录
├── app/                  ← Flutter 工程（所有代码在此）
│   ├── pubspec.yaml
│   ├── lib/              ← Flutter Dart 层（纯 UI + 薄桥接）
│   ├── android/          ← Android 原生壳
│   ├── ios/              ← iOS 原生壳
│   └── local_plugins/    ← 本地插件集
│       ├── ai_plugin_interface/   # 共享抽象接口
│       ├── agent_runtime/         # ★ Agent 执行引擎（核心）
│       ├── local_db/              # 本地数据库
│       ├── stt_azure/             # Azure STT（参考实现）
│       ├── tts_azure/             # Azure TTS（参考实现）
│       ├── llm_openai/            # LLM（OpenAI compatible + MCP）
│       ├── sts_volcengine/            # 端到端语音
│       ├── translation_deepl/     # DeepL 翻译
│       └── translation_aliyun/    # 阿里云翻译
├── docs/
│   ├── architecture.md
│   └── ui/index.html
├── plan.md               ← 本文件
└── task.md               ← 任务清单
```

---

## Phase 1 — 项目基础骨架

**目标**：建立 Flutter 工程骨架，所有依赖声明，开发环境可运行。

### 1.1 Flutter 工程初始化
- `flutter create --org com.example --platforms android,ios app` 在 `./app` 创建工程
- 调整 `pubspec.yaml`：添加所有第三方依赖（riverpod、go_router、pigeon、flutter_dotenv 等）
- 配置 `analysis_options.yaml`、`.env.example`

### 1.2 目录结构
按 `docs/architecture.md §2` 建立 `lib/` 下完整目录骨架：
- `core/`（config、errors、utils）
- `registry/`（service_library、各插件注册）
- `agents/`（agent_config 数据模型）
- `runtime/`（Flutter 侧桥接薄层）
- `models/`（message、stt_result 等）
- `features/`（agents、chat_agent、translate_agent、services、settings）
- `shared/`（widgets、themes）

### 1.3 local_plugins 基础 pubspec
为每个插件创建 `pubspec.yaml`，主工程 `pubspec.yaml` 通过 `path` 引用所有本地插件。

---

## Phase 2 — ai_plugin_interface（共享抽象层）

**目标**：定义所有 STT/TTS/LLM/Translation/STS 插件必须实现的 Dart 抽象接口和 Pigeon 消息类型。

### 内容
- `SttPlugin` 抽象类（startListening、stopListening、dispose）
- `TtsPlugin` 抽象类（synthesize、play、stop、dispose）
- `LlmPlugin` 抽象类（chat stream、cancel）
- `TranslationPlugin` 抽象类（translate）
- `StsPlugin` 抽象类（startCall、stopCall）
- 共享数据类：`SttConfig`、`TtsConfig`、`LlmConfig`、`StsConfig`
- Pigeon 消息定义文件（供 agent_runtime 使用）

---

## Phase 3 — local_db 插件

**目标**：原生 SQLite 数据中心，agent_runtime 可直接访问（无 Channel 开销），Flutter 通过 Pigeon 读取。

### 数据表
```sql
service_configs  -- API key、服务商配置
agents           -- Agent 定义（name、type、config JSON）
messages         -- 聊天记录（requestId 作主键，status 枚举）
mcp_servers      -- 远程 MCP 服务器配置
```

### 实现分工
| 平台 | 技术 |
|------|------|
| Android | Room Database + Kotlin Coroutines |
| iOS | GRDB（Swift）|
| Flutter | Pigeon CRUD 接口（只读/写，无复杂 ORM）|

---

## Phase 4 — agent_runtime 插件 ★

**目标**：Agent 后台执行引擎，Flutter 脱离后可独立运行。

### 4.1 Pigeon 接口
```
AgentRuntimeApi（命令下行，Flutter→Native）
  - startSession(config)
  - stopSession(sessionId)
  - sendText(sessionId, requestId, text)
  - interrupt(sessionId)
  - setInputMode(sessionId, mode)

AgentRuntimeEventApi（事件上行，Native→Flutter）
  - onSttEvent(SttEvent)     // 7 种 STT 事件
  - onLlmEvent(LlmEvent)     // 8 种 LLM 事件
  - onTtsEvent(TtsEvent)     // 7 种 TTS 事件
  - onStateChanged(sessionId, state)
  - onError(sessionId, code, message)
```

### 4.2 Android 实现
- `AgentRuntimeService`（ForegroundService，AndroidManifest 声明）
- `AgentSession`（状态机：IDLE→LISTENING→STT→LLM→TTS→PLAYING）
- Pipeline 节点：`VadEngine`、`SttPipelineNode`、`LlmPipelineNode`、`TtsPipelineNode`
- 打断机制：`activeRequestId` + OkHttp `call.cancel()`
- requestId 生成：文本模式由 Flutter 传入，短语音/通话模式由 `SttPipelineNode` 在 `isFinal=true` 时生成

### 4.3 iOS 实现
- `AgentRuntimeManager`（AVAudioSession + BGTaskScheduler）
- `AgentSession`（Swift actor 状态机）
- Pipeline 节点同 Android
- 打断机制：`URLSessionDataTask.cancel()`

### 4.4 Flutter 桥接薄层
- `agent_runtime_bridge.dart`：封装 Pigeon 调用
- `agent_session_provider.dart`：Riverpod，监听事件 → UI 状态
- `agent_event.dart`：Dart 侧事件镜像枚举

---

## Phase 5 — STT 参考实现（stt_azure）

**目标**：作为 STT 插件的完整参考，其他 STT 实现（aliyun/google/doubao）复用相同结构。

### 事件流（7 种）
```
ListeningStarted → VadSpeechStart → PartialResult(×n) → VadSpeechEnd
  → FinalResult → ListeningStopped
  错误时: Error
```

### 实现要点
- Android：Azure Speech SDK（Kotlin）
- iOS：Azure Speech SDK（Swift）
- 通过 `ai_plugin_interface` 中的 `SttPlugin` 抽象类实现

---

## Phase 6 — TTS 参考实现（tts_azure）

**目标**：作为 TTS 插件的完整参考。

### 事件流（7 种）
```
SynthesisStart → SynthesisReady → PlaybackStart → PlaybackProgress(×n)
  → PlaybackDone
  打断时: PlaybackInterrupted
  错误时: Error
```

---

## Phase 7 — LLM 插件（llm_openai）

**目标**：OpenAI-compatible streaming 接口 + 内置 MCP 工具调用。

### 事件流（8 种）
```
Thinking（可选）→ FirstToken → [ToolCallStart → ToolCallArguments → ToolCallResult] → Done
  取消时: Cancelled
  错误时: Error
```

### 实现要点
- 纯 Dart HTTP（`http` + `dart:async` Stream）
- SSE 流式解析
- MCP 工具路由：`McpManager`（本地内置工具 + 远程 SSE/HTTP 服务器）
- `requestId` 对应 `activeRequestId` 取消检测

---

## Phase 8 — Flutter UI 层

**目标**：3-tab 导航壳 + 全部功能屏幕，纯 UI 镜像，无业务逻辑。

### 屏幕清单
| 屏幕 | 路由 |
|------|------|
| AgentPanelScreen（主页 Tab 1）| `/` |
| ChatAgentScreen | `/agent/:id/chat` |
| TranslateAgentScreen | `/agent/:id/translate` |
| ServicesScreen（Tab 2）| `/services` |
| SettingsScreen（Tab 3）| `/settings` |
| AddAgentModal（弹窗）| - |
| McpConfigScreen（全页）| `/agent/:id/mcp` |
| AddServiceModal（弹窗）| - |

### 主题
- light / dark / system 三选一
- `ThemeMode` 由 `settings_provider.dart` 持有，`MaterialApp` 响应

### 输入栏三态
- 短语音：按住说话，松手发送
- 文字：输入框 + 发送按钮（Flutter 生成 requestId）
- 通话：常驻监听模式（Native 持续 VAD+STT 循环）

---

## Phase 9 — Translation 插件

**目标**：纯 Dart HTTP，每条消息独立翻译，无打断机制。

- `translation_deepl`：DeepL API v2
- `translation_aliyun`：阿里云机器翻译 API

---

## Phase 10 — STS 插件（sts_volcengine）

**目标**：端到端语音，agent_runtime 直接调度，无中间 STT/LLM/TTS 分步。

- 火山引擎 STS WebSocket API
- Android：OkHttp WebSocket（Kotlin）
- iOS：URLSessionWebSocketTask（Swift）

---

## 关键技术决策汇总

| 决策 | 选择 | 原因 |
|------|------|------|
| Agent 执行层 | 原生 Service | Flutter 后台会被回收 |
| 数据库 | 原生 SQLite（Room/GRDB）| agent_runtime 直接访问，零 Channel 延迟 |
| Flutter→Native 命令 | Pigeon MethodChannel | 类型安全，无反射 |
| Native→Flutter 事件 | EventChannel | 单向流，适合持续事件推送 |
| 打断机制 | requestId + activeRequestId + HTTP cancel | 精确对应，无竞争 |
| 翻译打断 | 不适用 | 翻译每句独立，无需打断 |
| requestId 生成 | 文本：Flutter；短语音/通话：原生 STT isFinal 时 | 各模式知情方生成 |
| 状态管理 | Riverpod（Flutter 侧薄层）| 仅做 UI 镜像，无复杂业务 |
