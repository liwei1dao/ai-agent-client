# local_plugins 约束文档

本目录下所有插件必须遵守以下规范，目的是让 `agent_chat` / `agent_sts_chat` / `agent_translate` / `agent_ast_translate` / `agents_server` / `service_manager` 等上层调度方可以**无差别替换厂商实现**。

- 所有接口、配置、事件结构统一定义在 [ai_plugin_interface/](ai_plugin_interface/)，厂商包只做**实现**，禁止新增面向业务层的公开类型。
- 厂商插件命名：`<能力>_<厂商>`，如 [stt_azure/](stt_azure/)、[tts_azure/](tts_azure/)、[sts_doubao/](sts_doubao/)、[ast_volcengine/](ast_volcengine/)。
- 组合能力（对话/翻译/STS/AST）统一放在 `agent_*` 插件内，不应直接在厂商包里糅合。

---

## 1. 插件分层

| 层级 | 目录 | 职责 |
| --- | --- | --- |
| 接口层 | [ai_plugin_interface/](ai_plugin_interface/) | 抽象类、配置、事件、错误码；**唯一**允许被上层直接依赖 |
| 厂商实现 | `stt_*` / `tts_*` / `sts_*` / `ast_*` / `llm_*` / `translation_*` | 仅实现对应接口，不新增公开 API |
| 组合/调度 | `agent_*` | 编排多能力，只面向 `ai_plugin_interface` 编程 |
| 服务管理 | [service_manager/](service_manager/) / [agents_server/](agents_server/) | 生命周期、配置下发、热切换 |

**铁律**：上层业务（`app/lib/features/**`）**禁止**直接 import 厂商包。

---

## 2. 通用约束

### 2.1 生命周期

所有插件必须实现以下状态机：

```
uninitialized → initialize(config) → ready → (start/speak/chat) → ready → dispose() → disposed
```

- `initialize` 幂等：重复调用需先释放旧资源。
- `dispose` 必须释放**所有**原生资源（WebSocket / AudioTrack / AudioRecord / 定时器 / StreamController），且 `dispose` 后再调用任何方法必须抛出 `StateError`。
- 事件流在 `dispose` 时必须 `close()`，不要泄漏 `StreamController`。

### 2.2 事件流（`Stream<XxxEvent>`）

- **必须** 使用 `StreamController.broadcast()`，允许多订阅。
- 事件派发**必须**在 Dart isolate 主线程（Native 侧通过 `MethodChannel` / `EventChannel` 回到主 isolate 后再 `add`）。
- 事件顺序保证：同一 `requestId` 的事件严格有序，`start → *(中间) → done/error/cancelled` 必然闭合，不能漏派结束事件。
- 错误事件 (`XxxEventType.error`) **不得**关闭事件流，便于后续重试。

### 2.3 `requestId` 语义（核心）

- 同一"轮次"事件共享一个 `requestId`，跨插件串联：**STT.finalResult.requestId == LLM.chat.requestId == TTS.speak.requestId**。
- `requestId` 由**触发方**生成（通常 STT 在 `finalResult` 时生成），下游插件**原样透传**。
- 所有允许打断的插件（LLM / TTS / STS / AST）必须支持"按 `requestId` 取消"，新 `requestId` 到达时旧任务立即终止并派发 `cancelled` / `playbackInterrupted`。

### 2.4 错误码

- `errorCode` 使用 **`<plugin>.<reason>`** 格式，例如 `stt.network_timeout`、`tts.synthesis_failed`、`sts.ws_disconnected`。
- 鉴权、网络、权限三类错误**必须**使用固定码：`auth_failed` / `network_error` / `permission_denied`。
- `errorMessage` 用于调试，**禁止**直接透传给终端用户 UI。

---

## 3. STT 约束

参见 [ai_plugin_interface/lib/src/stt_plugin.dart](ai_plugin_interface/lib/src/stt_plugin.dart)。

### 3.1 文本更新 vs 结果（极其重要）

STT 输出分两种语义，上层拼接策略完全不同：

| 事件 | 语义 | 上层处理 |
| --- | --- | --- |
| `partialResult` | **中间态**，流式更新 | **覆盖模式** — `currentText = event.text`，不累加 |
| `finalResult` | **确定态**，本句已结束 | **累加模式** — `committedText += event.text`；`currentText` 清空 |

上层最终显示文本 = `committedText + currentText`。

**实现方要求**：
- `partialResult.text` 必须是**从本句开头**到当前时刻的累计文本，**不是增量**。上层一旦收到就整体覆盖，厂商不得只发增量片段。
- `finalResult` 派发后，下一次 `partialResult` 必须**重置**为新句起点，不得把上一句内容再带出来。
- 一次 `startListening()` 过程中可产生**多个** `finalResult`（长录音、连续说话），它们在上层按顺序**累加**成完整对话。
- `finalResult.isFinal == true` 且 `text != null && text.isNotEmpty`；空字符串不要派发 finalResult。
- `requestId` **只在** `finalResult` 时生成并赋值，`partialResult` 的 `requestId` 为 `null`。

### 3.2 VAD / 监听

- `listeningStarted` / `listeningStopped` 必须与麦克风真实开关对应，不能提前/延后。
- `vadSpeechStart` / `vadSpeechEnd` 必须在同一句内成对出现；若厂商 SDK 无 VAD，实现方需用能量阈值或时间窗自行模拟。
- `stopListening()` 后厂商若已经在处理尾包，**必须**先派发尾部 `finalResult` 再派发 `listeningStopped`。

### 3.3 权限 & 冲突

- `RECORD_AUDIO` 权限检查由插件自身处理，失败派发 `error(code=permission_denied)`，禁止抛出未捕获异常。
- 与 STS / AST 插件的麦克风**互斥**；调度层保证不会同时启动，但插件自身在启动时若检测到冲突需派发 `error(code=audio_busy)` 而不是静默失败。

---

## 4. TTS 约束

参见 [ai_plugin_interface/lib/src/tts_plugin.dart](ai_plugin_interface/lib/src/tts_plugin.dart)。

### 4.1 文本合成频率 / 缓存（配合 LLM 流式）

LLM 流式输出会**逐 token**到达，TTS 不能每来一个字就请求一次合成。实现方**必须内置**以下策略：

1. **句子切分缓存（Sentence Buffer）**
   - 输入文本累积到遇到句子终结符（`。！？.!?;；\n` 以及中英文逗号后 > N 字）才触发一次合成请求。
   - 文本末尾若未遇终结符，由调用方通过显式 `flush` / `speak(finalChunk=true)` 触发（接口未来扩展）；当前版本要求 `speak()` 的每次调用都视作**一个完整语义段**。

2. **合成节流（Synthesis Throttle）**
   - 同一 `requestId` 的多段文本进入**合成队列**，并发合成数 ≤ 2，避免厂商 QPS 限流。
   - 队列中的段按顺序**播放**（FIFO），不得乱序。

3. **音频缓冲预加载（Playback Cache）**
   - 第一段 `synthesisReady` 立即开始播放；后续段边合成边入队，播放指针跨段无缝衔接。
   - 播放器内部 PCM 缓冲至少维持 200ms，防止卡顿。

4. **打断（Interruption）**
   - 收到新的 `requestId` 或显式 `stop()`：立即清空合成队列 + 停止当前播放 + 派发一次 `playbackInterrupted`，**不得**等待当前段合成完毕。
   - 打断后旧 `requestId` 的后续事件必须全部丢弃，不得再派发。

### 4.2 事件约束

- `synthesisStart` → `synthesisReady` → `playbackStart` → `playbackProgress*` → `playbackDone` 必须严格有序闭合，或被 `playbackInterrupted` / `error` 替代。
- `playbackProgress` 派发频率：**100ms ±20ms 一次**，不得过密（>20Hz）也不得过疏（<5Hz）。
- `synthesisReady.durationMs` 必须是本段音频实际时长；未知时置 `null`，**不得**用 0 冒充。

---

## 5. STS / AST 约束（端到端）

STS 参见 [ai_plugin_interface/lib/src/sts_plugin.dart](ai_plugin_interface/lib/src/sts_plugin.dart)；
AST 参见 [ai_plugin_interface/lib/src/ast_plugin.dart](ai_plugin_interface/lib/src/ast_plugin.dart)。

### 5.1 通用

- 长连接 WebSocket：`startCall` 建连成功后**必须**派发 `connected`；断连派发 `disconnected`（区分主动/被动，被动需额外 `error`）。
- `sendAudio(pcmData)`：PCM 16bit mono 16kHz（小端），非该格式由插件内部重采样，**不要**把责任甩给上层。
- 心跳：空闲 15s 无数据时发送心跳帧，超时 30s 判定断连。
- 自动重连：**不做**。断连直接抛出 `disconnected + error`，由上层 `agent_sts_chat` / `agent_ast_translate` 容器决策。

### 5.2 STS 特有

- `audioChunk.audioData` 为 PCM（或 Opus，视厂商；需在 `extraParams` 里标注 `audio_format`），**一次响应的音频必须属于同一 `requestId`**。
- 打断：调用方重新 `sendAudio` 用户语音开始时，插件须主动丢弃尚未下发的 `audioChunk` 并派发一次 `sentenceDone(text=null)` 表示上一句被抢占。

### 5.3 AST 特有

- `sourceSubtitle` / `translatedSubtitle` 遵循与 STT 相同的 **"覆盖 vs 累加"** 规则：中间字幕覆盖，句末字幕累加。厂商 SDK 无此区分时需由插件自行判定终结。
- `sourceSubtitle.text` 与 `translatedSubtitle.text` **必须同句成对**；若厂商只提供翻译，`sourceSubtitle` 可省略但不得错位。

---

## 6. LLM 约束

参见 [ai_plugin_interface/lib/src/llm_plugin.dart](ai_plugin_interface/lib/src/llm_plugin.dart)。

- `chat()` 返回的 Stream **每次调用独立创建**，不要复用。
- 流式事件：`firstToken` 只派发一次（首字节到达时），后续文本通过 `done.textDelta` 或 `done.fullText` 给出——**单次 `chat` 必然以 `done` / `cancelled` / `error` 之一闭合**。
- 工具调用：`toolCallStart` 带完整 `ToolCall.name`，`toolCallArguments` 流式追加 `argumentsJson`，上层在 `toolCallResult` 到来前**不得**执行工具；工具执行由调度层做，不在插件内。
- `cancel(requestId)` 必须幂等、线程安全；取消后派发一次 `cancelled` 并关闭对应 Stream。

---

## 7. 翻译（文本）约束

参见 [ai_plugin_interface/lib/src/translation_plugin.dart](ai_plugin_interface/lib/src/translation_plugin.dart)。

- 无 `requestId`、无事件流、无打断。每次 `translate()` 独立 Future。
- 失败以 `Future.error` 返回 `TranslationException(code, message)`（实现方自定义，code 遵循 §2.4）。
- **禁止**在此接口里混入语音/TTS 能力。

---

## 8. 原生侧（Android / iOS）规范

- `MethodChannel` 命名：`com.aiagent.<plugin_name>/method`；`EventChannel`：`com.aiagent.<plugin_name>/events`。
- 事件 payload 为 `Map<String, Object?>`，key 用 `snake_case`，Dart 侧统一解码到对应 `XxxEvent`。
- 音频采集 / 播放使用系统原生 API（Android: `AudioRecord`/`AudioTrack`；iOS: `AVAudioEngine`），禁止自带第三方音频库。
- 所有 Native 回调必须 `runOnUiThread` / `DispatchQueue.main` 再下发到 Flutter，避免跨线程 Channel 调用崩溃。

---

## 9. 新增厂商插件 Checklist

1. 在 [ai_plugin_interface/](ai_plugin_interface/) 找到对应抽象类，**不要**改动接口。如需改动，先提案到本文件 §2 / §3 统一规范。
2. 新建 `<能力>_<厂商>/` 目录，`pubspec.yaml` 声明依赖 `ai_plugin_interface`。
3. 实现类以 `XxxPluginImpl` 命名，在 [service_manager/](service_manager/) 的工厂中注册。
4. 自测：覆盖 §2.1 生命周期、§2.3 `requestId` 打断、§3.1 / §4.1 / §5.3 的文本语义三项。
5. 更新 [app/lib/features/services/](../lib/features/services/) 的 UI 配置表单（apiKey / region / 方言等）。
