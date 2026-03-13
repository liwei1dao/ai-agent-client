# 实现计划（Implementation Plan）

**项目**：AI Agent Client
**版本**：v1.0
**日期**：2026-03-13
**参考架构**：[architecture.md](./architecture.md)

---

## 总体策略

按"由内而外"的顺序构建：

```
基础设施层（插件接口 + 数据库）
    ↓
Flutter UI Shell（导航框架 + 屏幕骨架）
    ↓
功能模块（Services / Agents / Settings）
    ↓
Agent 运行界面（Chat / Translate）
    ↓
原生插件实现（STT / TTS / LLM Stub）
    ↓
agent_runtime 原生实现（Android + iOS）
    ↓
端到端联调
```

**阶段目标**：每个阶段结束后 App 可独立运行，展示当前阶段成果。

---

## Phase 0：项目脚手架

**目标**：建立完整目录结构，配置所有 pubspec.yaml 依赖关系。

**关键决策**：
- 采用 `flutter create` 创建主工程，手动建立 `local_plugins/` 下各包
- 本地插件通过 `path:` 引用，不发布 pub.dev
- 使用 `flutter_dotenv` 管理 API Key，`.env` 加入 `.gitignore`
- 状态管理：Riverpod 2.x（`flutter_riverpod` + `riverpod_annotation`）
- 路由：`go_router`
- Pigeon 版本：`pigeon: ^22.x`

**产物**：
- 主工程 `pubspec.yaml`（含所有依赖）
- 各 local_plugins 的 `pubspec.yaml`
- 目录骨架（空文件占位）

---

## Phase 1：共享接口层（ai_plugin_interface）

**目标**：定义所有插件共用的抽象接口、数据模型、Pigeon 消息定义。

**关键设计**：
- `SttProvider` / `TtsProvider` / `LlmProvider` / `TranslationProvider` 抽象类
- 统一的 `PluginException`（errorCode + message）
- Pigeon 消息类型（`SttConfig`, `SttResult`, `TtsRequest`, `LlmMessage`, `LlmConfig`）
- 不含任何原生代码，纯 Dart 包

**为何优先**：所有其他插件都依赖此包的接口定义，必须先行。

---

## Phase 2：本地数据库插件（local_db）

**目标**：实现跨平台 SQLite 存储，供 agent_runtime 原生直接访问、Flutter 通过 Pigeon 读取。

**关键设计**：
- Android：Room（`@Database`, `@Dao`, `@Entity`）
- iOS：GRDB（Swift，SQLite 直接封装）
- Pigeon 接口定义：CRUD for services / agents / messages / mcp_servers
- 敏感字段（apiKey）在原生层使用 Keystore/Keychain 加密存储

**实现顺序**：
1. Pigeon 消息定义 → 生成代码
2. Android Room 实现（entities + DAOs + Database）
3. iOS GRDB 实现（migrations + query helpers）
4. Dart 侧封装（`LocalDb` 单例）

---

## Phase 3：Flutter UI Shell

**目标**：3-tab 导航框架 + 各屏幕占位骨架 + 主题系统。

**关键设计**：
- `BottomNavigationBar`（Agents / Services / Settings）
- `go_router` 路由定义（路由表 + 参数传递）
- `AppTheme`（浅色 / 深色）+ `ThemeProvider`（跟随系统 / 手动切换）
- Riverpod `ProviderScope` 根节点

**每个屏幕只需能展示占位内容即可**，业务内容在后续阶段填充。

---

## Phase 4：Services 功能

**目标**：用户可添加/编辑/删除服务配置，配置持久化到 local_db。

**关键设计**：
- `ServiceLibraryNotifier`（Riverpod AsyncNotifier）：从 local_db 加载，写入变更
- `ServicesScreen`：服务卡片网格 + "添加服务" FAB
- `AddServiceModal`：
  - 类型分段选择器（STT / TTS / STS / LLM / 翻译）
  - 厂商 6 宫格图标选择器
  - 动态表单（根据厂商不同展示不同字段）
  - "测试连接"按钮（Phase 8 后真正可用，此阶段模拟成功）
- `ServiceCard`：显示服务名称、类型、厂商图标、连接状态

---

## Phase 5：Agents 功能

**目标**：用户可创建/编辑/删除 Agent 配置，Agent 列表持久化。

**关键设计**：
- `AgentListNotifier`（Riverpod AsyncNotifier）：从 local_db 加载
- `AgentPanelScreen`：Agent 卡片网格 + FAB
- `AddAgentModal`：
  - 类型选择（Chat / Translate）
  - Chat：选 LLM / STT / TTS 服务（从 ServiceLibrary 中选）、system prompt、MCP 配置入口
  - Translate：选翻译服务、源语言、目标语言、TTS（可选）
- `AgentCard`：显示名称、类型、关联服务 chip
- `McpConfigScreen`（完整页）：
  - 本地内置工具列表（开关）
  - 远程 MCP 服务器列表 + "添加远程 MCP 服务器"入口
  - `AddRemoteMcpScreen`：服务器名称、URL、传输类型、Auth Header、连接测试、工具多选

---

## Phase 6：Chat Agent 运行界面

**目标**：完整 Chat UI，含消息流式显示、多模态输入栏、工具调用卡片。

**关键设计**：
- `ChatAgentScreen`：消息列表 + 输入栏
- `MultimodalInputBar`（三态）：
  - 短语音：按住录音按钮，VAD 波形，松手发送
  - 文字：TextField + 发送按钮
  - 通话：计时器 + 打断按钮 + 挂断按钮
- `MessageBubble`：
  - `status=streaming`：末尾闪烁光标
  - `status=cancelled`：灰色删除线样式
  - `status=error`：红色 + 重试按钮
  - 工具调用卡片（callId + toolName + 执行状态 + 结果折叠）
  - Thinking 区域（可折叠）
- `AudioVisualizer`：波形动画（`flutter_sound` 或自绘）
- `ChatAgentProvider`：镜像 agent_runtime EventChannel 事件 → Riverpod 状态

**此阶段 agent_runtime 以 Mock 模式运行**，模拟完整事件序列。

---

## Phase 7：Translate Agent 运行界面

**目标**：翻译界面，含语言选择、逐句翻译对、同传模式。

**关键设计**：
- `TranslateAgentScreen`：语言栏 + 翻译对列表 + 输入栏
- `LanguageBar`：源语言 DropdownButton ⇌ 目标语言 DropdownButton
- `TranslationResultCard`：原文 + 译文 + TTS 播放按钮
- 同传模式：进入通话模式后自动开始 VAD→STT→Translation 循环
- 翻译不参与打断机制（每句独立处理）

---

## Phase 8：Settings 屏幕

**目标**：主题切换、后台服务开关、全局对话参数持久化。

**关键设计**：
- `SettingsScreen`：分组列表（外观 / 后台服务 / 对话默认参数 / 语音默认参数 / 关于）
- `SettingsProvider`：读写 SharedPreferences（主题、参数）
- 主题 Pill 选择器（浅色 / 深色 / 跟随系统）→ 实时生效
- 后台运行开关（Android: 引导开启忽略电池优化；iOS: 不需要额外操作）

---

## Phase 9：原生能力插件 Stub 实现

**目标**：每个 STT/TTS/LLM 插件提供可编译的最小化实现（真实 SDK 接入延后）。

**实现策略**：
- 先实现 `stt_azure`（作为参考实现，含完整 Pigeon 接口、Engine 骨架）
- 其他厂商插件直接复制骨架，API Key / SDK 接入部分留 TODO
- `llm_openai`：实现 OpenAI Streaming Chat Completion（纯 HTTP，无需原生 SDK）
- `translation_deepl` / `translation_google` / `translation_aliyun`：纯 Dart HTTP 实现

**接入顺序**（按优先级）：
1. `llm_openai`（最容易，纯 HTTP Dart 实现）
2. `translation_deepl`（同上）
3. `tts_azure`（Azure TTS streaming HTTP，无需重型 SDK）
4. `stt_azure`（需要 Azure Speech SDK）
5. 其他厂商可按需追加

---

## Phase 10：agent_runtime 原生实现（Android）

**目标**：Android ForegroundService 完整实现，驱动 Chat Agent 全流程。

**实现顺序**：
1. `AgentRuntimePlugin.kt`：FlutterPlugin 入口，注册 Pigeon + EventChannel
2. `AgentRuntimeService.kt`：ForegroundService，管理 Session Map，通知栏
3. `AgentSession.kt`：状态机框架（IDLE / LISTENING / RECORDING / STT_PROCESSING / LLM_CALLING / LLM_STREAMING / TTS_SYNTHESIZING / PLAYING）
4. `LlmPipelineNode.kt`：调用 `llm_openai` Engine，streaming 解析，OkHttp 取消
5. `TtsPipelineNode.kt`：调用 `tts_azure` Engine，AudioTrack 播放
6. `SttPipelineNode.kt`：调用 `stt_azure` Engine，VAD + 识别结果回调
7. `VadEngine.kt`：简单能量阈值 VAD（可替换为 Silero）
8. 打断机制：`activeRequestId` 追踪 + OkHttp cancel + DB status='cancelled'

---

## Phase 11：agent_runtime 原生实现（iOS）

**目标**：iOS AVAudioSession + Background Audio 完整实现，与 Android 功能对等。

**实现顺序**（类似 Android，Swift 版本）：
1. `AgentRuntimePlugin.swift`
2. `AgentRuntimeManager.swift`（AVAudioSession + BGTaskScheduler）
3. `AgentSession.swift`（状态机）
4. `LlmPipelineNode.swift`（URLSession streaming）
5. `TtsPipelineNode.swift`（AVAudioPlayer）
6. `SttPipelineNode.swift`
7. `VadEngine.swift`

---

## Phase 12：端到端联调 & 完善

**目标**：从用户说话到 AI 回答到 TTS 播报，全链路通畅。

**联调清单**：
- [ ] 文本模式：输入 → requestId 生成 → LLM 流式 → TTS → 播报
- [ ] 短语音模式：按住 → VAD → STT → requestId 生成 → LLM → TTS
- [ ] 通话模式：自动循环，打断机制，新 requestId 取消旧的
- [ ] 翻译模式：STT → Translation → 展示 → TTS 朗读
- [ ] 后台运行：App 退出后通话模式继续（Android ForegroundService）
- [ ] 状态恢复：App 重新进入前台，UI 重新同步原生状态
- [ ] 主题切换：浅色 / 深色 / 跟随系统
- [ ] 错误处理：网络断开、STT 无声音、LLM 超时、TTS 合成失败

---

## 技术栈汇总

| 层次 | 技术 |
|------|------|
| Flutter UI | Flutter 3.x, Riverpod 2.x, go_router |
| 跨平台通信 | Pigeon（命令），EventChannel（事件流）|
| 本地存储 | Android Room, iOS GRDB, Keystore/Keychain |
| 网络 | OkHttp (Android), URLSession (iOS), Dart http |
| LLM | OpenAI-compatible HTTP streaming |
| STT | Azure Speech SDK (Android AAR / iOS Pod) |
| TTS | Azure TTS HTTP streaming, AudioTrack/AVAudioPlayer |
| VAD | 能量阈值（可升级为 Silero ONNX） |
| 后台保活 | Android ForegroundService, iOS Background Audio |
| 主题 | ThemeData, SharedPreferences |
| 依赖注入 | Riverpod ProviderScope |
