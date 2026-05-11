# AI Agent SDK 使用文档

**项目名称**：AI Agent Client SDK
**版本**：v0.1.0
**日期**：2026-05-10
**适用读者**：接入本 SDK 的下游业务方开发者

---

## 0. 一句话概览

26 个 Flutter package，分四层（接口/厂商/编排/容器）+ 一个 umbrella 门面包。覆盖**语音对话、文本对话、文本翻译、端到端语音翻译、通话翻译、AI 助手、MCP 工具调用、蓝牙耳机协同**等场景。业务方加一行依赖（`ai_agent_sdk: ^0.1.0`）就能拿到全套。

发布与安装见 [`docs/sdk-distribution.md`](sdk-distribution.md)。本文档只讲**怎么用**。

---

## 1. 包导览（26 个）

### 1.1 接口层 (L0) — 3 包

| 包 | 用途 |
|---|---|
| `ai_plugin_interface` | 定义 STT / TTS / LLM / Translation / STS / AST / MCP 共 7 类抽象 + 配置 + 事件 |
| `device_plugin_interface` | 定义 `DevicePlugin` / `DeviceSession` / `DeviceManager` / `DeviceOtaPort` 抽象 |
| `local_db` | 跨域持久化（agent / service 配置、对话历史等） |

### 1.2 厂商层 (L1) — 13 包

按能力分组，**命名规则 `<能力>_<厂商>`**：

| 能力 | 包 |
|---|---|
| STT 语音识别 | `stt_azure` |
| TTS 语音合成 | `tts_azure` |
| LLM 大模型 | `llm_openai`、`llm_volcengine` |
| STS 端到端语音对话 | `sts_volcengine`、`sts_polychat`（含 `sts_doubao` 占位） |
| AST 端到端语音翻译 | `ast_volcengine`、`ast_polychat` |
| 文本翻译 | `translation_aliyun`、`translation_azure`、`translation_deepl` |
| MCP 工具协议 | `mcp` |
| 蓝牙耳机 | `device_jieli`（恒玄/高通/中科蓝讯待补） |

> 厂商包**只做实现**，业务方不应该直接 import。能用 `agents_server` / `service_manager` 容器透传调用就用容器，需要直接调 plugin 是逃生通道，不是常态。

### 1.3 编排层 (L2) — 3 包

| 包 | 用途 |
|---|---|
| `translate_server` | 复合场景：通话翻译 / 面对面翻译 / 音视频翻译 |
| `assistant_server` | AI 助手：原生模式 + RCSP 设备模式（蓝牙耳机本地按键唤醒） |
| `device_manager` | 单设备路由器，单 active session，统一音频端口分配 |

### 1.4 容器层 (L3) — 6 包

| 包 | 用途 |
|---|---|
| `agent_chat` | 三段式对话：STT → LLM → TTS |
| `agent_sts_chat` | 端到端语音对话（厂商 STS 直出） |
| `agent_translate` | 三段式翻译：STT → Translation → TTS |
| `agent_ast_translate` | 端到端语音翻译（厂商 AST 直出） |
| `service_manager` | AI 厂商服务工厂注册中心 + 服务自测桥 |
| `agents_server` | Agent 工厂注册中心 + 多 agent 生命周期管理 |

> `agent_*` 四个包是 **native-only**（Dart 几乎为空），业务方不直接 import 它们的类型——而是通过 `AgentsServerBridge.createAgent(agentType: 'chat' \| 'sts-chat' \| 'translate' \| 'ast-translate')` 来启动。

### 1.5 门面包 (Umbrella) — 1 包

| 包 | 用途 |
|---|---|
| `ai_agent_sdk` | re-export L0 接口 + L2/L3 容器，把 4 个 agent 类型包 + `device_jieli` 列为依赖让其 native 自注册 |

---

## 2. 快速开始

### 2.1 添加依赖

```yaml
# 业务方 pubspec.yaml
dependencies:
  ai_agent_sdk: ^0.1.0
```

```bash
export PUB_HOSTED_URL=http://localhost:4000   # 或公司内网私服
flutter pub get
```

### 2.2 第一个 agent — 三段式语音对话

```dart
import 'package:ai_agent_sdk/ai_agent_sdk.dart';
import 'dart:convert';

Future<void> bootstrap() async {
  final bridge = AgentsServerBridge();

  // 监听 agent 事件
  bridge.eventStream.listen((event) {
    switch (event) {
      case SttEvent(:final kind, :final text, :final requestId):
        print('STT[$kind]: $text  reqId=$requestId');
      case LlmEvent(:final kind, :final textDelta, :final fullText):
        print('LLM[$kind]: ${textDelta ?? fullText}');
      case TtsEvent(:final kind):
        print('TTS[$kind]');
      case AgentErrorEvent(:final code, :final message):
        print('ERR $code: $message');
      case _:
        // SessionStateEvent / AgentReadyEvent / ServiceConnectionStateEvent
    }
  });

  // 创建 agent
  await bridge.createAgent(
    agentId: 'demo-1',
    agentType: 'chat',                  // 'chat' | 'sts-chat' | 'translate' | 'ast-translate'
    inputMode: 'voice',                 // 'voice' | 'text'
    sttVendor: 'azure',
    sttConfigJson: jsonEncode({
      'apiKey': '<azure-stt-key>',
      'region': 'eastasia',
      'language': 'zh-CN',
    }),
    llmVendor: 'openai',
    llmConfigJson: jsonEncode({
      'apiKey': '<openai-key>',
      'baseUrl': 'https://api.openai.com/v1',
      'model': 'gpt-4o-mini',
      'temperature': 0.7,
      'systemPrompt': '你是一个友善的助手。',
    }),
    ttsVendor: 'azure',
    ttsConfigJson: jsonEncode({
      'apiKey': '<azure-tts-key>',
      'region': 'eastasia',
      'voiceName': 'zh-CN-XiaoxiaoNeural',
    }),
  );

  // 接入 service（连接厂商服务器，完成鉴权）
  await bridge.connectService('demo-1');

  // 开始监听麦克风
  await bridge.startListening('demo-1');

  // ...用户说话；事件流会按 STT → LLM → TTS 顺序到达，requestId 串起来同一轮

  // 销毁
  await bridge.deleteAgent('demo-1');
}
```

---

## 3. 三大铁律（贯穿所有包）

### 3.1 requestId 串联

同一"轮次"的事件**共享一个 requestId**，跨插件传递：

```
STT.finalResult.requestId
  ── 透传 ──> LLM.chat.requestId
                ── 透传 ──> TTS.speak.requestId
```

- `requestId` 由触发方生成（通常是 STT 在 `finalResult` 时生成，格式 `<vendor>_<unixMs>_<rand6>`）
- 所有可打断的插件（LLM / TTS / STS / AST）必须支持"按 requestId 取消"
- 新 requestId 到达时，旧 requestId 的事件流必须**收尾**：派发 `cancelled` 或 `playbackInterrupted`

业务方的处理原则：**永远按 requestId 隔离 UI 状态**，不要把不同轮次的文本拼在一起。

### 3.2 生命周期状态机

```
uninitialized → initialize(config) → ready
              → start*/speak/chat → ready (允许多次)
              → dispose() → disposed (终态)
```

- `initialize` 幂等：再次调用先释放旧资源
- `dispose` 必须释放所有原生资源（WebSocket / AudioTrack / 定时器 / StreamController）
- `dispose` 后再调任何方法**必抛 `StateError`**

### 3.3 单 active session 互斥

| 域 | 互斥单元 | 说明 |
|---|---|---|
| AI agent | `agents_server.activeAgent` | `AgentsServerBridge` 内多 agent 并存，但**麦克风**只能给一个 agent；切 agent 前停旧的 |
| 设备 | `DeviceManager.activeSession` | 至多一个连接中的耳机，`connect(newId)` 自动断旧 |
| 复合场景 | `TranslateServer.activeSession` | 通话翻译 / 面对面 / 音视频三种业务**互斥**，新 start 自动 stop 旧 |
| 设备厂商 | `DeviceManager.useVendor()` | 同进程**至多一个** vendor 处于 initialized 状态 |

---

## 4. 接口层 (L0) API

### 4.1 ai_plugin_interface — 7 类抽象

| 接口 | 配置类 | 事件类 | 关键方法 |
|---|---|---|---|
| `SttPlugin` | `SttConfig{apiKey, region, language}` | `SttEvent{type, text, isFinal, detectedLang}` | `startListening` / `stopListening` |
| `TtsPlugin` | `TtsConfig{apiKey, region, voiceName, outputFormat}` | `TtsEvent{type, audioData, durationMs}` | `speak(text, requestId)` / `stop(requestId)` |
| `LlmPlugin` | `LlmConfig{apiKey, baseUrl, model, temperature, maxTokens, systemPrompt}` | `LlmEvent{type, textDelta, fullText, toolCall}` | `chat(messages, requestId)` / `cancel(requestId)` |
| `TranslationPlugin` | `TranslationConfig{apiKey, extra}` | `Future<TranslationResult>` | `translate(text, srcLang, dstLang)` |
| `StsPlugin` | `StsConfig{apiKey, appId, voiceName}` | `StsEvent{type, role, text, audioChunk}` | `startCall` / `sendAudio(pcm)` / `stopCall` |
| `AstPlugin` | `AstConfig{apiKey, appId, srcLang, dstLang}` | `AstEvent{type, text, ttsAudioChunk}` | `startCall` / `sendAudio(pcm)` / `stopCall` |
| `McpPlugin` | `McpServerConfig{url, name}` | — | `listTools` / `callTool(name, args)` |

事件枚举（节选）：

- `SttEventType`: `listeningStarted`, `vadSpeechStart`, `vadSpeechEnd`, `partialResult`, `finalResult`, `listeningStopped`, `error`
- `TtsEventType`: `synthesisStart`, `synthesisReady`, `playbackStart`, `playbackProgress`, `playbackDone`, `playbackInterrupted`, `error`
- `LlmEventType`: `firstToken`, `done`, `cancelled`, `error`, `toolCallStart`, `toolCallArguments`, `toolCallResult`
- `StsEventType`: `connected`, `recognitionStart`, `recognizing`, `recognized`, `recognitionDone`, `recognitionEnd`, `synthesisStart`, `synthesizing`, `playbackStart`, `audioChunk`, `playbackEnd`, `disconnected`

### 4.2 device_plugin_interface — 设备域抽象

```dart
abstract class DevicePlugin { /* vendorKey, capabilities, configSchema, initialize/dispose */ }
abstract class DeviceSession { /* eventStream, readBattery, invokeFeature, otaPort, disconnect */ }
abstract class DeviceManager  { /* activeSession, useVendor, connect, agentTriggers */ }
abstract class DeviceOtaPort  { /* start(DeviceOtaRequest), cancel, isRunning, progressStream */ }
```

`DeviceOtaRequest` 是 sealed 层级：`File` / `Bytes` / `Url` / `Vendor`（详见 `local_plugins/CLAUDE.md` §10.9）。

### 4.3 local_db

跨域 KV / 关系存储，主要由 `agents_server` / `service_manager` 内部使用，业务方一般不直接调。

---

## 5. 厂商实现速查 (L1)

`agentsServer.createAgent()` 里 `xxxVendor` 字段填的就是这个表里的 vendor key（注册名）：

| 包名 | vendorKey | 配置字段 |
|---|---|---|
| `stt_azure` | `azure` | `apiKey`, `region`, `language` |
| `tts_azure` | `azure` | `apiKey`, `region`, `voiceName`, `outputFormat` |
| `llm_openai` | `openai` | `apiKey`, `baseUrl`, `model`, `temperature`, `maxTokens`, `systemPrompt` |
| `llm_volcengine` | `volcengine` | `apiKey`, `model`, `baseUrl`, `temperature`, `maxTokens` |
| `sts_volcengine` | `volcengine` | `apiKey`, `appId`, `voiceName` |
| `sts_polychat` | `polychat` | （由业务自定义；polychat 是私有协议） |
| `ast_volcengine` | `volcengine` | `apiKey`, `appId`, `srcLang`, `dstLang` |
| `ast_polychat` | `polychat` | `baseUrl`, `appId`, `appSecret`, `agentId` |
| `translation_aliyun` | `aliyun` | `apiKey` 格式：`{accessKeyId}:{accessKeySecret}` |
| `translation_azure` | `azure` | `apiKey`, `region` |
| `translation_deepl` | `deepl` | `apiKey`, `extra: {isPro: bool}` |
| `mcp` | — | `McpServerConfig{url, name}` |
| `device_jieli` | `jieli` | （走 `DeviceManager.useVendor('jieli', config)`） |

> **vendorKey 在不同能力域里是独立命名空间**：`stt_azure` 注册的 `azure` 与 `tts_azure` 注册的 `azure` 互不干扰，因为前者注册到 STT 工厂，后者到 TTS 工厂。

---

## 6. 容器层入口

### 6.1 AgentsServerBridge（业务方主入口）

```dart
class AgentsServerBridge {
  Stream<AgentEvent> get eventStream;

  // 创建 agent（4 种 type）
  Future<void> createAgent({
    required String agentId,
    required String agentType,        // 'chat' | 'sts-chat' | 'translate' | 'ast-translate'
    String inputMode = 'text',        // 'voice' | 'text'
    // 按 agentType 选填以下字段：
    String? sttVendor, String? sttConfigJson,
    String? ttsVendor, String? ttsConfigJson,
    String? llmVendor, String? llmConfigJson,
    String? stsVendor, String? stsConfigJson,
    String? astVendor, String? astConfigJson,
    String? translationVendor, String? translationConfigJson,
    String? mcpServersJson,
    Map<String, String> extraParams = const {},
  });

  Future<void> stopAgent(String agentId);
  Future<void> deleteAgent(String agentId);

  // 服务连接（鉴权 / WebSocket 长连）
  Future<void> connectService(String agentId);
  Future<void> disconnectService(String agentId);

  // 输入控制
  Future<void> setInputMode(String agentId, String mode);   // 'voice' | 'text'
  Future<void> sendText(String agentId, String requestId, String text);
  Future<void> startListening(String agentId);
  Future<void> stopListening(String agentId);

  // 打断与暂停
  Future<void> interrupt(String agentId);     // 立即停止当前 LLM/TTS 输出
  Future<void> pauseAudio(String agentId);
  Future<void> resumeAudio(String agentId);

  // 全局
  Future<void> notifyAppForeground(bool isForeground);
  Future<void> setAudioOutputMode(String mode);   // 'phone' | 'device' (耳机)
}
```

事件层级（`AgentEvent` 是 sealed）：

```dart
sealed class AgentEvent { final String sessionId; }
final class SttEvent extends AgentEvent { ... requestId, kind, text, detectedLang }
final class LlmEvent extends AgentEvent { ... requestId, kind, textDelta, fullText, toolCall }
final class TtsEvent extends AgentEvent { ... requestId, kind, audioData, durationMs }
final class SessionStateEvent extends AgentEvent { ... state }
final class ServiceConnectionStateEvent extends AgentEvent { ... connected, errorCode }
final class AgentReadyEvent extends AgentEvent { ... }
final class AgentErrorEvent extends AgentEvent { ... code, message }
```

### 6.2 ServiceManagerBridge（厂商配置 + 单服务自测）

主要用途是**预校验厂商配置是否能跑通**（业务方在"服务配置"页给用户做"测试连接"按钮的后端）：

```dart
class ServiceManagerBridge {
  Stream<ServiceTestEvent> get eventStream;

  Future<void> testSttStart({...});
  Future<void> testTtsSpeak({...});
  Future<void> testLlmChat({...});
  Future<void> testTranslate({...});
  Future<void> testStsConnect({...});
  Future<void> testAstConnect({...});
  Future<void> autoTest({...});  // 一键全跑
  Future<void> releaseTest(String testId);
}
```

业务方**不应该**用 ServiceManagerBridge 跑生产对话——那是 `AgentsServerBridge` 的工作。

### 6.3 DeviceManager（蓝牙耳机统一入口）

`DeviceManager` 是 `device_plugin_interface` 里的抽象，实现来自 `device_manager` 包：

```dart
final dm = MethodChannelDeviceManager();   // implements DeviceManager
await dm.initialize();
dm.registerVendor(JieliPluginDescriptor());   // 启动时注册想用的厂商
await dm.useVendor('jieli', JieliPluginConfig(...));
```

抽象签名：

```dart
abstract class DeviceManager {
  Stream<DeviceManagerEvent> get eventStream;
  Stream<DeviceAgentTrigger> get agentTriggers;
  DeviceSession? get activeSession;

  Future<void> initialize();
  void registerVendor(DevicePluginDescriptor descriptor);
  Future<void> useVendor(String vendorKey, DevicePluginConfig config);
  Future<void> clearVendor();

  Future<bool> isBluetoothEnabled();
  Future<void> startScan({Duration? timeout});
  Future<void> stopScan();
  Future<List<DiscoveredDevice>> bondedDevices();

  Future<DeviceSession> connect(String deviceId);
  Future<void> disconnect();
  Future<void> dispose();
}
```

`DeviceSession` 上能拿到电量、信号、`invokeFeature(key, args)`（厂商私有功能）、`otaPort()`（固件升级）。

---

## 7. 编排层 (L2)

### 7.1 TranslateServer — 通话翻译

**典型场景**：用户戴杰理耳机打电话，全程双向翻译，对方听到本地语，本地听到对方语。

```dart
final ts = MethodChannelTranslateServer();   // implements TranslateServer

final session = await ts.startCallTranslation(CallTranslationRequest(
  uplinkAgentType: 'ast-translate',
  uplinkConfig: {...},                 // 透传给 AgentsServerBridge.createAgent
  downlinkAgentType: 'ast-translate',
  downlinkConfig: {...},
  userLanguage: 'zh-CN',
  peerLanguage: 'en-US',
));

ts.eventStream.listen((event) {
  // SubtitleEvent / TranslationServerErrorEvent / SessionLifecycleEvent
});

// 结束
await session.stop();
```

**铁律**：
- 通话翻译数据**零转码**，依赖耳机给的 OPUS / 16kHz / mono / 20ms（`AudioFormat.standard`）
- 错误**不关流**——`errors` 流派发但 session 仍 active；调用方决定是否 stop
- 设备掉线 / 耳机退翻译模式 → pipeline 自动 stop
- 三种业务（`startCallTranslation` / `startFaceToFaceTranslation` / `startAudioTranslation`）**互斥单 active**

### 7.2 AssistantServer — AI 助手

**典型场景**：耳机长按 PTT 唤醒 AI，问"今天天气怎么样"，AI 回答从耳机播放。

```dart
final asv = MethodChannelAssistantServer();   // implements AssistantServer
final session = await asv.startAssistant(AssistantRequest(
  agentType: 'chat',                   // 复用 agent_chat / agent_sts_chat
  agentConfig: {...},
  userLanguage: 'zh-CN',
));

asv.eventStream.listen((event) { /* MessageEvent / StateEvent */ });
await session.stop();
```

`AssistantServer` 内部根据是否有 `DeviceManager.activeSession` 自动选 phone-mode 或 device-mode 音频通路。

### 7.3 DeviceManager — 看 §6.3

---

## 8. 组合使用场景（重点）

### 8.1 场景 A：三段式语音对话

```
mic → STT → LLM → TTS → speaker
```

依赖：`agent_chat` + 任一 `stt_*` + 任一 `llm_*` + 任一 `tts_*`

```dart
await bridge.createAgent(
  agentId: 'a1', agentType: 'chat', inputMode: 'voice',
  sttVendor: 'azure',  sttConfigJson: ...,
  llmVendor: 'openai', llmConfigJson: ...,
  ttsVendor: 'azure',  ttsConfigJson: ...,
);
```

特点：
- 三家厂商可独立替换
- LLM 流式 token 到达 → TTS 内部按句子切分缓冲合成（参见 `local_plugins/CLAUDE.md` §4.1）
- 打断：`interrupt(agentId)` 同时取消 LLM 与 TTS

### 8.2 场景 B：端到端语音对话

```
mic → STS (识别+对话+合成一体) → speaker
```

依赖：`agent_sts_chat` + 任一 `sts_*`

```dart
await bridge.createAgent(
  agentId: 'a2', agentType: 'sts-chat', inputMode: 'voice',
  stsVendor: 'volcengine', stsConfigJson: ...,
);
```

特点：
- 延迟比三段式低（无 STT/LLM 之间网络往返）
- 可控性低（无法替换 LLM、调 prompt）
- 厂商 STS 失败时**不会自动 fallback** 到三段式——业务方自己判断切

### 8.3 场景 C：文本翻译

```
text → Translation → text
```

依赖：`agent_translate`（如果走 agent 容器）或直接调 `service_manager.testTranslate`（一次性翻译）

```dart
// agent 模式（流式）
await bridge.createAgent(
  agentId: 't1', agentType: 'translate', inputMode: 'voice',
  sttVendor: 'azure', sttConfigJson: ...,
  translationVendor: 'deepl', translationConfigJson: ...,
  ttsVendor: 'azure', ttsConfigJson: ...,
);
```

### 8.4 场景 D：端到端语音翻译

```
mic → AST (识别+翻译+合成一体) → speaker
```

依赖：`agent_ast_translate` + 任一 `ast_*`

```dart
await bridge.createAgent(
  agentId: 'at1', agentType: 'ast-translate', inputMode: 'voice',
  astVendor: 'volcengine', astConfigJson: jsonEncode({
    'apiKey': '...',
    'srcLang': 'zh',
    'dstLang': 'en',
  }),
);
```

### 8.5 场景 E：双向通话翻译（耳机）

```
peer audio →     downlink AST → user 耳机
user audio  →    uplink   AST → peer 耳机
```

依赖：`translate_server` + `device_manager` + `device_jieli` + 两个 `ast_*` 实例

详见 §7.1，**必须**走 `TranslateServer.startCallTranslation`，不能直接编排两个 agent。

### 8.6 场景 F：MCP 工具调用

依赖：`mcp` + 任一 `llm_*`

```dart
await bridge.createAgent(
  agentId: 'tools-1', agentType: 'chat', inputMode: 'text',
  llmVendor: 'openai', llmConfigJson: ...,
  ttsVendor: 'azure',  ttsConfigJson: ...,
  sttVendor: 'azure',  sttConfigJson: ...,
  mcpServersJson: jsonEncode([
    {'url': 'http://localhost:8080/mcp', 'name': 'local-tools'},
    {'url': 'https://api.notion.so/mcp', 'name': 'notion'},
  ]),
);
```

特点：
- LLM 在生成中产生 `toolCallStart` 事件 → SDK 内部调用 MCP server → 把结果作为 `toolCallResult` 反馈给 LLM
- 业务方**不需要**自己执行工具，但**可以**监听 `LlmEvent.toolCall*` 事件做 UI 展示

---

## 9. 跨包使用规范（必须遵守）

### 9.1 初始化顺序

```
1. ServiceManagerBridge / AgentsServerBridge / DeviceManager  实例化（自动单例）
2. （可选）DeviceManager.useVendor('jieli', config) → connect(deviceId)
3. AgentsServerBridge.createAgent(...)
4. AgentsServerBridge.connectService(agentId)              ← 必须在 startListening 之前
5. AgentsServerBridge.startListening(agentId)
```

**反模式**：还没 `connectService` 就 `startListening` → 麦克风会采但事件没法上行，UI 卡住。

### 9.2 资源互斥

| 资源 | 谁占用 | 怎么释放 |
|---|---|---|
| 麦克风 | 同一时刻只能给一个 agent / STS / AST | 切 agent 前先 `stopAgent(旧)` 或 `setInputMode(旧, 'text')` |
| 蓝牙音频通道 | 同一时刻只能给一个 `DeviceSession` | `DeviceManager.connect(新)` 自动断旧 |
| OTA 端口 | 同设备同时只能一个升级任务 | 失败码 `device.ota_busy`；现成任务 `cancel` 后才能起新的 |
| `TranslateServer` session | 三种业务互斥 | `start*` 自动 await 旧 session 的 `stop`，不要手动并发 |

### 9.3 错误码空间

统一格式 **`<plugin>.<reason>`**，三类必须用固定码：

- `*.auth_failed`
- `*.network_error`
- `*.permission_denied`

举例：
- `stt.network_timeout`
- `tts.synthesis_failed`
- `sts.ws_disconnected`
- `device.connect_timeout`
- `device.ota_busy`
- `translate.session_busy`
- `agent_chat.no_active_service`

`errorMessage` 仅作调试用，**禁止**直接显示给终端用户 UI。

### 9.4 打断 (Interruption) 语义

打断必须**立即生效**，不要等当前 chunk 处理完：

```dart
// 旧 requestId 在跑
await bridge.startListening('a1');   // 用户开始新一句

// 新 requestId 到达时（STT.finalResult），SDK 内部自动：
// 1. cancel 旧 requestId 的 LLM
// 2. clear TTS 合成队列 + 停止当前播放
// 3. 派发 LlmEvent(cancelled) + TtsEvent(playbackInterrupted)
// 4. 开始新 requestId 的处理流水
```

业务方**手动打断**：

```dart
await bridge.interrupt('a1');   // 等价于"丢弃当前 requestId 的所有未完成产物"
```

### 9.5 dispose 必须调

每个 `Bridge` 单例不需要 dispose（应用生命周期）。但每个 **agent** 必须显式 `deleteAgent`，否则原生侧资源（线程 / WebSocket / AudioRecord）泄漏。

每个 **DeviceSession** 必须 `disconnect`，OTA 期间断开连接 SDK 会自动派发 `failed(device.disconnected_remote)`，但 socket 资源仍要释放。

---

## 10. 常见陷阱

| 现象 | 根因 | 处理 |
|---|---|---|
| `partialResult` 文本拼接成"我我我我我我"——不停重复 | 把 `partialResult.text` 当增量累加。它是**累计快照**，应该**覆盖**而非追加 | UI 维护 `committedText + currentText`，partial 只更新 currentText |
| LLM 输出说一半就停了，没有 `done` 事件 | 没监听完整事件流就 `dispose` 了 | `done`/`cancelled`/`error` 必有其一闭合，等到任一终态再 dispose |
| 新 requestId 到了，旧的 TTS 还在播 | 厂商 TTS 没正确处理 cancel | 业务方在新 requestId 的 STT.finalResult 时显式 `interrupt(agentId)` |
| 切 vendor（如 STT 从 azure 换 polychat）不生效 | 旧 agent 还在跑 | `deleteAgent(旧)` 后用新 vendor 重 `createAgent` |
| 通话翻译突然 stop 但没收到错误 | 设备掉线 / 耳机退出翻译模式 | 监听 `DeviceSession.eventStream` 的连接事件 + `TranslateServer.eventStream` 的 lifecycle 事件 |
| `OTA` UI 卡住 | OTA 任务终态事件被吞 | UI 锁定逻辑由 `progress.isTerminal` 单点决定，不要叠加自定义状态。详见 `local_plugins/CLAUDE.md` §10.9.5 |
| `SttEvent` 类型名冲突 | 同时引了 `ai_plugin_interface` 和 `agents_server` | 用 umbrella `ai_agent_sdk` 默认拿 agent 级；写厂商插件时直接依赖 `ai_plugin_interface` |
| `flutter pub get` 找不到 `ai_plugin_interface` | 没设 `PUB_HOSTED_URL` | `export PUB_HOSTED_URL=http://localhost:4000` 后再 pub get |

---

## 11. 进阶

### 11.1 选择性裁剪 umbrella

`ai_agent_sdk` 默认拉所有 vendor + agent 类型。不需要某些就不要 umbrella，单包按需依赖：

```yaml
dependencies:
  ai_plugin_interface: ^0.1.0
  agents_server: ^0.1.0          # 但 agents_server 自己声明了一批 vendor，部分仍会被拉进
  stt_azure: ^0.1.0
  llm_openai: ^0.1.0
  tts_azure: ^0.1.0
  # 不要 sts_*, ast_*, translation_* 等
```

> 如果连 `agents_server` 内部的 vendor 依赖都要裁，要先 patch 上游 SDK。等到这成为高频需求再把 vendor 依赖改成 `dev_dependencies` 或独立 vendor pack 包。

### 11.2 写一个新厂商插件

1. 新建 `local_plugins/vendors/<能力>_<厂商>/`
2. `pubspec.yaml` 依赖 `ai_plugin_interface: ^0.1.0`
3. 实现对应抽象类（`SttPlugin` / `TtsPlugin` / ...），命名 `XxxPluginImpl`
4. 在 native 侧 `service_manager` 工厂里注册
5. 自测覆盖：生命周期 / requestId 打断 / 文本语义（参见 `local_plugins/CLAUDE.md` §3-§5）
6. 加进 umbrella 依赖（如果是默认 vendor）

### 11.3 写一个新设备厂商

参见 `local_plugins/CLAUDE.md` §10.8 Checklist。

### 11.4 复合场景扩展（translate_server 之外）

参见 `local_plugins/CLAUDE.md` §11.6 Checklist。

---

## 12. 进一步阅读

| 主题 | 文档 |
|---|---|
| 包架构与运行时约束（接口/事件/requestId/状态机/错误码细节） | [`app/local_plugins/CLAUDE.md`](../app/local_plugins/CLAUDE.md) |
| 包发布与版本管理 | [`docs/sdk-distribution.md`](sdk-distribution.md) |
| 整体架构 | [`docs/architecture.md`](architecture.md) |
| 原生插件开发 | [`docs/native-plugin.md`](native-plugin.md) |
| API 协议 | [`docs/api-spec.md`](api-spec.md) |
