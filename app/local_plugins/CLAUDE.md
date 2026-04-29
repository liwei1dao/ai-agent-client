# local_plugins 约束文档

本目录下所有插件必须遵守以下规范，目的是让 `agent_chat` / `agent_sts_chat` / `agent_translate` / `agent_ast_translate` / `agents_server` / `service_manager` 等上层调度方可以**无差别替换厂商实现**。

- 所有接口、配置、事件结构统一定义在 [ai_plugin_interface/](ai_plugin_interface/)，厂商包只做**实现**，禁止新增面向业务层的公开类型。
- 厂商插件命名：`<能力>_<厂商>`，如 [stt_azure/](stt_azure/)、[tts_azure/](tts_azure/)、[sts_volcengine/](sts_volcengine/)、[ast_volcengine/](ast_volcengine/)。
- 组合能力（对话/翻译/STS/AST）统一放在 `agent_*` 插件内，不应直接在厂商包里糅合。

---

## 1. 插件分层

AI 域、设备域、复合场景域三轨**正交**：

| 域 | 接口层 | 厂商实现 | 调度/容器 |
| --- | --- | --- | --- |
| AI 能力 | [ai_plugin_interface/](ai_plugin_interface/) | `stt_*` / `tts_*` / `sts_*` / `ast_*` / `llm_*` / `translation_*` | `agent_*` / [service_manager/](service_manager/) / [agents_server/](agents_server/) |
| 硬件设备 | [device_plugin_interface/](device_plugin_interface/) | `device_<vendor>`（杰理 / 恒玄 / 高通 / 中科蓝讯 …） | [device_manager/](device_manager/) + `agents_server` 内的 `DeviceAgentRouter` |
| 复合场景 | （无独立接口层） | （无） | [translate_server/](translate_server/) — 双向通话翻译 / 面对面 / 音视频翻译 |

**铁律**：
- 上层业务（`app/lib/features/**`）**禁止**直接 import 厂商包；
- AI 厂商插件**禁止**依赖 `device_plugin_interface` 或 `translate_server`；设备厂商插件**禁止**依赖 `ai_plugin_interface` 或 `translate_server`；
- `translate_server` 只能依赖 `device_plugin_interface`；agent 集成走 `TranslateAgentRunner` 抽象，由 app 层注入；
- 设备 ↔ agent 的协调全部走 `device_manager` 暴露的端口/触发器；复合场景的协调走 `translate_server`。

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

- 长连接 WebSocket / WebRTC：`startCall` 建连成功后**必须**派发 `connected`；断连派发 `disconnected`（区分主动/被动，被动需额外 `error`）。
- `sendAudio(pcmData)`：PCM 16bit mono 16kHz（小端），非该格式由插件内部重采样，**不要**把责任甩给上层。Web 端浏览器自驱麦克风时可为 no-op。
- 心跳：空闲 15s 无数据时发送心跳帧，超时 30s 判定断连。
- 自动重连：**不做**。断连直接抛出 `disconnected + error`，由上层 `agent_sts_chat` / `agent_ast_translate` 容器决策。

### 5.2 STS 事件协议（识别 5 件套 + 合成 4 件套 + 播报 + 音频）

STS 是"识别 + 合成 + 播报"的合体，`StsEventType` 覆盖三个生命周期 + 连接 + 音频 + 错误，事件定义见 [sts_plugin.dart](ai_plugin_interface/lib/src/sts_plugin.dart)。

**识别生命周期**（user / bot 两侧共用，通过 `StsRole` 区分；每个事件**必带** `requestId`）：

| 阶段 | `text` 语义 | 消费端策略 |
|---|---|---|
| `recognitionStart` | 无 | 新建本 role 的段落缓冲 |
| `recognizing` | **累计快照**（从本段起点到当前） | **覆盖模式**：`current = event.text` |
| `recognized` | **本段定稿** | **累加模式**：`committed += event.text`；`current` 清空；**后续 role 仍可继续出现新的 `recognizing`** |
| `recognitionDone` | 无 | 本 role 的识别链路闭合（用户断句说完 / bot 文本全部送完） |
| `recognitionEnd` | 无 | 整个 `requestId` 回合关闭（所有 role 都 done 之后派发，**role=null**） |
| `recognitionError` | 无 | 错误，不关闭流；后续仍须补齐缺失的 Done / End |

**闭合铁律**：
- 每个 `recognitionStart(role)` 必然以 `recognitionDone(role)` 闭合；每个 `recognitionStart` 所属的 requestId 必然以 `recognitionEnd` 闭合。
- `error` / `recognitionError` **不关闭事件流**，但发生错误时插件必须补齐缺失的 `Done` / `End`，避免上层状态机悬挂。
- 用户抢占（新用户说话打断当前回合）：插件须自行 `recognitionDone → recognitionEnd` 旧 requestId，然后开新回合。

**合成生命周期**（`role = bot`，仅云端 TTS 流；WebRTC 端到端音频流插件可不派发合成事件）：

`synthesisStart → synthesizing* → synthesized* → synthesisEnd`；任一阶段可伴随 `synthesisError`（不关流）。

**播报 + 音频**（`role = bot`）：

- `playbackStart → audioChunk* → playbackEnd`
- `audioChunk.audioData` 为 PCM（或 Opus），首帧必须带 `audioFormat`
- `playbackEnd.interrupted = true` 表示被新 requestId 抢占或 teardown 打断

### 5.3 STS `requestId` 贯通规则

- **生成**：user 侧 `recognitionStart` 时生成；格式 `sts_<vendor>_<unixMs>_<rand6>`。
- **bot 主动发起**（无用户前导）：首帧（`bot_response_start` / chat_ended 等）由插件本地补生成，仍须走完整的 start→end 生命周期。
- **贯通**：一个回合内所有事件（识别、合成、播报、audioChunk）共享同一 requestId。
- **透传**：`agent_sts_chat` 容器桥接到 `LlmEvent.requestId` 时**原样透传**，不得重生成。

### 5.4 STS 插件自检清单

1. 覆盖 §2.1 生命周期（dispose 后任何方法抛 `StateError`）。
2. `recognizing.text` 必须是累计快照，**禁止**每帧只送增量。服务器若只发增量，插件自行累加后再发。
3. 每个 `recognitionStart` 必有配对 `recognitionDone`（同 role、同 requestId）；每个 requestId 必有一次 `recognitionEnd`。
4. 断连 / 异常时必须派发缺失的 `recognitionDone` / `recognitionEnd` / `playbackEnd(interrupted=true)`。
5. 空文本禁止派发 `recognized`。

### 5.5 AST 特有（待迁移到同协议）

- 当前 `AstEventType` 仍是旧版 `sourceSubtitle` / `translatedSubtitle` / `ttsAudioChunk`。
- **待办**：按 §5.2 升级到 `recognitionStart/recognizing/recognized/recognitionDone/recognitionEnd` 五件套 + 合成 + 播报，`AstRole { source, translated }` 区分两路字幕；`source` 侧负责生成 requestId。详见 P4 计划。

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

---

## 10. 设备域（device_plugin_interface / device_manager）

参见 [device_plugin_interface/lib/device_plugin_interface.dart](device_plugin_interface/lib/device_plugin_interface.dart)、[device_manager/lib/device_manager.dart](device_manager/lib/device_manager.dart)。

### 10.1 分层

- **接口层** [device_plugin_interface/](device_plugin_interface/)：`DevicePlugin` / `DeviceSession` / `DeviceManager` 抽象 + `AudioFormat` / `AudioFrame` / `DeviceAgentTrigger` 等数据类型；**唯一**允许被业务层直接依赖的设备域包。
- **厂商实现** `device_<vendor>/`：仅实现 `DevicePlugin` + `DeviceSession`，封装具体 SDK（杰理 RCSP、恒玄 BES SDK、高通 QCC 等）。
- **容器层** [device_manager/](device_manager/)：`DefaultDeviceManager` 单设备路由器；负责厂商工厂注册、热切换、单 active session、音频端口分配、唤醒触发器派发。

### 10.2 单设备 / 单 vendor 模型

- `DeviceManager.activeSession` 至多一个；`connect(newId)` 内部自动断开旧 session。
- `useVendor(key)` 是原子操作：`stopScan → disconnect → 旧 plugin.dispose → 新 plugin.initialize → vendorChanged`。切换中所有 scan/connect 抛 `device.vendor_switching`。
- 多 SDK 同进程并存大概率冲突蓝牙栈，故同时只能有一个 plugin 处于 `initialized`。

### 10.3 状态机（细化两阶段）

```
disconnected → connecting → linkConnected → ready → disconnecting → disconnected
```

`linkConnected` 是"蓝牙链路已建但厂商私有协议（如杰理 RCSP、QCC GAIA）尚未握手"的中间态；`DevicePlugin.connect` **必须**等到 `ready` 才 resolve，握手失败抛 `device.handshake_failed`。

### 10.4 音频端口（核心）

业务层不直接动 mic/spk，全部走 `DeviceManager.acquireAudioPort(downlink: ...)` 拿到的 [AgentAudioPort]：

- 上行（`DeviceAudioSource`）：耳机麦 → app；接口层规定**统一格式** [AudioFormat.standard]（Opus / 16 kHz / mono / 20 ms）。厂商 SDK 给的不是这个规格，**必须**在厂商插件内部转换；转不了 `initialize` 阶段抛 `device.format_unsupported`。
- 下行（`DeviceAudioSink`）：app TTS → 耳机；同样统一格式。能力 `speakerDownlink` 不被厂商声明时该方法抛 `device.not_supported`，由路由器改走 `AudioDownlinkSink.phone`（系统扬声器，由 agent 自行播放）。
- 单端口独占：`acquireAudioPort` 已被占用时抛 `device.audio_busy`；`AgentAudioPort.close()` 归还槽位。
- 端口与 agent 绑定：通话翻译类 agent 用 `downlink: device`；AI 唤醒对话用 `downlink: phone`。

### 10.5 设备触发 agent（DeviceAgentRouter）

- 设备本地唤醒（PTT、语音唤醒、翻译键、挂断键）由厂商插件解析为 [DeviceWakeEvent]，容器把它翻译成 [DeviceAgentTrigger]，从 `DeviceManager.agentTriggers` 派发。
- `agents_server` 中的 `DeviceAgentRouter` 监听该流，按"默认聊天 agent / 默认翻译 agent"两个配置项启动对应 agent；新触发到达时**无条件 cancel** 旧 agent + close port，再启新的。
- `WakeReason → DeviceAgentTriggerKind` 映射：`ptt|voiceWake → chat`，`translateKey → translate`，`hangup → stop`。

### 10.6 错误码

统一使用 `DeviceErrorCode` 命名空间（`device.<reason>`）：`permission_denied` / `bluetooth_off` / `connect_timeout` / `connect_failed` / `handshake_failed` / `disconnected_remote` / `audio_busy` / `not_supported` / `format_unsupported` / `vendor_switching` / `no_active_session` / `plugin_not_initialized` 等。所有插件方法**禁止**让原始 SDK 异常逃逸，要么转 [DeviceException]，要么以 `error` 事件派发。

### 10.7 通用语义事件

`DeviceFeatureEvent.key` 命名空间：

- `common.<name>`：跨厂商通用（`battery`, `wear.on`, `wear.off`, `key.click`, `key.double_click`, `key.long_press`, `anc.changed` ...）
- `<vendor>.<name>`：厂商私有；业务层若消费需注明强耦合。

通用事件**必须**由厂商插件翻译后再派发；通用 `device_ble` 仅产 `connectionStateChanged + raw`，私有→通用的语义映射在 `device_<vendor>` 内做。

### 10.8 新增设备厂商插件 Checklist

1. 新建 `device_<vendor>/`，`pubspec.yaml` 依赖 `device_plugin_interface`。
2. 实现 `DevicePlugin`（vendorKey、capabilities、configSchema）+ `DeviceSession`。
3. 在 `DevicePlugin.initialize` 中完成 SDK 启动 + 事件订阅；任何 SDK 启动失败抛 `DeviceException`，容器自动禁用厂商。
4. `connect` 必须等到协议握手完成（`ready`）再 resolve；中间态走 `linkConnected`。
5. 音频通道：实现 `openMicUplink` / `openSpeakerDownlink`，输出/接受统一 [AudioFormat.standard]；不支持的方向直接抛 `device.not_supported`。
6. 把私有按键/唤醒事件翻译为 [WakeReason]，通过 `DevicePluginEvent(type: wakeTriggered, wake: ...)` 派发；按键/佩戴/电量翻译为 `DeviceFeatureEvent('common.<name>')`。
7. 在 [device_manager/](device_manager/) 的注册位置（业务侧统一启动代码）`registerVendor(yourDescriptor)`。
8. 自测：覆盖 §10.3 状态机、§10.4 音频独占、§10.6 错误码三项。

---

## 11. 复合场景域（translate_server）

参见 [translate_server/lib/translate_server.dart](translate_server/lib/translate_server.dart)。

### 11.1 定位

`translate_server` 是**复合场景编排器**，专门处理"需要把多个 agent + 设备硬件通道拼起来"的业务，目前覆盖：

- **通话翻译**（`startCallTranslation`）：双向、2 个 agent、走耳机 RCSP 翻译通道（杰理 `MODE_CALL_TRANSLATION`）。**当前唯一已落地的业务**。
- **面对面翻译**（`startFaceToFaceTranslation`）：占位，待硬件方案确认。
- **音视频翻译**（`startAudioTranslation`）：占位，输入源为手机系统媒体回采。

### 11.2 依赖与边界

- 仅依赖 [device_plugin_interface/](device_plugin_interface/)；**禁止**依赖 `agents_server` / `agent_*` / `device_jieli` 等具体厂商包。
- agent 接入走 `TranslateAgentRunner` / `TranslateAgentRunnerFactory` 抽象——由 app 层（`core/services/translate_service.dart`）实现并注入。
- `device_manager` / `agents_server` **不允许**反向依赖 `translate_server`。

### 11.3 单 active session 模型

`TranslateServer.activeSession` 至多一个，**三种业务互斥**。新 `start*` 调用会先 `await _stopActive()`，旧 session 走完 `stopping → stopped` 再启动新的。

### 11.4 通话翻译数据流（已实现）

```
device.eventStream
  └─ feature.key=='jieli.translation.audio'
       ├─ source==eScoUpLink   → uplinkRunner.sendAudio(opus)
       └─ source==eScoDownLink → downlinkRunner.sendAudio(opus)

uplinkRunner.events (user→peer)
  ├─ partial → subtitles{role: user, stage: partial}
  └─ final   → subtitles{role: user, stage: finalized}
              + device.invokeFeature('jieli.translation.reportResult',
                  ttsAudio=opus, ttsSource=eScoUpLink) // 对方听到

downlinkRunner.events (peer→user) 对称：ttsSource=eScoDownLink // 用户耳机听到
```

铁律：

- **零转码**：通话翻译默认使用 mono 模式（`upgradeCallToStereo=false`），耳机给的就是 `AudioFormat.standard`（OPUS / 16 kHz / mono / 20 ms），按 source 字段直接分流，pipeline 不做 OPUS 解码 / 重新编码。
- **TTS 编码**：agent runner 必须输出 OPUS 帧；如果 agent 内部 TTS 是 PCM，runner 自己负责重新编码。
- **错误不关流**：错误派发到 `errors` 流后 session 仍然 active；调用方决定是否 `stop()`。设备掉线 / 耳机端退出翻译模式 → pipeline 自动 `stop()`。

### 11.5 错误码

`translate.<reason>`：`no_device` / `not_supported` / `vendor_mismatch` / `session_busy` / `agent_failed` / `enter_mode_failed` / `exit_mode_failed` / `device_disconnected` / `invalid_argument` / `not_implemented`。

### 11.6 新增复合场景 Checklist

1. 在 [src/translate_request.dart](translate_server/lib/src/translate_request.dart) 加请求类型；
2. 在 [src/translate_session.dart](translate_server/lib/src/translate_session.dart) 加 session 子类（仅打 `kind` 标签）；
3. 在 `pipeline/` 加 `<scenario>_pipeline.dart`，按 `_Leg` + `consumeSource` + `ttsSink` 模板填表；
4. 在 [src/default_translate_server.dart](translate_server/lib/src/default_translate_server.dart) 加 `start*` 方法；
5. 设备能力按需加 `DeviceCapability.onDevice<Scenario>`，并在厂商插件 capabilities 集合里声明；
6. 自测：覆盖单 active session 互斥、错误不关流、设备掉线自动收尾。
