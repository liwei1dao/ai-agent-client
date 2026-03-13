# 接口规范文档 (API Specification)

**项目名称**：AI Agent Client
**版本**：v1.3
**日期**：2026-03-12
**变更**：新增 ServiceConfig / ServiceLibrary 数据模型；更新 AgentConfig 以引用 serviceId 替代直接指定 Provider 类型

> 本文档定义所有接口规范：
> - **ai_plugin_interface**（共享 Dart 包）：Provider 抽象接口 + Pigeon 消息定义，所有插件必须实现
> - **local_plugins/stt_xxx 等**（各厂商插件包）：实现上述接口，含原生 Kotlin/Swift 代码
> - **主 App**：通过 Provider Registry 选取当前激活插件，Agent 层编排业务流程

---

## 1. 数据模型

### 1.1 消息模型

```dart
// lib/models/message.dart

enum MessageRole { user, assistant, system }

class Message {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isStreaming;        // 是否正在流式输出中

  const Message({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isStreaming = false,
  });

  Message copyWith({String? content, bool? isStreaming});
}
```

### 1.2 STT 结果模型

```dart
// lib/models/stt_result.dart

enum SttResultType { partial, final_ }

class SttResult {
  final String text;             // 识别文本
  final SttResultType type;      // partial（中间结果）或 final（最终结果）
  final double? confidence;      // 置信度 0.0 ~ 1.0
  final String? language;        // 检测到的语言（如 "zh-CN"）

  const SttResult({
    required this.text,
    required this.type,
    this.confidence,
    this.language,
  });
}
```

### 1.3 TTS 请求模型

```dart
// lib/models/tts_request.dart

class TtsRequest {
  final String text;             // 待合成文本
  final String language;         // 语言代码，如 "zh-CN"
  final String? voice;           // 音色名称（各厂商格式不同）
  final double? speedRate;       // 语速倍率，1.0 = 正常
  final double? pitchRate;       // 音调倍率，1.0 = 正常
  final int? sampleRate;         // 输出采样率，默认 16000
  final AudioFormat format;      // 输出音频格式

  const TtsRequest({
    required this.text,
    required this.language,
    this.voice,
    this.speedRate = 1.0,
    this.pitchRate = 1.0,
    this.sampleRate = 16000,
    this.format = AudioFormat.mp3,
  });
}

enum AudioFormat { mp3, pcm, wav, ogg }
```

### 1.4 翻译结果模型

```dart
// lib/models/translation_result.dart

class TranslationResult {
  final String sourceText;       // 原文
  final String translatedText;   // 译文
  final String sourceLang;       // 源语言（如 "auto" 或 "zh"）
  final String detectedLang;     // 实际检测到的语言
  final String targetLang;       // 目标语言
  final String providerName;     // 使用的服务商名称

  const TranslationResult({
    required this.sourceText,
    required this.translatedText,
    required this.sourceLang,
    required this.detectedLang,
    required this.targetLang,
    required this.providerName,
  });
}
```

### 1.5 LLM 响应模型

```dart
// lib/models/llm_response.dart

class LlmResponse {
  final String content;          // 回复文本
  final bool isDone;             // 是否为最终结果（流式模式中使用）
  final LlmUsage? usage;         // Token 使用统计（非流式时有值）

  const LlmResponse({
    required this.content,
    required this.isDone,
    this.usage,
  });
}

class LlmUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
}
```

### 1.6 统一异常模型

```dart
// lib/core/errors/app_exception.dart

enum AppErrorType {
  network,           // 网络错误
  authentication,    // 认证失败（API Key 无效）
  rateLimited,       // 限流
  invalidRequest,    // 请求参数错误
  providerError,     // 服务商内部错误
  audioPermission,   // 麦克风权限被拒
  unsupported,       // 当前 Provider 不支持该功能
  timeout,           // 超时
  unknown,
}

class AppException implements Exception {
  final AppErrorType type;
  final String message;
  final String? providerName;    // 哪个 Provider 报错
  final dynamic originalError;

  const AppException({
    required this.type,
    required this.message,
    this.providerName,
    this.originalError,
  });
}
```

---

## 2. STT Provider 接口

### 2.1 抽象接口

```dart
// lib/providers/stt/stt_provider.dart

abstract class SttProvider {
  /// Provider 标识名称，用于日志和错误追踪
  String get name;

  /// 是否支持实时流式识别
  bool get supportsStreaming;

  /// 开始实时流式识别（持续录音场景）
  /// 返回识别结果流，调用 stopStream() 结束
  /// 抛出 AppException 当初始化失败
  Stream<SttResult> startStream({
    required String language,    // 如 "zh-CN", "en-US"
    int sampleRate = 16000,
    int channels = 1,
  });

  /// 停止实时流式识别
  Future<void> stopStream();

  /// 一次性识别（适用于已有音频文件/字节）
  /// [audioData] PCM 格式原始音频数据
  Future<SttResult> recognize({
    required Uint8List audioData,
    required String language,
    int sampleRate = 16000,
  });

  /// 释放资源
  Future<void> dispose();
}
```

### 2.2 Provider 枚举

```dart
// lib/providers/stt/stt_provider_type.dart

enum SttProviderType {
  azure('Azure Speech'),
  google('Google Cloud STT'),
  aliyun('Aliyun STT'),
  doubao('Doubao STT');

  final String displayName;
  const SttProviderType(this.displayName);
}
```

### 2.3 Provider 工厂

```dart
// lib/providers/stt/stt_factory.dart

class SttFactory {
  static SttProvider create(SttProviderType type, AppConfig config) {
    return switch (type) {
      SttProviderType.azure   => AzureSttProvider(config),
      SttProviderType.google  => GoogleSttProvider(config),
      SttProviderType.aliyun  => AliyunSttProvider(config),
      SttProviderType.doubao  => DoubaoSttProvider(config),
    };
  }
}
```

### 2.4 各厂商配置要求

| Provider | 必填配置 Key |
|----------|-------------|
| Azure STT | `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION` |
| Google STT | `GOOGLE_SPEECH_API_KEY` 或 Service Account JSON |
| Aliyun STT | `ALIYUN_STT_APP_KEY`, `ALIYUN_STT_TOKEN` |
| Doubao STT | `DOUBAO_STT_APP_ID`, `DOUBAO_STT_TOKEN` |

---

## 3. TTS Provider 接口

### 3.1 抽象接口

```dart
// lib/providers/tts/tts_provider.dart

abstract class TtsProvider {
  /// Provider 标识名称
  String get name;

  /// 是否支持流式合成（边合成边播放）
  bool get supportsStreaming;

  /// 合成语音并返回音频字节数据（一次性）
  Future<Uint8List> synthesize(TtsRequest request);

  /// 流式合成，返回音频数据流（适用于长文本）
  /// 每个 Uint8List 是一个音频数据块
  Stream<Uint8List> synthesizeStream(TtsRequest request);

  /// 获取该 Provider 支持的音色列表
  Future<List<TtsVoice>> getAvailableVoices({String? language});

  /// 释放资源
  Future<void> dispose();
}

class TtsVoice {
  final String id;               // 音色 ID（传给 TtsRequest.voice）
  final String displayName;      // 展示名称
  final String language;         // 支持的语言
  final String? gender;          // "male" | "female" | "neutral"
  final String? style;           // 风格描述（如 "conversational"）
}
```

### 3.2 Provider 枚举

```dart
// lib/providers/tts/tts_provider_type.dart

enum TtsProviderType {
  azure('Azure TTS'),
  google('Google Cloud TTS'),
  aliyun('Aliyun TTS'),
  doubao('Doubao TTS');

  final String displayName;
  const TtsProviderType(this.displayName);
}
```

### 3.3 各厂商配置要求

| Provider | 必填配置 Key |
|----------|-------------|
| Azure TTS | `AZURE_SPEECH_KEY`, `AZURE_SPEECH_REGION` |
| Google TTS | `GOOGLE_TTS_API_KEY` |
| Aliyun TTS | `ALIYUN_TTS_APP_KEY`, `ALIYUN_TTS_TOKEN` |
| Doubao TTS | `DOUBAO_TTS_APP_ID`, `DOUBAO_TTS_TOKEN` |

---

## 4. LLM Provider 接口

### 4.1 抽象接口

```dart
// lib/providers/llm/llm_provider.dart

abstract class LlmProvider {
  /// Provider 标识名称
  String get name;

  /// 支持的最大 context 长度（tokens）
  int get maxContextLength;

  /// 非流式对话（等待完整回复）
  Future<LlmResponse> chat({
    required List<Message> messages,
    String? model,               // 不传则使用 Provider 默认 model
    double? temperature,
    int? maxTokens,
  });

  /// 流式对话（逐 token 返回）
  /// Stream 中每个 LlmResponse.isDone=false 表示中间 token
  /// 最后一个 LlmResponse.isDone=true 表示结束
  Stream<LlmResponse> chatStream({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  });

  /// 取消正在进行的请求
  Future<void> cancel();

  /// 释放资源
  Future<void> dispose();
}
```

### 4.2 Provider 枚举

```dart
// lib/providers/llm/llm_provider_type.dart

enum LlmProviderType {
  openai('OpenAI'),
  claude('Anthropic Claude'),
  gemini('Google Gemini'),
  qwen('Alibaba Qwen'),
  doubao('Doubao LLM'),
  deepseek('DeepSeek');

  final String displayName;
  const LlmProviderType(this.displayName);
}
```

### 4.3 各厂商配置要求

| Provider | 必填配置 Key | 默认 Model |
|----------|-------------|------------|
| OpenAI | `OPENAI_API_KEY`, 可选 `OPENAI_BASE_URL` | gpt-4o |
| Claude | `CLAUDE_API_KEY` | claude-sonnet-4-6 |
| Gemini | `GEMINI_API_KEY` | gemini-2.0-flash |
| Qwen | `QWEN_API_KEY` | qwen-turbo |
| Doubao LLM | `DOUBAO_LLM_API_KEY`, `DOUBAO_LLM_ENDPOINT_ID` | - |
| DeepSeek | `DEEPSEEK_API_KEY` | deepseek-chat |

---

## 5. Translation Provider 接口

### 5.1 抽象接口

```dart
// lib/providers/translation/translation_provider.dart

abstract class TranslationProvider {
  /// Provider 标识名称
  String get name;

  /// 翻译文本
  /// [sourceLang] 传 "auto" 表示自动检测
  Future<TranslationResult> translate({
    required String text,
    required String targetLang,  // 如 "zh", "en", "ja"
    String sourceLang = 'auto',
  });

  /// 批量翻译
  Future<List<TranslationResult>> translateBatch({
    required List<String> texts,
    required String targetLang,
    String sourceLang = 'auto',
  });

  /// 检测语言
  Future<String> detectLanguage(String text);

  /// 获取支持的语言列表
  Future<List<LanguageInfo>> getSupportedLanguages();

  /// 释放资源
  Future<void> dispose();
}

class LanguageInfo {
  final String code;             // 语言代码，如 "zh"
  final String name;             // 中文名，如 "中文"
  final String nativeName;       // 本地名，如 "中文"
}
```

### 5.2 Provider 枚举

```dart
// lib/providers/translation/translation_provider_type.dart

enum TranslationProviderType {
  deepl('DeepL'),
  google('Google Translate'),
  aliyun('Aliyun Translate'),
  youdao('Youdao Translate');

  final String displayName;
  const TranslationProviderType(this.displayName);
}
```

### 5.3 各厂商配置要求

| Provider | 必填配置 Key |
|----------|-------------|
| DeepL | `DEEPL_API_KEY` |
| Google Translate | `GOOGLE_TRANSLATE_API_KEY` |
| Aliyun Translate | `ALIYUN_TRANSLATE_ACCESS_KEY`, `ALIYUN_TRANSLATE_SECRET_KEY` |
| Youdao | `YOUDAO_API_KEY`, `YOUDAO_API_SECRET` |

---

## 6. Service Library 数据模型

### 6.1 ServiceConfig（服务配置实体）

```dart
// lib/registry/service_library.dart

enum ServiceType { stt, tts, llm, translation }

/// 用户在 Services Tab 中配置的单个服务实例
class ServiceConfig {
  final String serviceId;         // 用户命名，全局唯一，如 "Azure 中文语音"
  final ServiceType type;
  final String vendor;            // 厂商标识，如 "azure" / "openai"
  final String displayName;       // 界面展示名
  final String apiKey;            // 主鉴权 Key
  final String? secretKey;        // 部分厂商需要（如阿里云 appKey+token）
  final String? region;           // Azure 需要
  final String? model;            // LLM 指定模型，如 "gpt-4o"
  final String? defaultVoice;     // TTS 默认音色
  final bool isConnected;         // 最近一次连接测试结果
  final Map<String, dynamic> extra; // 厂商特有扩展参数

  const ServiceConfig({
    required this.serviceId,
    required this.type,
    required this.vendor,
    required this.displayName,
    required this.apiKey,
    this.secretKey,
    this.region,
    this.model,
    this.defaultVoice,
    this.isConnected = false,
    this.extra = const {},
  });
}
```

### 6.2 AgentConfig（Agent 配置实体）

```dart
// lib/agents/agent_config.dart

enum AgentType { chat, translate }

/// Agent 配置基类（引用 serviceId，不直接依赖 Provider 类型）
abstract class AgentConfig {
  final String agentId;
  final String agentName;
  final AgentType type;
}

/// Chat Agent 配置
class ChatAgentConfig extends AgentConfig {
  final String llmServiceId;      // 必选：引用 ServiceLibrary 中的 LLM 服务
  final String? sttServiceId;     // 可选：引用 STT 服务（语音输入）
  final String? ttsServiceId;     // 可选：引用 TTS 服务（语音输出）
  final String? ttsVoice;         // 可选：覆盖服务默认音色
  final String systemPrompt;      // 系统提示词
  final String sttLanguage;       // STT 识别语言，如 "zh-CN"
  final int maxHistoryMessages;   // 保留历史消息数量
  final bool enableVoiceOutput;   // 是否启用语音输出
  final bool enableVoiceInput;    // 是否启用语音输入

  const ChatAgentConfig({
    required super.agentId,
    required super.agentName,
    super.type = AgentType.chat,
    required this.llmServiceId,
    this.sttServiceId,
    this.ttsServiceId,
    this.ttsVoice,
    this.systemPrompt = '',
    this.sttLanguage = 'zh-CN',
    this.maxHistoryMessages = 20,
    this.enableVoiceOutput = false,
    this.enableVoiceInput = false,
  });
}

/// Translate Agent 配置
class TranslateAgentConfig extends AgentConfig {
  final String translationServiceId; // 必选：引用翻译服务
  final String? sttServiceId;        // 可选：语音输入
  final String? ttsServiceId;        // 可选：译文朗读
  final String? ttsVoice;            // 可选：目标语言音色
  final String sourceLanguage;       // 源语言，"auto" 表示自动检测
  final String targetLanguage;       // 目标语言

  const TranslateAgentConfig({
    required super.agentId,
    required super.agentName,
    super.type = AgentType.translate,
    required this.translationServiceId,
    this.sttServiceId,
    this.ttsServiceId,
    this.ttsVoice,
    this.sourceLanguage = 'auto',
    this.targetLanguage = 'zh-CN',
  });
}
```

---

## 7. Agent 接口

### 7.1 BaseAgent 抽象基类

```dart
// lib/agents/base_agent.dart

abstract class BaseAgent {
  /// Agent 名称（用于日志）
  String get name;

  /// Agent 当前状态
  AgentStatus get status;

  /// Agent 状态变化流
  Stream<AgentStatus> get statusStream;

  /// 初始化 Agent（加载 Provider、建立连接等）
  Future<void> initialize();

  /// 销毁 Agent，释放所有资源
  Future<void> dispose();

  /// 更新配置（动态切换 Provider 等）
  Future<void> updateConfig(covariant dynamic config);
}

enum AgentStatus {
  uninitialized,
  initializing,
  idle,
  processing,
  error,
  disposed,
}
```

### 7.2 输入模式枚举

聊天和翻译均支持三种输入模式，运行时可切换：

```dart
// lib/agents/agent_input_mode.dart

enum AgentInputMode {
  /// 文本模式：键盘输入，手动点击发送
  text,

  /// 短语音模式：按住录音按钮说话，松手后 STT 识别并发送
  /// 类似微信语音消息，适合单条语音指令
  shortVoice,

  /// 通话模式：持续监听，VAD 检测静音后自动发送，TTS 回复后继续监听
  /// 免持、连续对话体验，类似电话通话
  callMode,
}
```

### 7.3 ChatAgent 接口

```dart
// lib/agents/chat/chat_agent.dart

class ChatAgent extends BaseAgent {
  // --- 输入模式 ---

  /// 当前输入模式
  AgentInputMode get inputMode;

  /// 切换输入模式（text / shortVoice / callMode）
  /// 切换到 callMode 时自动开始监听；切换离开时停止监听
  Future<void> setInputMode(AgentInputMode mode);

  // --- 文本模式 ---

  /// 发送文本消息（文本模式使用）
  Stream<LlmResponse> sendMessage(String text);

  // --- 短语音模式 ---

  /// 开始按住录音（shortVoice 模式使用）
  Future<void> startShortVoiceRecording();

  /// 松手停止录音，STT 识别后自动发送给 LLM
  /// 返回 STT 识别的最终文本
  Future<String> stopShortVoiceAndSend();

  /// 取消本次短语音录制（滑动取消）
  Future<void> cancelShortVoice();

  // --- 通话模式 ---

  /// 进入通话模式：启动持续监听循环
  /// 内部循环：VAD 检测 → STT → LLM → TTS → 继续监听
  Future<void> enterCallMode();

  /// 退出通话模式，停止监听和一切处理
  Future<void> exitCallMode();

  /// 通话模式下手动打断 TTS 播放并立即开始新一轮监听
  Future<void> interruptAndListen();

  // --- 通用 ---

  /// 取消当前进行中的请求（不退出通话模式）
  Future<void> cancel();

  /// 清空对话历史
  void clearHistory();

  // --- 状态流 ---

  /// 对话历史列表流
  Stream<List<Message>> get messagesStream;

  /// STT 实时中间识别结果流（短语音/通话模式下可见）
  Stream<SttResult> get sttPartialResultStream;

  /// 当前输入模式流
  Stream<AgentInputMode> get inputModeStream;

  /// 当前详细状态
  Stream<ChatAgentStatus> get detailStatusStream;
}

enum ChatAgentStatus {
  // 通用
  idle,
  error,

  // 短语音模式
  shortVoiceRecording,     // 按住录音中
  shortVoiceProcessing,    // STT 识别中（松手后）

  // 通话模式
  callListening,           // VAD 监听中（等待用户开口）
  callDetectedSpeech,      // 检测到语音，正在录制
  callProcessingStt,       // STT 识别中

  // 共用（短语音/通话/文本）
  callingLlm,              // LLM 请求中
  streamingLlm,            // LLM 流式输出中
  synthesizingTts,         // TTS 合成中
  playingAudio,            // TTS 音频播放中（通话模式播放完后自动继续监听）
}
```

### 7.4 TranslateAgent 接口

```dart
// lib/agents/translate/translate_agent.dart

class TranslateAgent extends BaseAgent {
  // --- 输入模式 ---

  AgentInputMode get inputMode;

  Future<void> setInputMode(AgentInputMode mode);

  // --- 文本模式 ---

  /// 翻译文本（文本模式使用）
  Future<TranslationResult> translate({
    required String text,
    String sourceLang = 'auto',
  });

  // --- 短语音模式 ---

  /// 开始按住录音
  Future<void> startShortVoiceRecording();

  /// 松手：STT 识别 → 翻译 → 可选 TTS 播报
  Future<TranslationResult> stopShortVoiceAndTranslate();

  /// 取消短语音录制
  Future<void> cancelShortVoice();

  // --- 通话模式（同传模式）---

  /// 进入通话模式：持续监听 → VAD → STT → 翻译 → TTS → 继续监听
  Future<void> enterCallMode();

  /// 退出通话模式
  Future<void> exitCallMode();

  // --- 通用 ---

  /// 语言检测
  Future<String> detectLanguage(String text);

  // --- 状态流 ---
  Stream<AgentInputMode> get inputModeStream;
  Stream<TranslationResult> get resultStream;        // 实时翻译结果流
  Stream<SttResult> get sttPartialResultStream;      // STT 中间结果
  Stream<TranslateAgentStatus> get detailStatusStream;
}

enum TranslateAgentStatus {
  idle,
  error,

  // 短语音
  shortVoiceRecording,
  shortVoiceProcessing,

  // 通话模式
  callListening,
  callDetectedSpeech,
  callProcessingStt,

  // 共用
  translating,
  playingResult,        // TTS 播报译文（通话模式播放完后自动继续监听）
}
```

---

## 8. 语言代码规范

项目内统一使用以下语言代码格式：

| 场景 | 格式 | 示例 |
|------|------|------|
| STT 语言参数 | BCP-47 | `zh-CN`, `en-US`, `ja-JP` |
| TTS 语言参数 | BCP-47 | `zh-CN`, `en-US` |
| Translation 语言参数 | ISO 639-1 | `zh`, `en`, `ja` |
| LLM 系统提示中的语言 | 自然语言描述 | 无格式要求 |

各 Provider 实现内部负责格式转换，上层统一传 BCP-47 格式。

---

## 9. 错误处理规范

所有 Provider 方法**必须**将厂商原生异常包装为 `AppException` 后抛出：

```dart
// 示例：Azure STT Provider 错误包装
try {
  // Azure SDK 调用
} on SpeechRecognitionCanceledException catch (e) {
  throw AppException(
    type: AppErrorType.providerError,
    message: 'Azure STT 识别被取消: ${e.reason}',
    providerName: name,
    originalError: e,
  );
} on SocketException {
  throw AppException(
    type: AppErrorType.network,
    message: '网络连接失败，请检查网络',
    providerName: name,
  );
}
```

Agent 层统一捕获 `AppException`，通过状态流通知 UI，UI 层不直接处理 Provider 异常。

---

## 10. Pigeon 原生通道接口（各插件独立生成）

> Pigeon 消息定义放在 `ai_plugin_interface` 包的 `lib/src/pigeon/` 目录下，作为**共享定义**。
> 每个原生插件（如 `stt_azure`）在自己的 `pigeons/` 目录中引用这些消息类型，生成各自的通道代码。
>
> 生成命令：在每个插件包根目录执行 `dart run pigeon --input pigeons/xxx_messages.dart`

### 9.1 STT 通道接口

```dart
// local_plugins/ai_plugin_interface/lib/src/pigeon/stt_messages.dart
// （消息类型定义在共享包，各 STT 插件的 pigeons/ 中引用相同消息类）
// 以 stt_azure 插件为例，其 pigeons/stt_azure_messages.dart 如下：

// local_plugins/stt_azure/pigeons/stt_azure_messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/stt_azure_api.g.dart',
  kotlinOut: 'android/src/main/kotlin/com/yourcompany/stt_azure/SttAzureApi.kt',
  kotlinOptions: KotlinOptions(package: 'com.yourcompany.stt_azure'),
  swiftOut: 'ios/Classes/SttAzureApi.swift',
))

// ---- 消息类型 ----

class SttConfigMessage {
  String providerType = '';     // "azure" | "google" | "aliyun" | "doubao"
  String language = 'zh-CN';   // BCP-47
  int sampleRate = 16000;
  int channels = 1;
  Map<String?, String?> extras = {}; // 厂商特定扩展参数（apiKey、region 等）
}

class SttResultMessage {
  String text = '';
  bool isFinal = false;
  double confidence = 0.0;
  String detectedLanguage = '';
}

class SttErrorMessage {
  String code = '';
  String message = '';
}

// ---- Flutter → Native（指令） ----
@HostApi()
abstract class SttHostApi {
  /// 启动流式识别（传入配置，内部打开麦克风 + 建立服务连接）
  void startStream(SttConfigMessage config);

  /// 停止流式识别并关闭麦克风
  void stopStream();

  /// 一次性识别（离线音频文件或已录制字节）
  void recognize(Uint8List audioData, SttConfigMessage config);

  /// 释放资源
  void dispose();
}

// ---- Native → Flutter（回调） ----
@FlutterApi()
abstract class SttFlutterApi {
  void onResult(SttResultMessage result);
  void onError(SttErrorMessage error);
  void onStreamStopped();   // 识别流正常结束
}
```

### 9.2 TTS 通道接口

```dart
// local_plugins/tts_azure/pigeons/tts_azure_messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/tts_azure_api.g.dart',
  kotlinOut: 'android/src/main/kotlin/com/yourcompany/tts_azure/TtsAzureApi.kt',
  kotlinOptions: KotlinOptions(package: 'com.yourcompany.tts_azure'),
  swiftOut: 'ios/Classes/TtsAzureApi.swift',
))

class TtsRequestMessage {
  String providerType = '';     // "azure" | "google" | "aliyun" | "doubao"
  String text = '';
  String language = 'zh-CN';
  String voice = '';            // 音色 ID（各厂商格式不同）
  double speedRate = 1.0;
  double pitchRate = 1.0;
  int sampleRate = 16000;
  String format = 'mp3';        // "mp3" | "pcm" | "wav"
  Map<String?, String?> extras = {};
}

class TtsVoiceMessage {
  String id = '';
  String displayName = '';
  String language = '';
  String gender = '';
}

@HostApi()
abstract class TtsHostApi {
  /// 合成并直接播放（原生层负责播放）
  void synthesizeAndPlay(TtsRequestMessage request);

  /// 合成并以流形式返回音频字节（Flutter 层自行处理播放）
  void synthesizeStream(TtsRequestMessage request);

  /// 停止当前播放/合成
  void stop();

  /// 获取支持的音色列表
  void getAvailableVoices(String providerType, String language);

  void dispose();
}

@FlutterApi()
abstract class TtsFlutterApi {
  /// synthesizeStream 的音频数据回调（分块返回）
  void onAudioChunk(Uint8List chunk);

  /// 合成/播放完成
  void onDone();

  /// 错误回调
  void onError(String code, String message);

  /// getAvailableVoices 回调
  void onVoiceList(List<TtsVoiceMessage?> voices);
}
```

### 9.3 LLM 通道接口

```dart
// local_plugins/llm_openai/pigeons/llm_openai_messages.dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/llm_openai_api.g.dart',
  kotlinOut: 'android/src/main/kotlin/com/yourcompany/llm_openai/LlmOpenAiApi.kt',
  kotlinOptions: KotlinOptions(package: 'com.yourcompany.llm_openai'),
  swiftOut: 'ios/Classes/LlmOpenAiApi.swift',
))

class LlmMessageMessage {
  String role = '';             // "user" | "assistant" | "system"
  String content = '';
}

class LlmConfigMessage {
  String providerType = '';     // "openai" | "claude" | "gemini" | "qwen" | "doubao" | "deepseek"
  String model = '';            // 留空使用 Provider 默认值
  double temperature = 0.7;
  int maxTokens = 2048;
  Map<String?, String?> extras = {}; // apiKey、baseUrl 等注入
}

class LlmTokenMessage {
  String token = '';            // 单次增量内容
  bool isDone = false;          // true = 流结束
  int promptTokens = 0;         // 仅 isDone=true 时有值
  int completionTokens = 0;
  int totalTokens = 0;
}

@HostApi()
abstract class LlmHostApi {
  /// 发起流式对话（原生层通过 HTTP SSE 请求，逐 token 回调 onToken）
  void chatStream(List<LlmMessageMessage?> messages, LlmConfigMessage config);

  /// 取消当前请求
  void cancel();

  void dispose();
}

@FlutterApi()
abstract class LlmFlutterApi {
  void onToken(LlmTokenMessage token);
  void onError(String code, String message);
}
```

### 9.4 后台服务控制接口

```dart
// local_plugins/ai_plugin_interface/lib/src/pigeon/service_messages.dart
// 后台服务控制通道由主 App 统一使用，非单个插件

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: '../../lib/ai_service_control.g.dart',  // 生成到主 App lib/
  kotlinOut: '../../android/app/src/main/kotlin/com/yourcompany/ai_agent_client/ServiceApi.kt',
  kotlinOptions: KotlinOptions(package: 'com.yourcompany.ai_agent_client'),
  swiftOut: '../../ios/Runner/ServiceApi.swift',
))

enum NativeServiceStatus {
  uninitialized,
  starting,
  running,
  stopping,
  stopped,
  error,
}

class ServiceStatusMessage {
  NativeServiceStatus status = NativeServiceStatus.uninitialized;
  String? errorMessage;
}

@HostApi()
abstract class AiServiceHostApi {
  /// 启动后台服务（Android: 启动 ForegroundService；iOS: 激活 AVAudioSession）
  void startService();

  /// 停止后台服务
  void stopService();

  /// 查询当前服务状态
  NativeServiceStatus getServiceStatus();
}

@FlutterApi()
abstract class AiServiceFlutterApi {
  /// 服务状态变化通知
  void onServiceStatusChanged(ServiceStatusMessage status);
}
```

### 9.5 Pigeon 代码生成命令

每个原生插件在**自己的包根目录**独立生成：

```bash
# STT 插件
cd local_plugins/stt_azure  && dart run pigeon --input pigeons/stt_azure_messages.dart
cd local_plugins/stt_aliyun && dart run pigeon --input pigeons/stt_aliyun_messages.dart
cd local_plugins/stt_google && dart run pigeon --input pigeons/stt_google_messages.dart
cd local_plugins/stt_doubao && dart run pigeon --input pigeons/stt_doubao_messages.dart

# TTS 插件
cd local_plugins/tts_azure  && dart run pigeon --input pigeons/tts_azure_messages.dart
# ... 同理

# LLM 插件
cd local_plugins/llm_openai && dart run pigeon --input pigeons/llm_openai_messages.dart
# ... 同理

# 后台服务控制（主 App 级，在项目根目录执行）
dart run pigeon --input local_plugins/ai_plugin_interface/lib/src/pigeon/service_messages.dart
```

或使用根目录的 `Makefile` / `scripts/gen_pigeon.sh` 批量生成所有插件：

```bash
# scripts/gen_pigeon.sh
#!/bin/bash
for plugin in stt_azure stt_aliyun stt_google stt_doubao \
              tts_azure tts_aliyun tts_google tts_doubao \
              llm_openai llm_claude llm_qwen llm_doubao llm_deepseek; do
  echo "Generating pigeon for $plugin..."
  (cd local_plugins/$plugin && dart run pigeon --input pigeons/${plugin}_messages.dart)
done
echo "All done."
```

---

## 11. 后台服务配置要求

### 10.1 Android 权限（AndroidManifest.xml）

```xml
<!-- 前台服务权限 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />

<!-- 音频权限 -->
<uses-permission android:name="android.permission.RECORD_AUDIO" />

<!-- 网络 -->
<uses-permission android:name="android.permission.INTERNET" />

<!-- 开机自启（可选）-->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- 声明 Service -->
<service
    android:name=".service.AISupervisoryService"
    android:foregroundServiceType="microphone|mediaPlayback"
    android:exported="false" />

<!-- 开机广播接收器（可选）-->
<receiver android:name=".BootReceiver" android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED"/>
    </intent-filter>
</receiver>
```

### 10.2 iOS 能力配置（Info.plist）

```xml
<!-- 后台模式 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>              <!-- STT/TTS 后台音频 -->
    <string>fetch</string>              <!-- LLM 后台刷新 -->
    <string>processing</string>         <!-- BGTaskScheduler 后台处理 -->
    <string>voip</string>               <!-- VoIP 后台保持（需 Apple 审核）-->
</array>

<!-- 权限描述 -->
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限用于语音识别和对话</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>需要语音识别权限将语音转为文字</string>
```
