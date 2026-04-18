# 架构设计文档

**项目名称**：AI Agent Client
**版本**：v1.8
**日期**：2026-03-13
**变更**：v1.8 — 完善 AgentRuntimeEventApi 事件体系：STT 拆分为 ListeningStarted/VadSpeechStart/VadSpeechEnd/PartialResult/FinalResult/ListeningStopped/Error 七类；LLM 新增 Thinking/FirstToken/ToolCallStart/ToolCallArguments/ToolCallResult/Done/Cancelled/Error；TTS 拆分为 SynthesisStart/SynthesisReady/PlaybackStart/PlaybackProgress/PlaybackDone/PlaybackInterrupted/Error；新增 §3.4 完整事件参考（时序图 + UI 效果 + 状态机对应关系）；明确 requestId 生成路径（文本模式 Flutter 生成，短语音/通话模式原生 STT 层生成）

---

## 1. 整体架构

### 1.1 核心设计原则：Agent 执行引擎在原生层

**Agent 必须能在 Flutter 脱离（退到后台或被系统回收）时独立运行**，因此：

- **Agent 执行引擎**（STT→LLM→TTS 管线、VAD、状态机、会话管理）全部运行在原生 Service 中
- **Flutter 层**只做 UI 渲染和用户交互，通过 EventChannel 接收原生推送的事件来更新界面
- **命令下行**：Flutter → 原生，通过 Pigeon MethodChannel（startSession / sendText / interrupt / stop）
- **事件上行**：原生 → Flutter，通过 EventChannel 推送（stateChanged / messageReceived / sttResult / error）

### 1.2 分层架构

```
┌─────────────────────────────────────────────────────────────────┐
│                  Flutter UI Layer（纯展示层）                     │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ AgentPanel   │  │ Services     │  │  Settings            │  │
│  │ Screen [主页] │  │ Screen       │  │  Screen              │  │
│  └──────┬───────┘  └──────────────┘  └──────────────────────┘  │
│         │                                                        │
│  ┌──────▼────────────────────────────┐                          │
│  │  ChatAgentScreen / TranslateAgentScreen                      │
│  │  （UI 镜像原生 AgentSession 状态，无业务逻辑）                  │
│  └───────────────────────────────────┘                          │
│     Flutter Widgets + Riverpod（仅做状态镜像，不做业务编排）        │
└──────────────┬──────────────────────────────┬───────────────────┘
               │ 命令下行（Pigeon）             │ 事件上行（EventChannel）
               ▼                              ▲
┌─────────────────────────────────────────────────────────────────┐
│         agent_runtime 插件 ★ 核心执行层（新增）                   │
│                                                                 │
│  Android: AgentRuntimeService（ForegroundService）               │
│  iOS:     AgentRuntimeManager（Background Audio Session）        │
│                                                                 │
│  每个 AgentSession 内部运行完整管线：                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  VAD → STT Plugin → [MCP Tool Calls] → LLM Plugin → TTS │  │
│  │                      Plugin → Audio Output               │  │
│  │                                                          │  │
│  │  状态机（IDLE / LISTENING / STT / LLM / TTS / PLAYING）   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  AgentRuntimeChannel（Pigeon 接口）:                             │
│    ← 接收: startSession / stopSession / sendText                 │
│            interrupt / setCallMode / updateConfig               │
│    → 推送: AgentEvent（state / message / stt / tts / error）     │
└──────────────────────┬──────────────────────────────────────────┘
                       │ 调用各能力插件的原生 API
┌──────────────────────▼──────────────────────────────────────────┐
│              local_plugins/（能力插件集）                          │
│                                                                 │
│  ai_plugin_interface/  ← 共享 Dart 抽象接口 + Pigeon 消息定义     │
│                                                                 │
│  STT 插件                TTS 插件               LLM 插件         │
│  ┌───────────┐           ┌───────────┐          ┌───────────┐  │
│  │ stt_azure │           │ tts_azure │          │llm_openai │  │
│  │ stt_aliyun│           │tts_aliyun │          │(OpenAI    │  │
│  │ stt_google│           │tts_google │          │compatible │  │
│  │stt_doubao │           │tts_doubao │          │+ MCP内置) │  │
│  └───────────┘           └───────────┘          ├───────────┤  │
│                                                  │ llm_coze  │  │
│  STS 插件                                        └───────────┘  │
│  ┌───────────┐                                                   │
│  │sts_volcengine │  （端到端语音，agent_runtime 直接调度，无中间层）     │
│  └───────────┘                                                   │
│  Translation 插件（纯 Dart HTTP）                                  │
│  ┌──────────────────┬──────────────────┬──────────────────┐    │
│  │ translation_deepl│translation_google│translation_aliyun│    │
│  └──────────────────┴──────────────────┴──────────────────┘    │
└─────────────────────────┬───────────────────────────────────────┘
                          │ 原生 SDK / HTTP
┌─────────────────────────▼───────────────────────────────────────┐
│               External AI Services（外部服务）                    │
│  Azure │ Google │ Aliyun │ Doubao │ OpenAI │ Coze │ DeepL ...  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 后台服务架构说明

后台 Service **由 `agent_runtime` 插件自己声明和管理**，不再挂在主 App 下：

- **Android**：`agent_runtime` 的 `AgentRuntimeService` 是 `ForegroundService`，在插件的 `AndroidManifest.xml` 中声明；主 App 通过 `startForegroundService()` 启动，之后即使 Flutter Engine 销毁，Service 继续运行
- **iOS**：`agent_runtime` 持有 `AVAudioSession`（Background Audio）+ `BGTaskScheduler`；利用 VoIP push 或后台音频保活，确保通话/同传模式可后台运行
- 各 STT/TTS 插件的原生实现被 `AgentRuntimeService` **直接实例化并调用**，无需各自单独绑定 Service

---

## 2. 项目目录结构

```
ai_agent_client/
├── .env                               # 环境配置（gitignore）
├── .env.example                       # 配置示例（提交 git）
├── pubspec.yaml
│
├── local_plugins/                     # 本地插件集 ★
│   │
│   ├── agent_runtime/                 # ★ Agent 执行引擎插件（核心，新增）
│   │   ├── pubspec.yaml
│   │   ├── pigeons/
│   │   │   └── agent_runtime_messages.dart  # Pigeon 源定义（命令 + 事件）
│   │   ├── lib/
│   │   │   ├── agent_runtime.dart           # 公开 API
│   │   │   └── src/
│   │   │       ├── agent_runtime_channel.dart   # Pigeon 生成的 Dart 桥接
│   │   │       └── agent_session_state.dart     # AgentState / AgentEvent 枚举（Dart 侧镜像）
│   │   ├── android/
│   │   │   └── src/main/kotlin/.../
│   │   │       ├── AgentRuntimePlugin.kt        # FlutterPlugin 入口
│   │   │       ├── AgentRuntimeService.kt       # ForegroundService（后台保活）
│   │   │       ├── AgentSession.kt              # 单个 Agent 会话状态机 + 管线编排
│   │   │       ├── pipeline/
│   │   │       │   ├── VadEngine.kt             # VAD（静音检测）
│   │   │       │   ├── SttPipelineNode.kt       # 调用 STT 插件原生实现
│   │   │       │   ├── LlmPipelineNode.kt       # 调用 LLM 插件原生实现（含 MCP）
│   │   │       │   └── TtsPipelineNode.kt       # 调用 TTS 插件原生实现
│   │   │       └── AndroidManifest.xml          # 声明 AgentRuntimeService + 权限
│   │   └── ios/
│   │       ├── agent_runtime.podspec
│   │       └── Classes/
│   │           ├── AgentRuntimePlugin.swift     # FlutterPlugin 入口
│   │           ├── AgentRuntimeManager.swift    # AVAudioSession + BGTaskScheduler 管理
│   │           ├── AgentSession.swift           # 单个 Agent 会话状态机 + 管线编排
│   │           └── pipeline/
│   │               ├── VadEngine.swift
│   │               ├── SttPipelineNode.swift
│   │               ├── LlmPipelineNode.swift
│   │               └── TtsPipelineNode.swift
│   │
│   ├── local_db/                      # ★ 本地数据库插件（App 数据中心）
│   │   ├── pubspec.yaml
│   │   ├── pigeons/
│   │   │   └── local_db_messages.dart       # Pigeon 源定义（CRUD 接口）
│   │   ├── lib/
│   │   │   ├── local_db.dart                # 公开 API
│   │   │   └── src/
│   │   │       └── local_db_channel.dart    # Pigeon 生成的 Dart 桥接
│   │   ├── android/
│   │   │   └── src/main/kotlin/.../
│   │   │       ├── LocalDbPlugin.kt         # FlutterPlugin 入口
│   │   │       ├── AppDatabase.kt           # Room Database 定义
│   │   │       ├── dao/
│   │   │       │   ├── ServiceConfigDao.kt
│   │   │       │   ├── AgentDao.kt
│   │   │       │   ├── MessageDao.kt
│   │   │       │   └── McpServerDao.kt
│   │   │       └── entity/
│   │   │           ├── ServiceConfigEntity.kt
│   │   │           ├── AgentEntity.kt
│   │   │           ├── MessageEntity.kt
│   │   │           └── McpServerEntity.kt
│   │   └── ios/
│   │       ├── local_db.podspec
│   │       └── Classes/
│   │           ├── LocalDbPlugin.swift      # FlutterPlugin 入口
│   │           ├── AppDatabase.swift        # Core Data / GRDB 封装
│   │           └── dao/
│   │               ├── ServiceConfigDao.swift
│   │               ├── AgentDao.swift
│   │               ├── MessageDao.swift
│   │               └── McpServerDao.swift
│   │
│   ├── ai_plugin_interface/           # 共享抽象接口 + Pigeon 消息定义（纯 Dart）
│   │
│   ├── stt_azure/                     # Azure STT（Kotlin + Swift 原生实现）
│   ├── stt_aliyun/                    # 阿里云 STT
│   ├── stt_google/                    # Google STT
│   ├── stt_doubao/                    # 豆包 STT
│   │
│   ├── tts_azure/                     # Azure TTS
│   ├── tts_aliyun/                    # 阿里云 TTS
│   ├── tts_google/                    # Google TTS
│   ├── tts_doubao/                    # 豆包 TTS
│   │
│   ├── llm_openai/                    # OpenAI-compatible LLM + MCP 内置
│   ├── llm_coze/                      # Coze 平台（独立 API）
│   │
│   ├── sts_volcengine/                    # 火山引擎 STS（端到端，agent_runtime 直接调度）
│   │
│   ├── translation_deepl/             # DeepL 翻译（纯 Dart HTTP）
│   ├── translation_google/            # Google 翻译（纯 Dart HTTP）
│   └── translation_aliyun/            # 阿里云翻译（纯 Dart HTTP）
│
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml        # 仅声明主 Activity，Service 由 agent_runtime 插件声明
│
├── ios/
│   └── Runner/
│       └── Info.plist                 # Background Modes: audio（由 agent_runtime 使用）
│
└── lib/
    ├── main.dart
    ├── app.dart                       # App Widget + go_router 路由
    │
    ├── core/
    │   ├── config/
    │   │   ├── app_config.dart        # 从 .env 读取所有 API Key
    │   │   └── env_keys.dart
    │   ├── errors/
    │   │   └── app_exception.dart
    │   └── utils/
    │       └── logger.dart
    │
    ├── registry/                      # Service Library + Provider Registry（配置层）
    │   ├── service_library.dart       # ServiceConfig 数据模型 + 持久化
    │   ├── service_library_notifier.dart
    │   ├── stt_registry.dart
    │   ├── tts_registry.dart
    │   ├── llm_registry.dart
    │   └── translation_registry.dart
    │
    ├── agents/                        # Agent 配置模型（无业务逻辑，仅数据）
    │   ├── agent_config.dart          # AgentConfig 基类 + AgentType 枚举
    │   ├── agent_list_notifier.dart   # Riverpod StateNotifier（持久化 Agent 列表）
    │   ├── chat_agent_config.dart
    │   └── translate_agent_config.dart
    │
    ├── runtime/                       # Flutter 侧 Agent 运行时桥接（薄层）
    │   ├── agent_runtime_bridge.dart  # 封装 agent_runtime 插件 Pigeon 调用
    │   ├── agent_session_provider.dart # Riverpod：监听 EventChannel 事件 → UI 状态
    │   └── agent_event.dart           # AgentEvent / AgentState（Dart 侧镜像）
    │
    ├── models/
    │   ├── message.dart
    │   ├── stt_result.dart
    │   └── translation_result.dart
    │
    ├── features/                      # UI 功能模块（3-tab 导航）
    │   ├── agents/                        # Tab 1: Agent 管理面板
    │   │   ├── screens/
    │   │   │   └── agent_panel_screen.dart
    │   │   ├── widgets/
    │   │   │   ├── agent_card.dart
    │   │   │   ├── add_agent_modal.dart
    │   │   │   └── mcp_config_screen.dart   # MCP 独立配置页（本地工具 + 远程服务器）
    │   │   └── providers/
    │   │       └── agent_list_provider.dart
    │   │
    │   ├── chat_agent/                    # Chat Agent 运行界面（UI 镜像原生状态）
    │   │   ├── screens/
    │   │   │   └── chat_agent_screen.dart
    │   │   ├── widgets/
    │   │   │   ├── message_bubble.dart
    │   │   │   ├── multimodal_input_bar.dart  # 统一输入栏（短语音/文字/通话三态）
    │   │   │   └── audio_visualizer.dart
    │   │   └── providers/
    │   │       └── chat_agent_provider.dart   # 仅做 UI 状态映射，不编排业务
    │   │
    │   ├── translate_agent/
    │   │   ├── screens/
    │   │   │   └── translate_agent_screen.dart
    │   │   ├── widgets/
    │   │   │   ├── language_bar.dart
    │   │   │   ├── translation_result_card.dart
    │   │   │   ├── multimodal_input_bar.dart  # 复用同一组件
    │   │   │   └── call_mode_bar.dart
    │   │   └── providers/
    │   │       └── translate_agent_provider.dart
    │   │
    │   ├── services/                      # Tab 2: 服务库管理
    │   │   ├── screens/
    │   │   │   └── services_screen.dart
    │   │   ├── widgets/
    │   │   │   ├── service_card.dart
    │   │   │   ├── add_service_modal.dart
    │   │   │   ├── vendor_grid.dart
    │   │   │   └── quick_test_card.dart
    │   │   └── providers/
    │   │       └── service_library_provider.dart
    │   │
    │   └── settings/                      # Tab 3: 全局参数配置
    │       ├── screens/
    │       │   └── settings_screen.dart
    │       └── providers/
    │           └── settings_provider.dart
    │
    └── shared/
        ├── widgets/
        │   ├── loading_indicator.dart
        │   └── error_display.dart
        └── themes/
            └── app_theme.dart
```

---

## 3. agent_runtime 插件设计

### 3.1 Pigeon 接口定义

```dart
// local_plugins/agent_runtime/pigeons/agent_runtime_messages.dart

// ─── 命令接口（Flutter → Native）───────────────────────────────
@HostApi()
abstract class AgentRuntimeApi {
  // 启动一个 Agent 会话（传入完整配置 JSON）
  void startSession(AgentSessionConfig config);

  // 停止会话（释放资源，后台服务继续运行以备下次快速启动）
  void stopSession(String sessionId);

  // 文字输入（文本模式）；requestId 由 Flutter 生成的 UUID，用于多轮打断追踪
  void sendText(String sessionId, String requestId, String text);

  // 打断当前 TTS 播放，恢复监听（通话模式中用户主动打断）
  void interrupt(String sessionId);

  // 切换输入模式（call / voice / text）
  void setInputMode(String sessionId, String mode);

  // 前台/后台切换通知（供 Service 决策通知栏展示）
  void notifyAppForeground(bool isForeground);
}

// ─── 事件接口（Native → Flutter，EventChannel 推送）─────────────
@FlutterApi()
abstract class AgentRuntimeEventApi {

  // ── AgentSession 整体状态 ──────────────────────────────────────
  // state: IDLE | LISTENING | RECORDING | STT_PROCESSING |
  //        LLM_CALLING | LLM_STREAMING | TTS_SYNTHESIZING | PLAYING
  void onStateChanged(String sessionId, String state);

  // 某个请求被新请求抢占取消（"最新优先"策略触发）
  void onRequestCancelled(String sessionId, String requestId);

  // ── STT 事件 ──────────────────────────────────────────────────
  // 麦克风激活，开始监听（进入 LISTENING 状态）
  void onSttListeningStarted(String sessionId);

  // VAD 检测到用户开始说话（进入 RECORDING 状态）
  void onSttVadSpeechStart(String sessionId);

  // VAD 检测到用户停止说话，开始向 STT 服务发送音频（进入 STT_PROCESSING）
  void onSttVadSpeechEnd(String sessionId);

  // 识别中间结果（流式实时显示，isFinal=false）
  void onSttPartialResult(String sessionId, String text);

  // 识别完成一句话（isFinal=true）；requestId 由原生生成，作为本轮请求唯一 ID
  // 短语音/通话模式下，此事件会同时触发 AgentSession.onUserInput(requestId, text)
  void onSttFinalResult(String sessionId, String requestId, String text);

  // 停止监听（麦克风释放）
  void onSttListeningStopped(String sessionId);

  // STT 错误（errorCode: NO_SPEECH / NETWORK_ERROR / AUTH_ERROR / TIMEOUT）
  void onSttError(String sessionId, String errorCode, String message);

  // ── LLM / AI 事件 ─────────────────────────────────────────────
  // 开始向 LLM 发起请求
  void onLlmRequestStart(String sessionId, String requestId);

  // 模型思考中（仅支持 thinking 模式的模型，如 Claude extended thinking）
  void onLlmThinking(String sessionId, String requestId, String thinkingChunk, bool isDone);

  // 第一个 token 到达（可用于计算首字时延 TTFT）
  void onLlmFirstToken(String sessionId, String requestId);

  // 流式文字回复片段；isDone=true 表示本轮回复结束
  void onLlmChunk(String sessionId, String requestId, String chunk, bool isDone);

  // MCP 工具调用开始（callId 为工具调用唯一 ID，用于多工具并发区分）
  void onLlmToolCallStart(String sessionId, String requestId, String callId, String toolName);

  // MCP 工具调用参数（流式，可选；isDone=true 表示参数接收完毕，MCP 开始执行）
  void onLlmToolCallArguments(String sessionId, String requestId, String callId,
                               String argumentsChunk, bool isDone);

  // MCP 工具执行结果返回（result 为工具返回的 JSON 字符串）
  void onLlmToolCallResult(String sessionId, String requestId, String callId, String result);

  // LLM 请求正常完成（所有工具调用也已结束）
  void onLlmDone(String sessionId, String requestId);

  // LLM 请求被取消（由新请求抢占触发）
  void onLlmCancelled(String sessionId, String requestId);

  // LLM 错误（errorCode: NETWORK_ERROR / AUTH_ERROR / RATE_LIMIT / CONTEXT_TOO_LONG / TIMEOUT）
  void onLlmError(String sessionId, String requestId, String errorCode, String message);

  // ── TTS 事件 ──────────────────────────────────────────────────
  // 开始向 TTS 服务发起合成请求
  void onTtsSynthesisStart(String sessionId, String requestId);

  // TTS 合成完成，音频数据就绪（流式 TTS 下首帧到达即触发，可提前开始播放）
  void onTtsSynthesisReady(String sessionId, String requestId);

  // 开始播报（AudioTrack / AVAudioPlayer 开始输出）
  void onTtsPlaybackStart(String sessionId, String requestId);

  // 播报进度（字边界，可用于 UI 高亮当前朗读字符；charIndex 为字符位置）
  void onTtsPlaybackProgress(String sessionId, String requestId, int charIndex, int charLength);

  // 播报正常结束
  void onTtsPlaybackDone(String sessionId, String requestId);

  // 播报被打断（用户触发 interrupt() 或新请求到来）
  void onTtsPlaybackInterrupted(String sessionId, String requestId);

  // TTS 错误（errorCode: NETWORK_ERROR / AUTH_ERROR / SYNTHESIS_FAILED / AUDIO_FOCUS_LOST）
  void onTtsError(String sessionId, String requestId, String errorCode, String message);
}

// ─── 配置数据类 ─────────────────────────────────────────────────
class AgentSessionConfig {
  final String sessionId;
  final String agentType;        // "chat" | "translate" | "sts"
  final String llmConfigJson;    // ServiceConfig 序列化 JSON
  final String? sttConfigJson;
  final String? ttsConfigJson;
  final String? translationConfigJson;
  final String? mcpConfigJson;   // McpServerConfig[] JSON
  final String? systemPrompt;
  final String defaultInputMode; // "voice" | "text" | "call"
}
```

### 3.2 Android AgentRuntimeService 生命周期

```
App 启动
  └─ AgentRuntimePlugin.onAttachedToEngine()
        └─ 绑定 AgentRuntimeService（如未启动则先 startForegroundService）

用户打开 Agent → Flutter 调用 startSession(config)
  └─ AgentRuntimeService.startSession()
        └─ 创建 AgentSession（状态机初始化 → IDLE）
              └─ 加载 STT/TTS/LLM 插件原生实例（通过插件 Package 直接实例化，无 Channel 开销）

Flutter 退到后台 / 被系统杀死
  └─ AgentRuntimeService 继续运行（ForegroundService 保活）
        └─ 通知栏显示："AI Agent 运行中 · 通话模式"
              └─ 状态机继续驱动：VAD → STT → LLM → TTS → 循环

App 重新启动 / 回到前台
  └─ AgentRuntimePlugin.onAttachedToEngine()
        └─ 重新注册 EventChannel
              └─ AgentRuntimeService 将当前所有 Session 状态推送给 Flutter（状态同步）
```

### 3.3 AgentSession 状态机

```
                ┌─────────────────────────────────────────────────────┐
                │              AgentSession 状态机                      │
                └─────────────────────────────────────────────────────┘

IDLE ──[startCall / VAD激活]──→ LISTENING
  │
  ├─ LISTENING ──[VAD检测到语音]──→ RECORDING
  │      └─ RECORDING ──[静音超过阈值]──→ STT_PROCESSING
  │              └─ STT_PROCESSING ──[识别完成]──→ LLM_CALLING
  │
  ├─ LLM_CALLING ──[首个 token]──→ LLM_STREAMING
  │      └─ LLM_STREAMING ──[done + TTS]──→ TTS_SYNTHESIZING
  │              └─ TTS_SYNTHESIZING ──[开始播放]──→ PLAYING
  │                      └─ PLAYING ──[播放完毕]──→ LISTENING（通话模式自动循环）
  │                                              └─→ IDLE（短语音模式）
  │
  ├─ ANY ──[interrupt()]──→ LISTENING（打断 TTS，立刻恢复监听）
  └─ ANY ──[stopSession()]──→ IDLE（释放音频资源）
```

### 3.4 完整事件类型参考

下表按业务流程顺序列出所有事件，说明触发时机、驱动的 UI 效果和业务行为。

#### AgentSession 整体状态事件

| 事件 | 触发时机 | UI 效果 / 业务行为 |
|------|---------|-----------------|
| `onStateChanged(state)` | 状态机发生任何转移 | 底部状态栏图标更新；LISTENING 显示波形，PLAYING 显示音波动画 |
| `onRequestCancelled(requestId)` | 新请求抢占旧请求 | 将旧请求消息气泡标记为"已取消"灰色样式 |

#### STT 事件流（完整时序）

```
onSttListeningStarted
  └─ [用户开始说话]
       onSttVadSpeechStart
         └─ onSttPartialResult × N  （实时显示识别中间字）
              └─ [用户停止说话]
                   onSttVadSpeechEnd
                     └─ onSttFinalResult（requestId 在此生成，触发 LLM 请求）
                          └─ onSttListeningStopped（仅短语音/文本模式，通话模式保持监听）
```

| 事件 | 触发时机 | UI 效果 / 业务行为 |
|------|---------|-----------------|
| `onSttListeningStarted` | 麦克风激活 | 显示麦克风激活图标，输入区显示"正在监听…" |
| `onSttVadSpeechStart` | VAD 检测到声音 | 显示语音波形动画，输入区背景高亮 |
| `onSttVadSpeechEnd` | VAD 检测到静音 | 波形停止，显示"识别中…"spinner |
| `onSttPartialResult(text)` | STT 返回中间结果 | 输入区实时显示识别文字（灰色斜体，可变动） |
| `onSttFinalResult(requestId, text)` | STT `isFinal=true` | 输入区文字确定（变黑），用户消息气泡出现；**同时触发 LLM 请求** |
| `onSttListeningStopped` | 麦克风释放 | 麦克风图标恢复默认 |
| `onSttError(errorCode, message)` | STT 服务出错 | Toast 提示错误信息，状态回 IDLE；`NO_SPEECH` 时静默重置 |

#### LLM / AI 事件流（完整时序）

```
onLlmRequestStart
  └─ [支持 thinking 模式时] onLlmThinking × N
       onLlmFirstToken
         └─ onLlmChunk × N
              │  [若有工具调用]
              ├─ onLlmToolCallStart
              │    └─ onLlmToolCallArguments × N
              │         └─ onLlmToolCallResult
              │              └─ [继续 onLlmChunk，整合工具结果后继续生成]
              └─ onLlmChunk(isDone=true) → onLlmDone → [触发 TTS]
```

| 事件 | 触发时机 | UI 效果 / 业务行为 |
|------|---------|-----------------|
| `onLlmRequestStart(requestId)` | 开始发起 LLM HTTP 请求 | AI 消息气泡出现，显示"…"加载动画 |
| `onLlmThinking(chunk, isDone)` | 模型 thinking 片段（Claude extended thinking 等）| 折叠的"思考过程"区域流式显示（可展开） |
| `onLlmFirstToken(requestId)` | 首个 token 到达 | 结束加载动画，开始流式显示文字；可记录 TTFT 指标 |
| `onLlmChunk(chunk, isDone)` | 每个流式 token | 文字逐字追加到消息气泡 |
| `onLlmToolCallStart(callId, toolName)` | LLM 决定调用工具 | 消息气泡内插入工具调用卡片，显示工具名和"执行中…" |
| `onLlmToolCallArguments(callId, chunk, isDone)` | 工具参数流式到达 | 工具卡片展示参数（调试/展开视图） |
| `onLlmToolCallResult(callId, result)` | MCP 工具返回结果 | 工具卡片显示结果摘要，状态变为"✓ 完成" |
| `onLlmDone(requestId)` | 所有内容生成完毕 | 消息气泡完成状态；**触发 TTS 合成**（如启用） |
| `onLlmCancelled(requestId)` | 被新请求抢占 | 消息气泡标记"已取消"；TTS 不触发 |
| `onLlmError(requestId, errorCode, message)` | LLM 服务出错 | 消息气泡显示错误提示，提供"重试"按钮 |

#### TTS 事件流（完整时序）

```
onTtsSynthesisStart
  └─ onTtsSynthesisReady（流式 TTS 首帧即触发，无需等全部合成完）
       onTtsPlaybackStart
         └─ onTtsPlaybackProgress × N（可选，字边界回调）
              └─ onTtsPlaybackDone（正常完成）
                   └─ 通话模式：→ onSttListeningStarted（自动循环）
              或 └─ onTtsPlaybackInterrupted（被打断）
```

| 事件 | 触发时机 | UI 效果 / 业务行为 |
|------|---------|-----------------|
| `onTtsSynthesisStart(requestId)` | 向 TTS 服务发起请求 | 消息气泡底部显示"合成中…"小图标 |
| `onTtsSynthesisReady(requestId)` | 首帧音频就绪 | 立即开始播放（流式 TTS 减少延迟） |
| `onTtsPlaybackStart(requestId)` | AudioTrack 开始输出 | 显示音波播放动画，打断按钮出现 |
| `onTtsPlaybackProgress(charIndex, charLength)` | 每个字边界回调 | 消息文字逐字高亮（卡拉 OK 效果，可选） |
| `onTtsPlaybackDone(requestId)` | 播放正常结束 | 音波动画停止；通话模式自动触发下一轮监听 |
| `onTtsPlaybackInterrupted(requestId)` | `interrupt()` 或新请求到来 | 立即停止音波动画，状态回 LISTENING |
| `onTtsError(requestId, errorCode, message)` | TTS 服务出错 | Toast 提示，跳过 TTS 直接回 LISTENING |

#### 事件与 AgentSession 状态机对应关系

```
IDLE
  ──[startSession / setInputMode(call)]──→ LISTENING
        [onSttListeningStarted]

LISTENING
  ──[VAD speech_start]──→ RECORDING
        [onSttVadSpeechStart]

RECORDING
  ──[VAD speech_end]──→ STT_PROCESSING
        [onSttVadSpeechEnd]
        [onSttPartialResult × N]

STT_PROCESSING
  ──[isFinal=true]──→ LLM_CALLING
        [onSttFinalResult]
        [onLlmRequestStart]

LLM_CALLING
  ──[first token]──→ LLM_STREAMING
        [onLlmFirstToken]
        [onLlmChunk × N]
        [onLlmToolCallStart / onLlmToolCallResult × N（可选）]

LLM_STREAMING
  ──[isDone=true]──→ TTS_SYNTHESIZING
        [onLlmDone]
        [onTtsSynthesisStart]
        [onTtsSynthesisReady]

TTS_SYNTHESIZING
  ──[首帧就绪]──→ PLAYING
        [onTtsPlaybackStart]
        [onTtsPlaybackProgress × N（可选）]

PLAYING
  ──[播放结束]──→ LISTENING（通话模式）或 IDLE（短语音）
        [onTtsPlaybackDone]

ANY ──[新 requestId 到来]──→ 取消当前，重入 LLM_CALLING
        [onRequestCancelled]  [onLlmCancelled]  [onTtsPlaybackInterrupted]
```

### 3.5 插件内部调用方式

`agent_runtime` 与 `stt_*` / `tts_*` / `llm_*` 插件的关系：

- **Android**：`AgentSession.kt` 通过 Kotlin 直接实例化各插件的 Engine 类（如 `AzureSttEngine`），**不走 Flutter MethodChannel**，避免线程切换开销
- **iOS**：同理，`AgentSession.swift` 直接实例化各插件的 Swift 类
- 各能力插件仍对外暴露 Flutter Plugin 接口（供服务快速测试页使用），但在 `agent_runtime` 内部直接调用原生层

```kotlin
// android/AgentSession.kt（示意）
class AgentSession(config: AgentSessionConfig) {
    private val sttEngine: SttEngine = when (config.sttVendor) {
        "azure"  -> AzureSttEngine(config.sttConfig)   // 直接 new，不走 Channel
        "aliyun" -> AliyunSttEngine(config.sttConfig)
        else     -> throw IllegalArgumentException("Unknown STT vendor")
    }
    private val llmEngine: LlmEngine = OpenAILlmEngine(config.llmConfig)
    private val ttsEngine: TtsEngine = AzureTtsEngine(config.ttsConfig)
    // ...状态机驱动管线
}
```

---

## 4. local_db 插件设计（本地数据库）

### 4.1 设计原则

- 数据库插件放在原生层（Android Room / iOS GRDB），原生 Service（`agent_runtime`）可以**直接访问**，无需经过 Flutter Channel，适合后台运行时持续写入消息
- Flutter 层通过 Pigeon 读写，用于 UI 展示和配置管理
- 采用 **SQLite** 作为底层存储，跨平台一致，数据文件与 App 生命周期绑定

### 4.2 数据库表结构

```sql
-- 服务配置表（对应 ServiceLibrary）
CREATE TABLE service_configs (
    id          TEXT PRIMARY KEY,   -- serviceId（用户命名）
    type        TEXT NOT NULL,      -- 'stt' | 'tts' | 'sts' | 'llm' | 'translation'
    vendor      TEXT NOT NULL,      -- 厂商标识
    name        TEXT NOT NULL,      -- 显示名称
    config_json TEXT NOT NULL,      -- 完整配置 JSON（含 apiKey 等，加密存储）
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

-- Agent 配置表
CREATE TABLE agents (
    id           TEXT PRIMARY KEY,  -- agentId（UUID）
    name         TEXT NOT NULL,
    type         TEXT NOT NULL,     -- 'chat' | 'translate' | 'sts'
    config_json  TEXT NOT NULL,     -- ChatAgentConfig / TranslateAgentConfig JSON
    sort_order   INTEGER NOT NULL DEFAULT 0,
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL
);

-- 消息表（聊天历史）
CREATE TABLE messages (
    id           TEXT PRIMARY KEY,  -- requestId（UUID，与 LLM 请求绑定）
    agent_id     TEXT NOT NULL REFERENCES agents(id),
    role         TEXT NOT NULL,     -- 'user' | 'assistant' | 'system'
    content      TEXT NOT NULL,     -- 消息文本（assistant 可为流式追加）
    status       TEXT NOT NULL,     -- 'pending' | 'streaming' | 'done' | 'cancelled' | 'error'
    created_at   INTEGER NOT NULL,
    updated_at   INTEGER NOT NULL
);
CREATE INDEX idx_messages_agent ON messages(agent_id, created_at);

-- MCP 服务器配置表
CREATE TABLE mcp_servers (
    id           TEXT PRIMARY KEY,
    name         TEXT NOT NULL,
    url          TEXT NOT NULL,
    transport    TEXT NOT NULL,     -- 'sse' | 'http'
    headers_json TEXT,              -- Authorization 等
    enabled_tools_json TEXT,        -- 已勾选工具 ID 列表
    created_at   INTEGER NOT NULL
);
```

### 4.3 消息写入流程（由 agent_runtime 原生直接写库）

```
用户发送（sendText with requestId）
  └─ AgentSession 原生
        ├─ INSERT messages(id=requestId, role='user', status='done')
        ├─ INSERT messages(id=responseId, role='assistant', status='pending')
        │
        └─ LLM 流式返回
              ├─ onChunk → UPDATE messages SET content=content||chunk, status='streaming'
              └─ onDone  → UPDATE messages SET status='done'

用户触发打断（新 requestId 到来）
  └─ AgentSession 原生
        └─ UPDATE messages SET status='cancelled' WHERE id=被取消的responseId
```

Flutter 通过 Pigeon 查询消息列表，展示 UI（不直接写库，只读 + 监听变化事件）。

---

## 5. local_plugins 能力插件包结构

### 5.1 ai_plugin_interface（共享接口包）

```
local_plugins/ai_plugin_interface/
├── pubspec.yaml               # 纯 Dart 包，无 flutter plugin 声明
└── lib/
    ├── ai_plugin_interface.dart   # 统一导出
    └── src/
        ├── interfaces/
        │   ├── stt_provider.dart       # SttProvider 抽象类
        │   ├── tts_provider.dart       # TtsProvider 抽象类
        │   ├── llm_provider.dart       # LlmProvider 抽象类
        │   └── translation_provider.dart
        ├── models/
        │   ├── stt_config.dart         # SttConfig（语言、采样率等）
        │   ├── stt_result.dart
        │   ├── tts_request.dart
        │   ├── llm_message.dart
        │   ├── llm_config.dart
        │   └── translation_result.dart
        ├── pigeon/                     # Pigeon 消息定义（原生插件共用）
        │   ├── stt_messages.dart
        │   ├── tts_messages.dart
        │   └── llm_messages.dart
        └── errors/
            └── plugin_exception.dart
```

### 5.2 单个厂商插件包结构（以 stt_azure 为例）

```
local_plugins/stt_azure/
├── pubspec.yaml
├── lib/
│   ├── stt_azure.dart                 # 公开 API，导出 SttAzurePlugin
│   └── src/
│       ├── stt_azure_plugin.dart      # 实现 SttProvider 接口
│       └── pigeon/
│           └── stt_azure_api.g.dart   # Pigeon 生成（勿手改）
├── pigeons/
│   └── stt_azure_messages.dart        # Pigeon 源定义（手写）
├── android/
│   ├── build.gradle                   # 引入 Azure Speech SDK AAR
│   └── src/main/kotlin/com/yourcompany/stt_azure/
│       ├── SttAzurePlugin.kt          # FlutterPlugin 入口 + Pigeon HostApi 实现
│       └── AzureSttEngine.kt          # Azure SDK 封装
└── ios/
    ├── stt_azure.podspec              # 引入 MicrosoftCognitiveServicesSpeech Pod
    └── Classes/
        ├── SttAzurePlugin.swift       # FlutterPlugin 入口 + Pigeon HostApi 实现
        └── AzureSttEngine.swift       # Azure SDK 封装
```

### 5.3 翻译插件包结构（纯 Dart，以 translation_deepl 为例）

```
local_plugins/translation_deepl/
├── pubspec.yaml               # 纯 Dart 包（无 flutter plugin 声明，无原生代码）
└── lib/
    ├── translation_deepl.dart
    └── src/
        └── deepl_translation_provider.dart  # 实现 TranslationProvider 接口（HTTP）
```

---

## 6. UI 界面设计

### 6.1 底部导航结构（3-tab）

```
App（底部 BottomNavigationBar）
├── 🤖 Agents     → AgentPanelScreen（Agent 管理面板）[默认 Tab]
├── 🧪 Services   → ServicesScreen（服务库管理）
└── ⚙️ Settings   → SettingsScreen（全局参数配置）
```

Agent 详细页面（从 AgentPanelScreen 进入，无底部 Tab）：
```
AgentPanelScreen
├── → ChatAgentScreen（对话 Agent 运行界面）
└── → TranslateAgentScreen（翻译 Agent 运行界面）
```

### 6.2 AgentPanelScreen（Agent 管理面板，首页）

```
┌───────────────────────────────────────┐
│  Agents                         [+]   │  ← FAB 添加新 Agent
├───────────────────────────────────────┤
│  ┌───────────────────┐ ┌───────────────────┐
│  │▌ GPT助手          │ │▌ 翻译官          │
│  │  Chat Agent       │ │  Translate Agent  │
│  │  LLM: GPT-4o      │ │  LLM: DeepL       │
│  │  STT: Azure       │ │  STT: Aliyun      │
│  │  TTS: Azure       │ │  TTS: Azure       │
│  │  [打开]  [⋮]      │ │  [打开]  [⋮]     │
│  └───────────────────┘ └───────────────────┘
└───────────────────────────────────────┘
```

"添加 Agent" 弹窗配置项（按类型展示）：
- Agent 名称（文本输入）
- Agent 类型：Chat / Translate（分段选择器）
- Chat 类型：选择 LLM 服务（必选）、STT 服务（可选）、TTS 服务（可选）
  - TTS 服务选中后，展开音色选择（Chip 组）
  - 系统提示词（system prompt）文本区
- Translate 类型：选择翻译服务（必选）、源语言、目标语言
  - 选择 TTS 服务（目标语言朗读，可选），展开音色选择

### 6.3 多模态输入栏组件（MultimodalInputBar）

底部**统一输入栏**包含三种输入状态，通过左右两侧图标切换，无需额外 Tab 行：

```
┌──────────────────────────────────────────┐
│  [⌨️]   [● 按住说话，松开发送]   [📞]    │  ← 默认状态（短语音）
│         左：切换文字输入                   │
│                            右：进入通话   │
└──────────────────────────────────────────┘

点击 ⌨️ → 切换为文字输入状态：
┌──────────────────────────────────────────┐
│  [〜〜]  [输入框................... ↑]  [📞] │  ← 文字输入状态（左：波形图标，切回短语音）
│  左：切回短语音   ↑ 在输入框内部   右：进入通话  │
└──────────────────────────────────────────┘

点击 📞 → 进入通话模式（整个栏变形）：
┌──────────────────────────────────────────┐
│  🟢 通话中 · 01:23   [✋ 打断]   [📞 挂断]│  ← 通话状态栏
└──────────────────────────────────────────┘
```

三种状态说明：
- **默认（短语音）**：中间大按钮按住录音，松手 STT 识别后发送，上滑取消
- **文字输入**：点击左侧 ⌨️ 切入，展开键盘，回车或点击 ↑ 发送；点击左侧 🎤 切回语音
- **通话模式**：点击右侧 📞 进入，VAD 自动驱动整个对话循环；再点 📞 挂断退出

### 6.4 ChatAgentScreen（对话 Agent 运行界面）

**默认状态（短语音，按住录音中）：**
```
┌───────────────────────────────────────┐
│  ← GPT助手  [LLM: GPT-4o][STT: Azure]│
├───────────────────────────────────────┤
│  [用户] 你好，请介绍一下自己            │
│  [AI]   我是 GPT-4o ...               │
│  ┌─ STT 气泡 ────────────────────┐    │
│  │ ~~~波形~~~  "Flutter 最擅长..." │    │
│  └──────────────────────────────┘    │
├───────────────────────────────────────┤
│  [⌨️]   [● 松开发送 · 2.3s]   [📞]   │  ← 按住中，波形 + 时长
└───────────────────────────────────────┘
```

**文字输入状态：**
```
┌───────────────────────────────────────┐
│  ← GPT助手  [LLM: GPT-4o][STT: Azure]│
├───────────────────────────────────────┤
│  [用户] 你好，请介绍一下自己            │
│  [AI]   我是 GPT-4o ... ▋             │
├───────────────────────────────────────┤
│  [🎤]   [继续提问.............. ↑]  [📞]  │
└───────────────────────────────────────┘
```

**通话模式（AI 正在回答）：**
```
┌───────────────────────────────────────┐
│  ← GPT助手  [LLM: GPT-4o][STT: Azure]│
├───────────────────────────────────────┤
│  [用户] Flutter 有什么优势？            │
│  [AI]   Flutter 的核心优势在于...  ▋  │
│  ┌─ TTS 播放指示 ──────────────────┐  │
│  │ ~~~绿色波形~~~  晓晓正在朗读...   │  │
│  └──────────────────────────────┘  │
├───────────────────────────────────────┤
│  🟢 通话中 · 01:23  [✋ 打断]  [📞挂断]│
└───────────────────────────────────────┘
```

### 6.5 TranslateAgentScreen（翻译 Agent 运行界面）

**默认状态（短语音）：**
```
┌───────────────────────────────────────┐
│  ← 翻译官                              │
├───────────────────────────────────────┤
│  [中文 ▼]    ⇌    [英文 ▼]            │
├───────────────────────────────────────┤
│  原文（中文）                           │
│  Artificial intelligence is...        │
│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─  │
│  译文（英文）                           │
│  人工智能正在改变我们的方式。   [▶]     │
├───────────────────────────────────────┤
│  [⌨️]   [● 按住说话，松开翻译]  [📞]   │
└───────────────────────────────────────┘
```

**同传模式（通话状态，逐句翻译）：**
```
┌───────────────────────────────────────┐
│  ← 翻译官  English → 中文              │
├───────────────────────────────────────┤
│  ┌─ 翻译对 1 ────────────────────┐    │
│  │ AI is transforming work...    │    │
│  │ 人工智能正在改变工作方式。       │    │
│  └──────────────────────────────┘    │
│  ┌─ 翻译对 2（进行中）────────────┐    │
│  │ ~~~波形~~~ Flutter is...      │    │
│  │ Flutter 是跨平台的未来▋        │    │
│  └──────────────────────────────┘    │
├───────────────────────────────────────┤
│  🟢 同传中 · 03:17  [🔇]  [📞 结束]   │
└───────────────────────────────────────┘
```

### 6.6 ServicesScreen（服务库管理）

```
┌───────────────────────────────────────┐
│  已配置服务              [+ 添加服务]   │
├───────────────────────────────────────┤
│  ┌────────────────┐ ┌────────────────┐│
│  │ [STT] Azure语音│ │ [TTS] Azure语音││
│  │ 已连接 ✅      │ │ 已连接 ✅      ││
│  └────────────────┘ └────────────────┘│
│  ┌────────────────┐ ┌────────────────┐│
│  │ [LLM] GPT-4o  │ │ [翻译] DeepL   ││
│  │ 已连接 ✅      │ │ 已连接 ✅      ││
│  └────────────────┘ └────────────────┘│
├───────────────────────────────────────┤
│  STT 快速测试  │  TTS 快速测试          │
└───────────────────────────────────────┘
```

"添加服务" 弹窗配置项：
- 服务类型：STT / TTS / STS / LLM / 翻译（分段选择器）
- 厂商选择（6宫格图标选择器）
- 服务名称（文本输入，如"Azure 中文语音"）
- API Key / 密钥（各厂商所需字段）
- [测试连接] 按钮

### 6.7 SettingsScreen（全局参数配置）

```
┌───────────────────────────────────────┐
│  设置                                  │
├───────────────────────────────────────┤
│  外观                                  │
│  └── 主题    [浅色 | 深色 | 跟随系统]   │
├───────────────────────────────────────┤
│  后台服务                              │
│  ├── 后台运行         [开关]            │
│  ├── 电池优化         [忽略 >]          │
│  └── 开机自启         [开关]            │
├───────────────────────────────────────┤
│  对话默认参数                           │
│  ├── 历史消息数        [20]             │
│  ├── Temperature      [0.7]            │
│  ├── Max Tokens       [2048]           │
│  └── Markdown 渲染    [开关]            │
├───────────────────────────────────────┤
│  语音默认参数                           │
│  ├── 采样率            [16000 Hz]      │
│  ├── TTS 语速          [1.0x]          │
│  └── TTS 音调          [0]             │
├───────────────────────────────────────┤
│  关于                                  │
│  ├── 版本             v1.0.0           │
│  └── 开源协议          MIT             │
└───────────────────────────────────────┘
```

---

## 7. Service Library 与 Provider Registry

### 7.1 核心概念

**Service Library（服务库）**：用户在 Services Tab 中配置的一组命名服务实例。每个服务有唯一 `serviceId`（用户自定义名称），配置一次即可被多个 Agent 复用，无需重复填写 API Key。

**Agent 引用服务**：Agent 配置中仅保存 `serviceId` 引用，运行时通过 Registry 查找对应的 Provider 实例。

```
ServiceLibrary（持久化存储）
  "Azure 中文语音" → ServiceConfig { type: STT, vendor: azure, apiKey: ... }
  "GPT-4o"        → ServiceConfig { type: LLM, vendor: openai, model: gpt-4o, ... }
  "DeepL 翻译"    → ServiceConfig { type: Translation, vendor: deepl, ... }
  "Azure 晓晓"    → ServiceConfig { type: TTS, vendor: azure, voice: zh-CN-XiaoxiaoNeural, ... }

ChatAgentConfig
  sttServiceId: "Azure 中文语音"
  llmServiceId: "GPT-4o"
  ttsServiceId: "Azure 晓晓"
  systemPrompt:  "你是一个有帮助的助手..."
  ttsVoice:      "zh-CN-XiaoxiaoNeural"  ← 可覆盖服务默认音色
```

### 7.2 Provider Registry 实现

```dart
// lib/registry/stt_registry.dart

class SttRegistry {
  static final Map<SttVendor, SttProvider Function(ServiceConfig)> _factories = {
    SttVendor.azure:  (c) => SttAzurePlugin(subscriptionKey: c.apiKey, region: c.region!),
    SttVendor.aliyun: (c) => SttAliyunPlugin(appKey: c.apiKey, token: c.secretKey!),
    SttVendor.google: (c) => SttGooglePlugin(apiKey: c.apiKey),
    SttVendor.doubao: (c) => SttDoubaoPlugin(appId: c.apiKey, token: c.secretKey!),
  };

  static SttProvider create(ServiceConfig config) {
    final factory = _factories[config.vendor];
    if (factory == null) throw UnsupportedError('STT vendor ${config.vendor} not registered');
    return factory(config);
  }
}
```

### 7.3 ServiceLibrary 数据模型

```dart
// lib/registry/service_library.dart

enum ServiceType { stt, tts, sts, llm, translation }
enum SttVendor { azure, aliyun, google, doubao }
enum TtsVendor { azure, aliyun, google, doubao }
enum LlmVendorType { openaiCompatible, coze }
enum TranslationVendor { deepl, google, aliyun, youdao }

class ServiceConfig {
  final String serviceId;   // 用户命名，如 "Azure 中文语音"
  final ServiceType type;
  final String vendor;      // 厂商标识
  final String apiKey;
  final String? secretKey;  // 部分厂商需要
  final String? region;
  final String? model;      // LLM model name
  final String? voice;      // TTS 默认音色
  final Map<String, dynamic> extra; // 厂商特有参数
}

// OpenAI-compatible 服务配置
class OpenAICompatibleConfig extends ServiceConfig {
  final String baseUrl;      // API 地址，如 https://api.openai.com/v1
  final String apiKey;
  final String model;        // 如 gpt-4o, qwen-max, deepseek-chat
  final double temperature;
  final int maxTokens;
  final List<String> mcpServerIds;  // 关联的远程 MCP 服务器 ID 列表
}

// Coze 服务配置
class CozeConfig extends ServiceConfig {
  final String apiKey;
  final String botId;
  final String? workspaceId;
  final String baseUrl; // 国内版/国际版
}
```

---

## 8. MCP（Model Context Protocol）架构

### 8.1 整体结构

```
McpManager
  ├── LocalMcpRegistry（本地工具注册表）
  │   ├── UserInfoTool       # 用户信息（姓名、偏好、联系人等）
  │   ├── DateTimeTool       # 当前时间/日期
  │   ├── CalculatorTool     # 数学计算
  │   └── DeviceInfoTool     # 设备信息
  │
  └── RemoteMcpRegistry（远程 MCP 服务器注册表）
      └── McpServerConfig[]  # 每条配置一个远程 MCP 服务器
```

### 8.2 McpServerConfig 数据模型

```dart
enum McpTransportType { sse, http }

class McpServerConfig {
  final String serverId;        // 唯一标识
  final String name;            // 用户命名，如 "Notion MCP"
  final String url;             // 服务器地址
  final McpTransportType transport; // SSE 或 HTTP
  final Map<String, String> headers; // 鉴权头（Authorization 等）
  final List<String> enabledTools;   // 用户勾选启用的工具 ID 列表
}
```

### 8.3 本地 MCP 工具

```dart
// lib/mcp/local/user_info_provider.dart
class UserInfoProvider {
  String? name;
  String? language;
  String? timezone;
  Map<String, String> customFields;
}

// 工具基类
abstract class LocalMcpTool {
  String get toolId;
  String get displayName;
  String get description;
  Map<String, dynamic> get inputSchema;
  Future<String> execute(Map<String, dynamic> args);
}
```

### 8.4 与 LLM 的集成

- Agent 运行时，McpManager 将已启用的本地工具 + 远程服务器工具合并，作为 `tools` 参数传给 LLM
- OpenAI-compatible 接口原生支持 function calling / tools，无需额外适配
- Coze 通过 Bot 配置管理工具，不在客户端注入

---

## 9. Agent 详细设计

> **架构说明**：Agent 所有执行逻辑（状态机、管线编排、VAD、会话历史）均运行在 `agent_runtime` 原生 Service 中。Flutter 层仅负责：
> 1. 将用户操作通过 Pigeon 下行给原生（sendText / interrupt / setInputMode）
> 2. 监听原生上行的 AgentEvent，更新 UI 状态（Riverpod Provider 镜像）

### 9.1 输入模式（三种，聊天和翻译均支持）

| 模式 | Flutter 侧操作 | 原生侧行为 |
|------|----------------|-----------|
| **文本模式** | 键盘输入 → 点击发送 → `sendText()` Pigeon 调用 | AgentSession 接收文本，直接进入 LLM_CALLING |
| **短语音模式** | 按住按钮 → 松开 → `stopShortVoice()` | AgentSession 录制音频 → STT → LLM_CALLING |
| **通话模式** | 点击📞 → `setInputMode("call")` | AgentSession 开启 VAD 循环，持续在 LISTENING↔RECORDING↔LLM↔TTS 之间驱动 |

### 9.2 Agent 原生执行管线（运行在 AgentRuntimeService 中）

**文本 / 短语音模式：**
```
sendText / stopShortVoice
  └──[原生 AgentSession]──→ STT（如需）──→ LLM_CALLING ──→ LLM_STREAMING
                                                  └──[stream chunk]──→ onMessageChunk 事件上行 Flutter
                                        └──[done + TTS enabled]──→ TTS_SYNTHESIZING ──→ PLAYING ──→ IDLE
```

**通话模式（VAD 自动驱动，App 可在后台）：**
```
setInputMode("call")
  └──[AgentRuntimeService 保活运行]
        IDLE ──→ LISTENING（VAD 持续检测）
              └──[检测到语音]──→ RECORDING
                    └──[检测到静音]──→ STT_PROCESSING
                          └──[识别完成]──→ LLM_CALLING ──→ LLM_STREAMING
                                                └──[done]──→ TTS_SYNTHESIZING ──→ PLAYING
                                                                  └──[播放完毕]──→ LISTENING（自动循环）
        ANY ──[interrupt()]──→ LISTENING（立刻打断 TTS，恢复监听）
        ANY ──[setInputMode("voice")]──→ IDLE（退出通话）
```

**事件上行（原生 → Flutter EventChannel）：**
```
onStateChanged(sessionId, "LISTENING")    → UI 更新为"聆听中"
onSttResult(sessionId, text, isFinal)     → 显示 STT 气泡
onMessageChunk(sessionId, chunk, isDone)  → 流式更新 AI 气泡
onTtsStateChanged(sessionId, true)        → 显示 TTS 波形动画
onError(sessionId, "STT_TIMEOUT", "...")  → 显示错误 Toast
```

### 9.3 请求打断与 "最新优先" 机制（Chat 专用）

> **仅适用于 Chat Agent**。翻译 Agent 说多少翻多少，每句独立处理，不存在打断逻辑。

**问题场景**：用户在通话/短语音模式下连续说话，AI 还未开始回答下一个问题就来了，需要放弃旧请求、立刻响应最新问题。

**设计方案：requestId 追踪 + "最新优先" 取消策略**

#### requestId 的生成来源（按输入模式）

不同输入模式下，requestId 由不同层生成：

| 输入模式 | requestId 生成方 | 触发时机 | 路径 |
|---------|----------------|---------|------|
| **文本模式** | Flutter | 用户点击发送 | Flutter 生成 UUID → `sendText(sessionId, requestId, text)` via Pigeon |
| **短语音模式** | 原生 STT 层 | STT 返回 `isFinal=true` | `SttPipelineNode` 生成 UUID → 直接调用 `AgentSession.onUserInput(requestId, text)` |
| **通话模式** | 原生 STT 层 | 每轮 VAD→STT 识别完成 | 同短语音，原生内部闭环，不经过 Flutter |

**关键点**：短语音和通话模式下，Flutter 对 requestId 无感知，整个 VAD→STT→onUserInput 链路全部在原生 Service 内部完成。Flutter 只通过 EventChannel 收到结果事件（`onSttResult` / `onMessageChunk`），事件中携带的 requestId 由原生生成。

```
【文本模式】
Flutter 用户点击发送
  └─ UUID requestId = UUID.randomUUID()
       └─ sendText(sessionId, requestId, text)   ← Pigeon MethodChannel
            └─ AgentSession.onUserInput(requestId, text)

【短语音 / 通话模式】
原生 VAD 检测到语音结束
  └─ STT 请求 → isFinal=true
       └─ UUID requestId = UUID.randomUUID()     ← 原生 SttPipelineNode 生成
            └─ AgentSession.onUserInput(requestId, sttText)  ← 原生内部直接调用
                 └─ EventChannel 上行：onSttResult(sessionId, sttText, isFinal=true, requestId)
                      └─ Flutter 仅用于 UI 展示识别文字，不参与请求调度
```

**核心流程（所有模式共用）：**

```
AgentSession.onUserInput(requestId, text)
  └─ activeRequestId = requestId
     取消上一个 in-flight 请求（如果有）：
       - 取消 LLM HTTP 流（OkHttp cancel / URLSession cancel）
       - 停止 TTS 合成
       - DB UPDATE messages SET status='cancelled' WHERE id=旧requestId
     开始新的 LLM 请求（绑定新 requestId）
```

**原生 AgentSession 核心逻辑（Kotlin 示意）：**

```kotlin
private var activeRequestId: String? = null
private var activeCall: Call? = null  // OkHttp 请求句柄

fun onUserInput(requestId: String, text: String) {
    // 1. 取消当前进行中的请求
    activeCall?.cancel()
    activeRequestId?.let { oldId ->
        db.messageDao.updateStatus(oldId, "cancelled")
        eventSink.send(AgentEvent.requestCancelled(sessionId, oldId))
    }

    // 2. 激活新请求
    activeRequestId = requestId
    db.messageDao.insert(MessageEntity(id=requestId, role="user", status="done", ...))
    val responseId = UUID.randomUUID().toString()
    db.messageDao.insert(MessageEntity(id=responseId, role="assistant", status="pending", ...))

    // 3. 发起 LLM 请求
    activeCall = llmEngine.streamChat(
        messages = db.messageDao.getHistory(sessionId),
        onChunk = { chunk ->
            if (activeRequestId == requestId) {   // 确认仍是最新请求
                db.messageDao.appendContent(responseId, chunk)
                eventSink.send(AgentEvent.messageChunk(sessionId, requestId, chunk, false))
            }
        },
        onDone = {
            if (activeRequestId == requestId) {
                db.messageDao.updateStatus(responseId, "done")
                eventSink.send(AgentEvent.messageChunk(sessionId, requestId, "", true))
                startTts(responseId)
            }
        }
    )
}
```

**Flutter UI 侧处理：**

```dart
// onMessageChunk 到达时，先校验 requestId
AgentRuntimeBridge.eventStream(sessionId).listen((event) {
  if (event is MessageChunkEvent) {
    // 忽略非当前活跃请求的响应（双重保险，原生已过滤）
    if (event.requestId != state.activeRequestId) return;
    state = state.appendChunk(event.requestId, event.chunk, event.isDone);
  }
  if (event is RequestCancelledEvent) {
    // 将对应消息气泡标记为"已取消"样式
    state = state.markCancelled(event.requestId);
  }
});
```

**关键规则总结：**
| 场景 | 行为 |
|------|------|
| 新请求到来，旧请求 LLM 尚未开始 | 直接跳过旧请求，开始新请求 |
| 新请求到来，旧请求 LLM 流式中 | 取消 HTTP 流，响应消息标记 cancelled |
| 新请求到来，旧请求 TTS 播放中 | 停止 TTS，标记完成（AI 回答已生成），开始新 LLM |
| 翻译 Agent | **不适用**，每条独立处理，全部保留 |

### 9.4 Flutter 侧 Provider（薄层，仅做 UI 状态镜像）

```dart
// lib/runtime/agent_session_provider.dart

@riverpod
class AgentSessionNotifier extends _$AgentSessionNotifier {
  StreamSubscription? _eventSub;

  @override
  AgentSessionState build(String sessionId) {
    // 监听原生 EventChannel 推送
    _eventSub = AgentRuntimeBridge.eventStream(sessionId).listen((event) {
      state = state.applyEvent(event);  // 纯状态更新，无业务逻辑
    });
    ref.onDispose(() => _eventSub?.cancel());
    return AgentSessionState.idle();
  }

  Future<void> sendText(String text) =>
      AgentRuntimeBridge.sendText(sessionId, text);

  Future<void> interrupt() =>
      AgentRuntimeBridge.interrupt(sessionId);

  Future<void> setInputMode(AgentInputMode mode) =>
      AgentRuntimeBridge.setInputMode(sessionId, mode.name);
}
```

### 9.5 Agent 配置模型（Dart 侧，仅数据，无执行逻辑）

```dart
// lib/agents/chat_agent_config.dart

class ChatAgentConfig {
  final String agentId;
  final String agentName;
  final String llmServiceId;      // 引用 ServiceLibrary 中的 LLM 服务（必选）
  final String? sttServiceId;     // STT 服务（可选）
  final String? ttsServiceId;     // TTS 服务（可选）
  final String systemPrompt;
  final String? ttsVoice;         // 覆盖服务默认音色
  final String sttLanguage;
  final int maxHistoryMessages;
  final AgentInputMode defaultInputMode;
  final List<String> enabledLocalMcpTools;   // 启用的本地 MCP 工具 ID
  final List<String> enabledMcpServerIds;    // 启用的远程 MCP 服务器 ID
}

class TranslateAgentConfig {
  final String agentId;
  final String agentName;
  final String translationServiceId;
  final String? sttServiceId;
  final String? ttsServiceId;
  final String? ttsVoice;
  final String sourceLanguage;    // "auto" = 自动检测
  final String targetLanguage;
}
```

---

## 10. 技术选型

| 类别 | 选型 | 说明 |
|------|------|------|
| 状态管理 | Riverpod 2.x | 类型安全，异步友好 |
| Platform Channel | Pigeon（每插件独立生成） | 类型安全，各插件自包含 |
| 共享接口 | ai_plugin_interface（本地 Dart 包）| 统一 Provider 抽象接口 |
| 后台服务 Android | ForegroundService（agent_runtime 插件声明）| AgentSession 独立于 Flutter Engine 运行 |
| 后台服务 iOS | AVAudioSession + BGTaskScheduler（agent_runtime 管理）| Background Audio 保活通话模式 |
| 环境配置 | flutter_dotenv | .env 文件加载 |
| HTTP（翻译/纯 Dart LLM 备用） | dio | 翻译 Provider 使用 |
| HTTP（LLM 原生层） | OkHttp (Android) / URLSession (iOS) | SSE 流式请求 |
| 原生音频 Android | AudioRecord / AudioTrack | STT/TTS 插件使用 |
| 原生音频 iOS | AVAudioEngine / AVSpeechSynthesizer | STT/TTS 插件使用 |
| 路由 | go_router | 声明式路由，底部导航 |
| JSON 序列化 | json_serializable + freezed | 数据模型不可变 |
| Markdown 渲染 | flutter_markdown | LLM 回复渲染 |
| 日志 | logger (Dart) + Timber (Android) + OSLog (iOS) | 分层日志 |
| Agent 执行引擎 | agent_runtime 原生插件 | 管线编排、VAD、状态机全部在原生 Service 运行 |
| Flutter↔Native 事件 | EventChannel（agent_runtime） | 原生状态变化推送到 Flutter UI |
| MCP 客户端 | 原生实现（OkHttp SSE / URLSession）| 在 agent_runtime 内部调用，不走 Dart 层 |
| MCP 本地工具 | 原生实现（Kotlin / Swift）| UserInfo/DateTime/Calculator/DeviceInfo |
| 本地数据库 Android | Room（SQLite ORM）| local_db 插件，agent_runtime 直接访问 |
| 本地数据库 iOS | GRDB（Swift SQLite 库）| 同上，原生层直写，Flutter 只读查询 |
| 敏感数据加密 | Android Keystore / iOS Keychain | service_configs 中的 apiKey 加密存储 |
