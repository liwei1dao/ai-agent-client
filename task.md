# AI Agent Client — 任务清单

> 按顺序执行，完成一项标记 ✅，阻塞时记录原因。
> 所有代码在 `./app/` 目录下。

---

## Phase 1 — 项目基础骨架

- [ ] **T1.1** 在 `./app` 创建 Flutter 工程（flutter create）
- [ ] **T1.2** 配置 `./app/pubspec.yaml`（添加 riverpod、go_router、pigeon、flutter_dotenv、uuid 等依赖）
- [ ] **T1.3** 建立 `./app/lib/` 完整目录骨架（空 `.dart` 占位文件）
- [ ] **T1.4** 建立 `./app/local_plugins/` 目录，为每个插件创建 `pubspec.yaml` 骨架
- [ ] **T1.5** 主工程 `pubspec.yaml` 通过 `path` 引用所有本地插件
- [ ] **T1.6** 创建 `.env.example`（列出所有需要的 API Key 名称）
- [ ] **T1.7** 配置 `analysis_options.yaml`

---

## Phase 2 — ai_plugin_interface

- [ ] **T2.1** 定义 `SttPlugin` 抽象类 + 配置/结果数据类
- [ ] **T2.2** 定义 `TtsPlugin` 抽象类 + 配置/结果数据类
- [ ] **T2.3** 定义 `LlmPlugin` 抽象类 + `LlmMessage`、`LlmTool`、`ToolCall` 数据类
- [ ] **T2.4** 定义 `TranslationPlugin` 抽象类
- [ ] **T2.5** 定义 `StsPlugin` 抽象类
- [ ] **T2.6** 定义 Pigeon 消息文件（`agent_runtime_messages.dart`）：AgentRuntimeApi + AgentRuntimeEventApi + 全部事件类

---

## Phase 3 — local_db 插件

- [ ] **T3.1** 定义 Pigeon 接口（`local_db_messages.dart`）：ServiceConfig、Agent、Message、McpServer CRUD
- [ ] **T3.2** 生成 Pigeon 代码（`flutter pub run pigeon`）
- [ ] **T3.3** Android：Room Database（`AppDatabase.kt`）+ Entity 类
- [ ] **T3.4** Android：DAO 实现（ServiceConfigDao、AgentDao、MessageDao、McpServerDao）
- [ ] **T3.5** Android：`LocalDbPlugin.kt`（FlutterPlugin 入口，连接 Pigeon ↔ Room）
- [ ] **T3.6** iOS：`AppDatabase.swift`（GRDB 封装）+ Model 类
- [ ] **T3.7** iOS：DAO 实现（4 个 DAO）
- [ ] **T3.8** iOS：`LocalDbPlugin.swift`（FlutterPlugin 入口）
- [ ] **T3.9** Dart 桥接：`local_db.dart`（公开 API） + `local_db_channel.dart`（Pigeon 生成桥接）

---

## Phase 4 — agent_runtime 插件 ★

### 4A — Pigeon 接口 + Dart 桥接

- [ ] **T4A.1** 编写 `pigeons/agent_runtime_messages.dart`（完整接口 + 全部事件类）
- [ ] **T4A.2** 运行 `flutter pub run pigeon` 生成 Android/iOS/Dart 代码
- [ ] **T4A.3** 实现 `agent_runtime_bridge.dart`（封装 Pigeon 调用）
- [ ] **T4A.4** 实现 `agent_event.dart`（Dart 侧事件镜像枚举）
- [ ] **T4A.5** 实现 `agent_session_provider.dart`（Riverpod，EventChannel → UI 状态）

### 4B — Android 实现

- [ ] **T4B.1** `AgentRuntimePlugin.kt`（FlutterPlugin 入口，注册 Pigeon + 绑定 Service）
- [ ] **T4B.2** `AgentRuntimeService.kt`（ForegroundService，管理多个 AgentSession）
- [ ] **T4B.3** `AgentSession.kt`（状态机：IDLE/LISTENING/STT/LLM/TTS/PLAYING + activeRequestId）
- [ ] **T4B.4** `VadEngine.kt`（静音检测，触发 STT 开始/结束）
- [ ] **T4B.5** `SttPipelineNode.kt`（调用 STT 插件，isFinal 时生成 requestId，推送 7 种 STT 事件）
- [ ] **T4B.6** `LlmPipelineNode.kt`（OkHttp SSE 流，推送 8 种 LLM 事件，支持 cancel）
- [ ] **T4B.7** `TtsPipelineNode.kt`（调用 TTS 插件，推送 7 种 TTS 事件）
- [ ] **T4B.8** `AndroidManifest.xml`（声明 AgentRuntimeService + 权限：FOREGROUND_SERVICE、RECORD_AUDIO）

### 4C — iOS 实现

- [ ] **T4C.1** `AgentRuntimePlugin.swift`（FlutterPlugin 入口）
- [ ] **T4C.2** `AgentRuntimeManager.swift`（AVAudioSession + BGTaskScheduler 管理）
- [ ] **T4C.3** `AgentSession.swift`（Swift actor 状态机 + activeRequestId）
- [ ] **T4C.4** `VadEngine.swift`
- [ ] **T4C.5** `SttPipelineNode.swift`（isFinal 时生成 requestId，推送 7 种 STT 事件）
- [ ] **T4C.6** `LlmPipelineNode.swift`（URLSession SSE + cancel）
- [ ] **T4C.7** `TtsPipelineNode.swift`（推送 7 种 TTS 事件）
- [ ] **T4C.8** `Info.plist` 配置 Background Modes: audio

---

## Phase 5 — stt_azure 插件

- [ ] **T5.1** Android：`SttAzurePlugin.kt`（实现 SttPlugin，Azure Speech SDK）
- [ ] **T5.2** Android：7 种 STT 事件推送完整实现
- [ ] **T5.3** iOS：`SttAzurePlugin.swift`（实现 SttPlugin，Azure Speech SDK）
- [ ] **T5.4** iOS：7 种 STT 事件推送完整实现
- [ ] **T5.5** Dart：`stt_azure.dart`（公开 API）

---

## Phase 6 — tts_azure 插件

- [ ] **T6.1** Android：`TtsAzurePlugin.kt`（实现 TtsPlugin，Azure TTS SDK）
- [ ] **T6.2** Android：7 种 TTS 事件推送完整实现
- [ ] **T6.3** iOS：`TtsAzurePlugin.swift`（实现 TtsPlugin）
- [ ] **T6.4** iOS：7 种 TTS 事件推送完整实现
- [ ] **T6.5** Dart：`tts_azure.dart`（公开 API）

---

## Phase 7 — llm_openai 插件

- [ ] **T7.1** Dart：`LlmOpenaiPlugin`（实现 LlmPlugin，纯 Dart HTTP + SSE 解析）
- [ ] **T7.2** Dart：`McpManager`（本地内置工具注册 + 远程 SSE/HTTP MCP 服务器路由）
- [ ] **T7.3** Dart：`McpServerConfig`（URL、transport、auth header、已启用工具列表）
- [ ] **T7.4** Dart：LLM 事件流（Thinking/FirstToken/ToolCallStart/ToolCallArguments/ToolCallResult/Done/Cancelled/Error）
- [ ] **T7.5** Dart：requestId 取消检测（与 `activeRequestId` 比对，过期则 cancel）

---

## Phase 8 — Flutter UI 层

### 8A — 应用壳

- [ ] **T8A.1** `main.dart`（flutter_dotenv 加载 .env，Riverpod ProviderScope，runApp）
- [ ] **T8A.2** `app.dart`（MaterialApp.router + go_router 路由表 + 主题响应）
- [ ] **T8A.3** `shared/themes/app_theme.dart`（light/dark ThemeData）
- [ ] **T8A.4** `core/config/app_config.dart`（从 .env 读取所有 API Key）

### 8B — 底部导航

- [ ] **T8B.1** `BottomNavigationBar` 3-tab 壳（Agents / Services / Settings）
- [ ] **T8B.2** go_router 嵌套路由（StatefulShellRoute）

### 8C — Services 屏幕（Tab 2）

- [ ] **T8C.1** `services_screen.dart`（服务卡片列表）
- [ ] **T8C.2** `service_card.dart`（显示服务类型、状态、快速测试按钮）
- [ ] **T8C.3** `add_service_modal.dart`（类型选择：STT/TTS/LLM/STS，厂商选择，API Key 输入）
- [ ] **T8C.4** `vendor_grid.dart`（厂商图标格）
- [ ] **T8C.5** `service_library_provider.dart`（Riverpod，CRUD via local_db）

### 8D — Agents 屏幕（Tab 1）

- [ ] **T8D.1** `agent_panel_screen.dart`（Agent 卡片列表 + FAB 新建）
- [ ] **T8D.2** `agent_card.dart`（显示 Agent 名称、类型、状态、启动/停止按钮）
- [ ] **T8D.3** `add_agent_modal.dart`（Chat/Translate 类型，绑定 STT/TTS/LLM 服务）
- [ ] **T8D.4** `agent_list_provider.dart`（Riverpod，Agent 列表管理）

### 8E — Chat Agent 屏幕

- [ ] **T8E.1** `chat_agent_screen.dart`（消息列表 + 输入栏，仅镜像原生状态）
- [ ] **T8E.2** `message_bubble.dart`（user/assistant 气泡，streaming 效果，cancelled 样式）
- [ ] **T8E.3** `multimodal_input_bar.dart`（短语音/文字/通话 三态切换）
- [ ] **T8E.4** `audio_visualizer.dart`（VAD 音量波形动画）
- [ ] **T8E.5** `chat_agent_provider.dart`（监听 EventChannel 事件，映射到 UI 状态）
- [ ] **T8E.6** 文本发送：Flutter 生成 UUID requestId → `sendText(sessionId, requestId, text)`

### 8F — Translate Agent 屏幕

- [ ] **T8F.1** `translate_agent_screen.dart`
- [ ] **T8F.2** `language_bar.dart`（源语言 → 目标语言切换）
- [ ] **T8F.3** `translation_result_card.dart`（原文 + 译文卡片）
- [ ] **T8F.4** `call_mode_bar.dart`（通话模式常驻监听状态栏）
- [ ] **T8F.5** `translate_agent_provider.dart`

### 8G — MCP 配置屏幕

- [ ] **T8G.1** `mcp_config_screen.dart`（本地工具列表 + 远程服务器列表）
- [ ] **T8G.2** 添加远程 MCP 服务器表单（Name、URL、Transport SSE/HTTP、Auth Header、连接测试、工具多选）

### 8H — Settings 屏幕（Tab 3）

- [ ] **T8H.1** `settings_screen.dart`（全局参数列表）
- [ ] **T8H.2** 外观设置（浅色/深色/跟随系统 三段式 Pill 选择器）
- [ ] **T8H.3** `settings_provider.dart`（Riverpod，ThemeMode 持久化）

---

## Phase 9 — Translation 插件

- [ ] **T9.1** `translation_deepl`：纯 Dart HTTP，DeepL API v2
- [ ] **T9.2** `translation_aliyun`：纯 Dart HTTP，阿里云机器翻译 API
- [ ] **T9.3** 注册到 `registry/translation_registry.dart`

---

## Phase 10 — sts_doubao 插件

- [ ] **T10.1** Android：`StsDoubaoPlugin.kt`（OkHttp WebSocket，豆包 STS API）
- [ ] **T10.2** iOS：`StsDoubaoPlugin.swift`（URLSessionWebSocketTask）
- [ ] **T10.3** Dart：`sts_doubao.dart`（公开 API，agent_runtime 调度入口）

---

## 完成标准

- [ ] `flutter analyze` 零警告
- [ ] `flutter build apk --debug` 成功
- [ ] `flutter build ios --debug --no-codesign` 成功
- [ ] 基本 UI 流程可走通（创建 Agent → 发送文本 → 收到 LLM 流式响应）
