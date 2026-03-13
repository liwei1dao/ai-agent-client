# 开发任务清单（Task List）

**项目**：AI Agent Client
**版本**：v1.0
**日期**：2026-03-13
**关联计划**：[plan.md](./plan.md) | **参考架构**：[architecture.md](./architecture.md)

> **规则**：每完成一项，在 `[ ]` 内填 `x` 变为 `[x]`，并在旁边标注完成日期。

---

## Phase 0：项目脚手架

### T0.1 创建 Flutter 主工程
- [ ] 执行 `flutter create ai_agent_client --org com.yourcompany --platforms android,ios`
- [ ] 删除默认 `counter` 示例代码
- [ ] 创建完整目录骨架（`lib/`, `local_plugins/`, `docs/`, `android/`, `ios/`）
- [ ] 添加 `.gitignore`（含 `.env`, `*.g.dart` 生成文件, `local_plugins/*/android/.gradle` 等）

### T0.2 配置主工程 pubspec.yaml
添加以下依赖：
```yaml
dependencies:
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5
  go_router: ^14.2.0
  pigeon: ^22.0.0           # dev_dependency
  flutter_dotenv: ^5.1.0
  shared_preferences: ^2.2.3
  uuid: ^4.4.0
  http: ^1.2.1
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.4.9
  json_serializable: ^6.8.0
  riverpod_generator: ^2.4.0
  flutter_lints: ^3.0.0
```
- [ ] 添加所有 local_plugins path 依赖
- [ ] 配置 `flutter_dotenv` assets（`.env`）
- [ ] 执行 `flutter pub get` 验证依赖无冲突

### T0.3 创建各 local_plugins 包骨架
为以下每个包创建最小 `pubspec.yaml` + `lib/` 目录：
- [ ] `local_plugins/ai_plugin_interface/`（纯 Dart 包）
- [ ] `local_plugins/local_db/`（Flutter 插件）
- [ ] `local_plugins/agent_runtime/`（Flutter 插件）
- [ ] `local_plugins/stt_azure/`（Flutter 插件）
- [ ] `local_plugins/tts_azure/`（Flutter 插件）
- [ ] `local_plugins/llm_openai/`（纯 Dart 包）
- [ ] `local_plugins/sts_doubao/`（Flutter 插件）
- [ ] `local_plugins/translation_deepl/`（纯 Dart 包）
- [ ] `local_plugins/translation_aliyun/`（纯 Dart 包）

### T0.4 环境配置
- [ ] 创建 `.env.example`（列出所有 Key 名称，值为空）
- [ ] 创建 `.env`（本地填入真实 Key，gitignore）
- [ ] 创建 `lib/core/config/app_config.dart`（从 dotenv 读取所有 Key）
- [ ] 创建 `lib/core/utils/logger.dart`（封装日志，debug 下打印，release 下抑制）

---

## Phase 1：ai_plugin_interface

### T1.1 抽象接口定义
- [ ] `lib/src/interfaces/stt_provider.dart`
  - `SttProvider` 抽象类
  - 方法：`startRecognition(SttConfig)`, `stopRecognition()`, `dispose()`
  - 事件流：`Stream<SttEvent>` （SttListeningStarted / VadSpeechStart / VadSpeechEnd / PartialResult / FinalResult / ListeningStopped / Error）
- [ ] `lib/src/interfaces/tts_provider.dart`
  - `TtsProvider` 抽象类
  - 方法：`synthesizeAndPlay(TtsRequest)`, `stop()`, `dispose()`
  - 事件流：`Stream<TtsEvent>` （SynthesisStart / SynthesisReady / PlaybackStart / PlaybackProgress / PlaybackDone / PlaybackInterrupted / Error）
- [ ] `lib/src/interfaces/llm_provider.dart`
  - `LlmProvider` 抽象类
  - 方法：`chat(LlmChatRequest)` → `Stream<LlmEvent>` （RequestStart / Thinking / FirstToken / Chunk / ToolCallStart / ToolCallArguments / ToolCallResult / Done / Cancelled / Error）
  - 方法：`cancel(String requestId)`
- [ ] `lib/src/interfaces/translation_provider.dart`
  - `TranslationProvider` 抽象类
  - 方法：`translate(String text, String from, String to)` → `Future<TranslationResult>`

### T1.2 数据模型
- [ ] `SttConfig`（language, sampleRate, enablePartialResults）
- [ ] `SttEvent`（密封类，各子类型）
- [ ] `TtsRequest`（text, voiceId, speed, pitch）
- [ ] `TtsEvent`（密封类，各子类型，含 charIndex/charLength）
- [ ] `LlmMessage`（role, content, toolCallId?）
- [ ] `LlmChatRequest`（messages, model, temperature, maxTokens, tools, requestId）
- [ ] `LlmEvent`（密封类，各子类型）
- [ ] `TranslationResult`（sourceText, translatedText, sourceLang, targetLang）
- [ ] `PluginException`（errorCode, message, cause?）

---

## Phase 2：local_db 插件

### T2.1 Pigeon 接口定义（`pigeons/local_db_messages.dart`）
- [ ] `ServiceConfigDto`（id, type, vendor, name, configJson, createdAt, updatedAt）
- [ ] `AgentDto`（id, name, type, configJson, sortOrder）
- [ ] `MessageDto`（id, agentId, role, content, status, createdAt, updatedAt）
- [ ] `McpServerDto`（id, name, url, transport, headersJson, enabledToolsJson）
- [ ] `LocalDbApi`（HostApi）：
  - `insertServiceConfig(ServiceConfigDto)`
  - `updateServiceConfig(ServiceConfigDto)`
  - `deleteServiceConfig(String id)`
  - `getAllServiceConfigs()` → `List<ServiceConfigDto>`
  - `insertAgent(AgentDto)`
  - `updateAgent(AgentDto)`
  - `deleteAgent(String id)`
  - `getAllAgents()` → `List<AgentDto>`
  - `getMessages(String agentId, int limit, int offset)` → `List<MessageDto>`
  - `insertMessage(MessageDto)`
  - `updateMessageStatus(String id, String status)`
  - `appendMessageContent(String id, String chunk)`
  - `insertMcpServer(McpServerDto)`
  - `updateMcpServer(McpServerDto)`
  - `deleteMcpServer(String id)`
  - `getAllMcpServers()` → `List<McpServerDto>`
- [ ] 运行 `flutter pub run pigeon --input pigeons/local_db_messages.dart`

### T2.2 Android Room 实现
- [ ] `build.gradle`：添加 Room 依赖（`room-runtime`, `room-ktx`, `room-compiler`）
- [ ] `ServiceConfigEntity.kt`（@Entity）
- [ ] `AgentEntity.kt`（@Entity）
- [ ] `MessageEntity.kt`（@Entity，含 index on agent_id+created_at）
- [ ] `McpServerEntity.kt`（@Entity）
- [ ] `ServiceConfigDao.kt`（@Dao，含 insertOrReplace, deleteById, getAll）
- [ ] `AgentDao.kt`
- [ ] `MessageDao.kt`（含 getByAgentId(limit, offset), appendContent, updateStatus）
- [ ] `McpServerDao.kt`
- [ ] `AppDatabase.kt`（@Database，version=1，exportSchema=false，实例化为单例）
- [ ] `LocalDbPlugin.kt`（FlutterPlugin 入口 + Pigeon HostApi 实现，调用 Room DAO）

### T2.3 iOS GRDB 实现
- [ ] `local_db.podspec`：添加 GRDB.swift 依赖
- [ ] `AppDatabase.swift`（DatabaseQueue 单例，建表 SQL，migration 框架）
- [ ] 各 DAO Swift 实现（ServiceConfigDao, AgentDao, MessageDao, McpServerDao）
- [ ] `LocalDbPlugin.swift`（FlutterPlugin 入口 + Pigeon HostApi 实现）

### T2.4 Dart 封装
- [ ] `lib/local_db.dart`：导出 `LocalDb` 单例
- [ ] `lib/src/local_db_repository.dart`：封装 Pigeon 调用，提供 Stream 接口

---

## Phase 3：Flutter UI Shell

### T3.1 主题系统
- [ ] `lib/shared/themes/app_theme.dart`：
  - `lightTheme`（MaterialTheme，seed color 蓝绿色调）
  - `darkTheme`
  - 统一 `TextStyle` 规范（headline / body / caption）
  - 统一 `ColorScheme` 扩展（成功绿 / 警告橙 / 错误红）
- [ ] `lib/features/settings/providers/settings_provider.dart`：
  - `ThemeMode themeMode`（light / dark / system）
  - 读写 SharedPreferences
- [ ] `lib/app.dart`：`MaterialApp.router` 绑定 `themeMode`

### T3.2 路由配置
- [ ] `lib/app.dart`：`go_router` 定义：
  ```
  /                   → AgentPanelScreen (shell)
  /agents             → AgentPanelScreen
  /agents/:agentId    → ChatAgentScreen 或 TranslateAgentScreen（根据类型）
  /services           → ServicesScreen
  /settings           → SettingsScreen
  /mcp-config/:agentId → McpConfigScreen
  /add-mcp-server     → AddRemoteMcpScreen
  ```
- [ ] `lib/core/config/router.dart`：路由表独立文件

### T3.3 3-tab 导航骨架
- [ ] `lib/app.dart`：`ShellRoute` + `BottomNavigationBar`（Agents / Services / Settings）
- [ ] 各 Screen 文件建立（内容为空占位 Text）：
  - [ ] `lib/features/agents/screens/agent_panel_screen.dart`
  - [ ] `lib/features/services/screens/services_screen.dart`
  - [ ] `lib/features/settings/screens/settings_screen.dart`

---

## Phase 4：Services 功能

### T4.1 数据层
- [ ] `lib/registry/service_library.dart`：`ServiceConfig`、`ServiceType`、`SttVendor`、`TtsVendor`、`LlmVendorType`、`TranslationVendor` 等数据模型（JSON 序列化）
- [ ] `lib/registry/service_library_notifier.dart`：`ServiceLibraryNotifier`（AsyncNotifier），从 local_db 加载，写入 local_db

### T4.2 ServicesScreen UI
- [ ] `lib/features/services/screens/services_screen.dart`：
  - AppBar（"已配置服务" + [+ 添加服务] 按钮）
  - 服务卡片网格（按类型分组）
  - 空状态引导提示
- [ ] `lib/features/services/widgets/service_card.dart`：
  - 类型 Badge（STT/TTS/STS/LLM/翻译）
  - 服务名称
  - 厂商图标（SVG 或 Icon）
  - 连接状态（✅ / ⚠️ / ❌）
  - 长按删除

### T4.3 AddServiceModal
- [ ] `lib/features/services/widgets/add_service_modal.dart`：
  - Step 1：服务类型分段选择器（STT / TTS / STS / LLM / 翻译）
  - Step 2：厂商 6 宫格选择器（根据类型展示不同厂商）
  - Step 3：动态表单（根据厂商类型展示字段）
    - STT Azure：subscriptionKey, region, language
    - STT Aliyun：appKey, token, language
    - LLM OpenAI compatible：baseUrl, apiKey, model, temperature, maxTokens
    - LLM Coze：apiKey, botId, baseUrl
    - TTS Azure：subscriptionKey, region, voiceId
    - STS Doubao：appId, token, voiceType
    - Translation DeepL：apiKey
    - Translation Aliyun：accessKeyId, accessKeySecret
  - 服务名称输入框（用户自命名）
  - [测试连接] 按钮（Phase 9 后真实测试，此阶段模拟延迟后返回成功）
  - [保存] 按钮

---

## Phase 5：Agents 功能

### T5.1 数据层
- [ ] `lib/agents/agent_config.dart`：`AgentConfig`（基类）、`AgentType` 枚举、`ChatAgentConfig`、`TranslateAgentConfig`（JSON 序列化）
- [ ] `lib/agents/agent_list_notifier.dart`：`AgentListNotifier`，从 local_db 加载

### T5.2 AgentPanelScreen UI
- [ ] `lib/features/agents/screens/agent_panel_screen.dart`：
  - 页面标题 + [+] FAB
  - `GridView` 展示 AgentCard
  - 空状态（"点击 + 创建你的第一个 Agent"）
- [ ] `lib/features/agents/widgets/agent_card.dart`：
  - Agent 名称 + 类型图标
  - 关联服务 Chip（LLM: GPT-4o，STT: Azure 等）
  - [打开] 按钮 → 跳转 ChatAgentScreen / TranslateAgentScreen
  - [⋮] 菜单（编辑 / 删除）

### T5.3 AddAgentModal
- [ ] `lib/features/agents/widgets/add_agent_modal.dart`：
  - Agent 名称输入框
  - 类型切换（Chat / Translate）
  - **Chat 配置**：
    - LLM 服务选择器（从 ServiceLibrary 过滤 type=llm）
    - STT 服务选择器（可选）
    - TTS 服务选择器（可选）→ 选中后展开音色选择器
    - System Prompt 文本区域（多行）
    - MCP 配置入口按钮（→ McpConfigScreen）
    - 默认输入模式选择（短语音 / 文字 / 通话）
  - **Translate 配置**：
    - 翻译服务选择器
    - 源语言 / 目标语言选择器
    - TTS 服务（可选）

### T5.4 McpConfigScreen
- [ ] `lib/features/agents/widgets/mcp_config_screen.dart`（独立全页面）：
  - **本地内置工具** 列表（UserInfoTool / DateTimeTool / CalculatorTool / DeviceInfoTool），每项有开关
  - **远程 MCP 服务器** 列表 + [+ 添加] 按钮
  - 服务器条目显示：名称、URL、传输类型、已启用工具数量
- [ ] `lib/features/agents/widgets/add_remote_mcp_screen.dart`（独立全页面）：
  - 服务器名称输入框
  - URL 输入框（带格式验证）
  - 传输类型选择（SSE / HTTP）
  - Authorization Header 输入框（可选）
  - [连接测试] 按钮 → 模拟连接 → 展示工具列表（多选 CheckboxListTile）
  - [保存并启用] 按钮

---

## Phase 6：Chat Agent 运行界面

### T6.1 状态模型
- [ ] `lib/runtime/agent_event.dart`：
  - `AgentState` 枚举（IDLE / LISTENING / RECORDING / STT_PROCESSING / LLM_CALLING / LLM_STREAMING / TTS_SYNTHESIZING / PLAYING）
  - `AgentEvent` 密封类（对应所有 EventApi 事件）
  - `MessageUiState`（id, role, content, status, toolCalls, thinkingContent）
- [ ] `lib/features/chat_agent/providers/chat_agent_provider.dart`：
  - `ChatAgentNotifier`（AsyncNotifier）
  - 订阅 `agent_runtime` EventChannel 事件
  - 维护 `List<MessageUiState>` 消息列表
  - requestId 生成（文本模式），接收 onSttFinalResult 中的 requestId（语音模式）
  - "最新优先"：收到 onRequestCancelled 时更新旧消息状态为 cancelled

### T6.2 ChatAgentScreen 主体
- [ ] `lib/features/chat_agent/screens/chat_agent_screen.dart`：
  - AppBar：Agent 名称 + 服务 Badge（LLM / STT）
  - `ListView.builder`（消息列表，自动滚动到底部）
  - STT 识别中间结果悬浮气泡（onSttPartialResult 显示，onSttFinalResult 消失）
  - TTS 播放指示栏（onTtsPlaybackStart 显示波形动画）
  - 底部：`MultimodalInputBar`

### T6.3 MessageBubble 组件
- [ ] `lib/features/chat_agent/widgets/message_bubble.dart`：
  - **用户气泡**：右对齐，蓝色背景，文字白色
  - **AI 气泡**：左对齐，灰色背景
    - `status=pending`：显示 "..." 三点动画
    - `status=streaming`：文字 + 末尾闪烁光标 `▋`
    - `status=done`：静态文字（支持 Markdown 渲染，可配置关闭）
    - `status=cancelled`：灰色文字 + 删除线 + "已取消" 标签
    - `status=error`：红色边框 + 错误提示 + [重试] 按钮
    - **Thinking 折叠区**：`onLlmThinking` 时展开，完成后可折叠
    - **工具调用卡片**（内嵌在气泡中）：
      - 工具名称 + callId
      - 参数折叠（可展开）
      - 执行状态：进行中 / 完成 ✓ / 错误 ✗

### T6.4 MultimodalInputBar 组件
- [ ] `lib/features/chat_agent/widgets/multimodal_input_bar.dart`：
  - **短语音态**：[⌨️] + [● 按住说话，松开发送] + [📞]
    - 按住：显示波形 + 录音时长，调用 `agent_runtime` 开始录音
    - 松手：发送，触发 STT
    - 上滑取消：动画提示 + 取消录音
  - **文字态**：[🎤] + TextField（hint: "输入消息...") + [↑ 发送] + [📞]
    - 发送：生成 UUID requestId → `sendText(sessionId, requestId, text)`
  - **通话态**：[🟢 通话中 · 计时器] + [✋ 打断] + [📞 挂断]
    - 打断：调用 `interrupt(sessionId)`
    - 挂断：调用 `setInputMode(sessionId, "voice")` 退出通话
  - 三态切换动画（AnimatedSwitcher）

### T6.5 AudioVisualizer 组件
- [ ] `lib/features/chat_agent/widgets/audio_visualizer.dart`：
  - 基于音频幅度的 CustomPainter 波形动画
  - 录音中（绿色波形）/ 播放中（蓝色波形）/ 空闲（静态图标）

---

## Phase 7：Translate Agent 运行界面

### T7.1 TranslateAgentProvider
- [ ] `lib/features/translate_agent/providers/translate_agent_provider.dart`：
  - 维护翻译对列表 `List<TranslationPairState>`（原文 + 译文 + 状态）
  - 通话模式下自动循环（每个 STT FinalResult → 触发 Translation）
  - 翻译独立处理，无 requestId 打断机制

### T7.2 TranslateAgentScreen
- [ ] `lib/features/translate_agent/screens/translate_agent_screen.dart`：
  - `LanguageBar`（源语言 DropdownButton ⇌ 目标语言 DropdownButton）
  - 翻译对滚动列表（TranslationResultCard）
  - 输入栏（复用 MultimodalInputBar，无通话打断按钮，换为"结束"）
  - 同传模式：进入通话后栏变为 "🟢 同传中 · 计时器 [🔇] [📞 结束]"

### T7.3 TranslationResultCard
- [ ] `lib/features/translate_agent/widgets/translation_result_card.dart`：
  - 原文区（灰色，STT 识别文字）
  - 译文区（黑/白色，翻译结果，流式追加）
  - [▶] TTS 朗读按钮（点击播放本句译文）

---

## Phase 8：Settings 屏幕

### T8.1 SettingsProvider
- [ ] `lib/features/settings/providers/settings_provider.dart`：
  - `ThemeMode` 读写
  - `HistoryMessageCount` (int)
  - `DefaultTemperature` (double)
  - `DefaultMaxTokens` (int)
  - `MarkdownRender` (bool)
  - `DefaultSampleRate` (int)
  - `TtsSpeed` (double)
  - `TtsPitch` (double)
  - 所有值持久化到 SharedPreferences

### T8.2 SettingsScreen
- [ ] `lib/features/settings/screens/settings_screen.dart`：
  - **外观** 分组：
    - 主题 Pill 选择器（浅色 | 深色 | 跟随系统）→ 实时应用
  - **后台服务** 分组：
    - "后台运行" Switch
    - Android：点击"电池优化" → 系统设置忽略优化页
    - "开机自启" Switch（Android only）
  - **对话默认参数** 分组：
    - 历史消息数（Slider，5~100）
    - Temperature（Slider，0.0~2.0）
    - Max Tokens（TextField，数字键盘）
    - Markdown 渲染（Switch）
  - **语音默认参数** 分组：
    - 采样率（DropdownButton：8000/16000/24000/48000）
    - TTS 语速（Slider，0.5x~2.0x）
    - TTS 音调（Slider，-10~10）
  - **关于** 分组：
    - App 版本（从 pubspec 读取）
    - 开源协议 MIT（点击查看）

---

## Phase 9：llm_openai 实现（纯 Dart）

### T9.1 LLM Provider 实现
- [ ] `lib/src/openai_llm_provider.dart`：实现 `LlmProvider` 接口
  - `chat(LlmChatRequest)` → `Stream<LlmEvent>`
  - 使用 Dart `http` 发送 POST `{baseUrl}/chat/completions`，`stream: true`
  - 解析 SSE（`data: {...}` 行逐行处理）
  - 支持 `tool_calls`（工具调用）解析
  - 发出事件：RequestStart → FirstToken → Chunk × N → (ToolCallStart → ToolCallArguments → ToolCallResult) × M → Done
  - `cancel(requestId)`：调用 `http.Client.close()`
  - 错误处理：429 → RATE_LIMIT / 401 → AUTH_ERROR / 超时 → TIMEOUT

### T9.2 OpenAI Models
- [ ] `LlmMessage`（role, content, tool_call_id, tool_calls）
- [ ] `ToolCallDelta`（id, name, argumentsChunk）
- [ ] SSE 解析器（支持增量 JSON 拼接）

---

## Phase 10：translation_deepl 实现（纯 Dart）

### T10.1 Translation Provider 实现
- [ ] `lib/src/deepl_translation_provider.dart`：实现 `TranslationProvider`
  - `translate(text, from, to)` → POST `https://api-free.deepl.com/v2/translate`
  - 解析 JSON 响应，返回 `TranslationResult`
  - 错误处理：403 AUTH_ERROR / 456 QUOTA_EXCEEDED / 超时 TIMEOUT

---

## Phase 11：agent_runtime Pigeon 接口

### T11.1 Pigeon 定义（已在 architecture.md §3.1 设计完毕）
- [ ] 创建 `local_plugins/agent_runtime/pigeons/agent_runtime_messages.dart`（按 §3.1 完整定义）
- [ ] 运行 `flutter pub run pigeon --input pigeons/agent_runtime_messages.dart`
- [ ] 验证生成的 Kotlin 和 Swift 骨架代码

### T11.2 Dart 侧桥接层
- [ ] `lib/runtime/agent_runtime_bridge.dart`：
  - 封装 Pigeon `AgentRuntimeApi` 调用（startSession / stopSession / sendText / interrupt / setInputMode）
  - 订阅 EventChannel → 解析 `AgentEvent` → 广播给各 Provider
- [ ] `lib/runtime/agent_session_provider.dart`：
  - Riverpod Provider，持有 `AgentRuntimeBridge` 单例
  - 管理 `Map<sessionId, SessionState>`

---

## Phase 12：agent_runtime Android 实现

### T12.1 基础框架
- [ ] `AndroidManifest.xml`（agent_runtime 插件）：
  - 声明 `AgentRuntimeService`（foregroundServiceType: microphone）
  - 声明权限：RECORD_AUDIO, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE
- [ ] `AgentRuntimePlugin.kt`：
  - `FlutterPlugin.onAttachedToEngine`：注册 Pigeon HostApi + 绑定 Service
  - `FlutterPlugin.onDetachedFromEngine`：解绑（不停止 Service）
- [ ] `AgentRuntimeService.kt`：
  - `ForegroundService`，`onStartCommand` 处理 session 生命周期
  - 通知栏构建（"AI Agent 运行中 · {模式}"）
  - `Map<String, AgentSession>` 会话管理

### T12.2 AgentSession 状态机
- [ ] `AgentSession.kt`：
  - 状态枚举：IDLE / LISTENING / RECORDING / STT_PROCESSING / LLM_CALLING / LLM_STREAMING / TTS_SYNTHESIZING / PLAYING
  - 状态转移方法 + 断言（防止非法跳转）
  - `activeRequestId`（AtomicReference，线程安全）
  - `onUserInput(requestId, text)`：若 requestId != activeRequestId → 取消旧请求 → 更新 activeRequestId → 触发 LLM

### T12.3 LlmPipelineNode.kt
- [ ] 调用 `OpenAILlmEngine`（llm_openai 插件中的原生层实现）
- [ ] OkHttp streaming，逐行解析 SSE
- [ ] `cancel()`：`okHttpCall.cancel()`
- [ ] 回调：通过 `AgentSession` → `EventChannel` 推送 LLM 事件
- [ ] DB 写入：`onChunk` → `appendMessageContent`；`onDone` → `updateMessageStatus('done')`；`cancel()` → `updateMessageStatus('cancelled')`

### T12.4 TtsPipelineNode.kt
- [ ] 调用 `AzureTtsEngine`（tts_azure 插件）
- [ ] AudioTrack 或 MediaPlayer 播放
- [ ] 字边界回调（Azure Word Boundary Event）
- [ ] `cancel()`：停止 AudioTrack
- [ ] 回调：通过 AgentSession → EventChannel 推送 TTS 事件

### T12.5 SttPipelineNode.kt
- [ ] 调用 `AzureSttEngine`（stt_azure 插件）
- [ ] VAD 集成（先用简单能量阈值，后可换 Silero）
- [ ] `onSttFinalResult`：**在此生成新的 UUID requestId** → 调用 `AgentSession.onUserInput(requestId, text)` → 发送 `onSttFinalResult(sessionId, requestId, text)` 给 Flutter

### T12.6 VadEngine.kt
- [ ] 基于 RMS 能量阈值的 VAD
- [ ] 参数：speechThreshold（能量阈值），silenceThresholdMs（静音持续时间 800ms）
- [ ] 事件：speechStart / speechEnd

---

## Phase 13：agent_runtime iOS 实现

### T13.1 基础框架
- [ ] `Info.plist`（主工程）：添加 `UIBackgroundModes: [audio]`
- [ ] `AgentRuntimePlugin.swift`：FlutterPlugin 入口，注册 Pigeon
- [ ] `AgentRuntimeManager.swift`：
  - `AVAudioSession` 配置（`.playAndRecord`, `.allowBluetooth`, 后台保活）
  - `Map<String, AgentSession>` 会话管理

### T13.2 AgentSession.swift
- [ ] 状态机（同 Android）
- [ ] `activeRequestId`（Atomic 通过 DispatchQueue 保护）
- [ ] `onUserInput(requestId, text)`

### T13.3 Pipeline 节点（Swift 实现）
- [ ] `LlmPipelineNode.swift`（URLSession，async/await + AsyncStream）
- [ ] `TtsPipelineNode.swift`（AVAudioPlayer）
- [ ] `SttPipelineNode.swift`（Azure Speech SDK for iOS）
- [ ] `VadEngine.swift`（AVAudioEngine + RMS）

---

## Phase 14：stt_azure & tts_azure 插件实现

### T14.1 stt_azure Android
- [ ] `build.gradle`：添加 Azure Speech SDK AAR 依赖
- [ ] `AzureSttEngine.kt`：
  - `SpeechRecognizer` 初始化（subscriptionKey, region）
  - `startContinuousRecognition()`
  - 回调：recognizing（partialResult）/ recognized（finalResult）/ canceled（error）
- [ ] `SttAzurePlugin.kt`：Pigeon HostApi 实现（供快速测试页使用）

### T14.2 stt_azure iOS
- [ ] `stt_azure.podspec`：引入 `MicrosoftCognitiveServicesSpeech` Pod
- [ ] `AzureSttEngine.swift`：SPXSpeechRecognizer 封装
- [ ] `SttAzurePlugin.swift`

### T14.3 tts_azure Android
- [ ] `AzureTtsEngine.kt`：SpeechSynthesizer 封装，支持 SSML，流式播放
- [ ] 字边界事件（WordBoundary）映射到 `onTtsPlaybackProgress`

### T14.4 tts_azure iOS
- [ ] `AzureTtsEngine.swift`：SPXSpeechSynthesizer 封装

---

## Phase 15：Mock 模式与端到端联调

### T15.1 Mock AgentRuntime（开发调试用）
- [ ] `lib/runtime/mock_agent_runtime.dart`：
  - 实现 `AgentRuntimeApi` 接口（不走 Native）
  - `sendText` 后模拟完整事件序列（LlmRequestStart → Chunk × 5 → LlmDone → TtsSynthesisStart → TtsPlaybackStart → TtsPlaybackDone）
  - 开关：`const bool kUseMockRuntime = bool.fromEnvironment('MOCK_RUNTIME', defaultValue: false)`
- [ ] 验证 UI 所有状态和动画效果

### T15.2 集成测试清单
- [ ] **文本模式**：输入文字 → UUID 生成 → LLM 流式 → 消息气泡逐字显示 → TTS 播报 → 音波动画
- [ ] **短语音模式**：按住 → 波形动画 → 松手 → STT → 用户气泡出现 → AI 回答 → 播报
- [ ] **通话模式**：进入通话 → 自动开始监听 → 说话 → AI 回答 → 自动循环
- [ ] **打断机制**：通话中说话打断 TTS → 旧消息标记 cancelled → 新消息开始流式
- [ ] **主题切换**：三种主题实时切换，重启后保持
- [ ] **后台运行**（Android）：Home 键后通话模式继续，回来后状态同步
- [ ] **错误场景**：断网 → 错误气泡 → 重试按钮可用

---

## 依赖关系图

```
T0（脚手架）
  └─ T1（ai_plugin_interface）
        ├─ T2（local_db）
        │    └─ T3（UI Shell）
        │         ├─ T4（Services）─────────┐
        │         ├─ T5（Agents）───────────┤
        │         ├─ T6（Chat UI）──────────┤── T11（Pigeon接口）
        │         ├─ T7（Translate UI）─────┤        └─ T12（Android）
        │         └─ T8（Settings）─────────┘        └─ T13（iOS）
        ├─ T9（llm_openai）─────────────── T12.3
        ├─ T10（translation_deepl）──────── T7
        └─ T14（stt/tts plugins）──────── T12.5, T13.3
                                T15（联调）依赖所有前序
```

---

## 当前优先级

按可见价值排序，建议的启动顺序：

1. **T0 + T3**（先跑起来，能看到 3-tab 界面）
2. **T1 + T4 + T8**（Services + Settings，基本可用）
3. **T5**（Agents 创建）
4. **T9 + T11 Dart 桥接 + T6 Chat UI with Mock**（最有价值的演示路径）
5. **T2 local_db**（持久化）
6. **T12 Android 原生**（真正后台运行）
7. **T14 STT/TTS 插件**（完整语音链路）
