# 开发指南 (Developer Guide)

**项目名称**：AI Agent Client
**版本**：v1.1
**日期**：2026-03-11
**变更**：新增原生插件开发流程、后台服务配置、Pigeon 代码生成

---

## 1. 环境搭建

### 1.1 前置要求

| 工具 | 最低版本 | 说明 |
|------|---------|------|
| Flutter SDK | 3.22+ | `flutter --version` |
| Dart SDK | 3.4+ | 随 Flutter 附带 |
| Xcode | 15+ | iOS 开发（macOS） |
| Android Studio | Hedgehog+ | Android 开发 |
| CocoaPods | 1.14+ | iOS 依赖管理 |

### 1.2 初始化项目

```bash
# 1. 创建 Flutter 项目（主 App）
flutter create --org com.yourcompany ai_agent_client
cd ai_agent_client

# 2. 创建共享接口包（纯 Dart，无原生层）
flutter create --template=package local_plugins/ai_plugin_interface

# 3. 批量创建各厂商原生插件包（STT）
for name in stt_azure stt_aliyun stt_google stt_doubao; do
  flutter create --template=plugin --platforms=android,ios \
    --org com.yourcompany -a kotlin -i swift \
    local_plugins/$name
done

# 4. 批量创建各厂商原生插件包（TTS）
for name in tts_azure tts_aliyun tts_google tts_doubao; do
  flutter create --template=plugin --platforms=android,ios \
    --org com.yourcompany -a kotlin -i swift \
    local_plugins/$name
done

# 5. 批量创建各厂商原生插件包（LLM，含后台 HTTP）
for name in llm_openai llm_claude llm_qwen llm_doubao llm_deepseek; do
  flutter create --template=plugin --platforms=android,ios \
    --org com.yourcompany -a kotlin -i swift \
    local_plugins/$name
done

# 6. 批量创建翻译插件包（纯 Dart）
for name in translation_deepl translation_google translation_aliyun; do
  flutter create --template=package local_plugins/$name
done

# 7. 安装所有依赖
flutter pub get
for dir in local_plugins/*/; do
  (cd "$dir" && flutter pub get)
done

# 8. 批量生成 Pigeon 通道代码
bash scripts/gen_pigeon.sh

# 9. 配置环境变量（见 1.3）

# 10. iOS 依赖安装
cd ios && pod install && cd ..

# 11. 运行
flutter run
```

### 1.3 环境变量配置

在项目根目录创建 `.env` 文件（参考 `.env.example`）：

```bash
cp .env.example .env
# 编辑 .env，填入真实的 API Key
```

**.env.example 完整内容：**

```dotenv
# ============================================
# AI Agent Client - 环境配置示例
# 复制此文件为 .env，填入真实配置
# ============================================

# ---- LLM 配置 ----

# OpenAI
OPENAI_API_KEY=sk-...
OPENAI_BASE_URL=https://api.openai.com/v1    # 可替换为代理地址

# Anthropic Claude
CLAUDE_API_KEY=sk-ant-...

# Google Gemini
GEMINI_API_KEY=AI...

# 阿里云通义千问
QWEN_API_KEY=sk-...

# 火山引擎豆包 LLM
DOUBAO_LLM_API_KEY=...
DOUBAO_LLM_ENDPOINT_ID=...

# DeepSeek
DEEPSEEK_API_KEY=sk-...

# ---- STT 配置 ----

# 微软 Azure Speech
AZURE_SPEECH_KEY=...
AZURE_SPEECH_REGION=eastasia              # 如 eastus, eastasia

# Google Cloud Speech-to-Text
GOOGLE_SPEECH_API_KEY=...

# 阿里云智能语音
ALIYUN_STT_APP_KEY=...
ALIYUN_STT_TOKEN=...                      # 阿里云 Token（需定期刷新）

# 火山引擎豆包语音识别
DOUBAO_STT_APP_ID=...
DOUBAO_STT_TOKEN=...

# ---- TTS 配置 ----

# 微软 Azure TTS（与 STT 共用 Key/Region）
# AZURE_SPEECH_KEY 和 AZURE_SPEECH_REGION 已在上方定义

# Google Cloud TTS
GOOGLE_TTS_API_KEY=...

# 阿里云 TTS（可与 STT 共用 Token）
ALIYUN_TTS_APP_KEY=...

# 火山引擎豆包 TTS
DOUBAO_TTS_APP_ID=...
DOUBAO_TTS_TOKEN=...

# ---- 翻译配置 ----

# DeepL
DEEPL_API_KEY=...                         # 免费版 Key 以 :fx 结尾

# Google Cloud Translation
GOOGLE_TRANSLATE_API_KEY=...

# 阿里云机器翻译
ALIYUN_TRANSLATE_ACCESS_KEY=...
ALIYUN_TRANSLATE_SECRET_KEY=...

# 有道翻译
YOUDAO_API_KEY=...
YOUDAO_API_SECRET=...

# ---- 默认 Provider 选择 ----
DEFAULT_LLM_PROVIDER=openai               # openai | claude | gemini | qwen | doubao | deepseek
DEFAULT_STT_PROVIDER=azure                # azure | google | aliyun | doubao
DEFAULT_TTS_PROVIDER=azure                # azure | google | aliyun | doubao
DEFAULT_TRANSLATION_PROVIDER=deepl        # deepl | google | aliyun | youdao
```

**重要**：将 `.env` 加入 `.gitignore`：

```gitignore
# .gitignore
.env
*.env
!.env.example
```

---

## 2. 依赖包清单

### 2.1 主 App（pubspec.yaml）

```yaml
name: ai_agent_client
description: AI能力测试平台 - 各方服务演示 App

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'

dependencies:
  flutter:
    sdk: flutter

  # ---- 共享接口包 ----
  ai_plugin_interface:
    path: local_plugins/ai_plugin_interface

  # ---- STT 插件 ----
  stt_azure:   { path: local_plugins/stt_azure }
  stt_aliyun:  { path: local_plugins/stt_aliyun }
  stt_google:  { path: local_plugins/stt_google }
  stt_doubao:  { path: local_plugins/stt_doubao }

  # ---- TTS 插件 ----
  tts_azure:   { path: local_plugins/tts_azure }
  tts_aliyun:  { path: local_plugins/tts_aliyun }
  tts_google:  { path: local_plugins/tts_google }
  tts_doubao:  { path: local_plugins/tts_doubao }

  # ---- LLM 插件 ----
  llm_openai:   { path: local_plugins/llm_openai }
  llm_claude:   { path: local_plugins/llm_claude }
  llm_qwen:     { path: local_plugins/llm_qwen }
  llm_doubao:   { path: local_plugins/llm_doubao }
  llm_deepseek: { path: local_plugins/llm_deepseek }

  # ---- 翻译插件（纯 Dart）----
  translation_deepl:   { path: local_plugins/translation_deepl }
  translation_google:  { path: local_plugins/translation_google }
  translation_aliyun:  { path: local_plugins/translation_aliyun }

  # ---- 状态管理 ----
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # ---- 环境配置 ----
  flutter_dotenv: ^5.1.0

  # ---- HTTP（翻译插件内部使用，主 App 传递）----
  dio: ^5.4.3+1

  # ---- 路由 ----
  go_router: ^13.2.0

  # ---- JSON 序列化 ----
  json_annotation: ^4.9.0
  freezed_annotation: ^2.4.1

  # ---- 工具库 ----
  logger: ^2.3.0
  uuid: ^4.4.0
  collection: ^1.18.0

  # ---- UI 组件 ----
  flutter_markdown: ^0.6.22

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.9
  json_serializable: ^6.8.0
  freezed: ^2.5.2
  riverpod_generator: ^2.4.0
  custom_lint: ^0.6.4
  riverpod_lint: ^2.3.10
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
  assets:
    - .env
    - assets/
```

### 2.2 共享接口包（local_plugins/ai_plugin_interface/pubspec.yaml）

```yaml
name: ai_plugin_interface
description: Shared abstract interfaces and Pigeon message definitions for AI plugins

environment:
  sdk: '>=3.4.0 <4.0.0'

dependencies:
  plugin_platform_interface: ^2.1.8

dev_dependencies:
  pigeon: ^21.0.0
  flutter_lints: ^3.0.0
```

### 2.3 原生 STT/TTS 插件（以 stt_azure 为例，pubspec.yaml）

```yaml
name: stt_azure
description: Azure Speech-to-Text Flutter plugin

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'

dependencies:
  flutter:
    sdk: flutter
  ai_plugin_interface:
    path: ../ai_plugin_interface
  plugin_platform_interface: ^2.1.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  pigeon: ^21.0.0
  flutter_lints: ^3.0.0

flutter:
  plugin:
    platforms:
      android:
        package: com.yourcompany.stt_azure
        pluginClass: SttAzurePlugin
      ios:
        pluginClass: SttAzurePlugin
```

### 2.4 各插件 Android 原生依赖

| 插件 | android/build.gradle 添加内容 |
|------|-------------------------------|
| stt_azure / tts_azure | `implementation 'com.microsoft.cognitiveservices.speech:client-sdk:1.37.0'` |
| stt_aliyun / tts_aliyun | `implementation 'com.alibaba.nls:nls-sdk-long-asr:2.2.2'` 等 |
| llm_openai / llm_claude 等 | `implementation 'com.squareup.okhttp3:okhttp:4.12.0'`<br>`implementation 'com.squareup.okhttp3:okhttp-sse:4.12.0'` |

### 2.5 各插件 iOS 原生依赖（podspec）

| 插件 | podspec 添加内容 |
|------|----------------|
| stt_azure / tts_azure | `s.dependency 'MicrosoftCognitiveServicesSpeech-iOS', '~> 1.37'` |
| stt_aliyun / tts_aliyun | `s.dependency 'AlibabaCloud-NLS'` |
| llm_xxx | 无额外依赖（URLSession 原生自带）|

---

## 3. 编码规范

### 3.1 文件命名
- 所有 Dart 文件使用 `snake_case`：`chat_agent.dart`
- 类名使用 `PascalCase`：`ChatAgent`
- 私有变量/方法以 `_` 开头：`_sttProvider`

### 3.2 Provider 实现规范

实现新 Provider 时必须遵循：

```dart
// ✅ 正确：所有异常包装为 AppException
Future<SttResult> recognize({...}) async {
  try {
    // 调用厂商 SDK
  } on SpecificVendorException catch (e) {
    throw AppException(
      type: AppErrorType.providerError,
      message: '识别失败: ${e.message}',
      providerName: name,
      originalError: e,
    );
  }
}

// ✅ 正确：实现 dispose 方法
@override
Future<void> dispose() async {
  await _client?.close();
  _streamController?.close();
}

// ❌ 错误：直接抛出原始异常
Future<SttResult> recognize({...}) async {
  // 不包装直接 throw
  throw SomeVendorException('...');
}
```

### 3.3 流式数据规范

```dart
// ✅ 正确：流关闭前确保 done 信号
Stream<LlmResponse> chatStream({...}) async* {
  try {
    await for (final chunk in _fetchStream()) {
      yield LlmResponse(content: chunk, isDone: false);
    }
    yield LlmResponse(content: '', isDone: true);  // 必须发送结束信号
  } catch (e) {
    // 包装错误
    throw AppException(...);
  }
}
```

### 3.4 API Key 安全规范

```dart
// ✅ 正确：从 AppConfig 读取，不硬编码
final apiKey = config.openaiApiKey;

// ❌ 错误：硬编码 Key
final apiKey = 'sk-1234567890abcdef';

// ❌ 错误：打印 Key 到日志
logger.d('Using API key: $apiKey');

// ✅ 正确：打印时遮蔽
logger.d('Using API key: ${apiKey.substring(0, 6)}...');
```

---

## 4. 如何新增 STT/TTS Provider

新增一个厂商的 STT/TTS 意味着**新建一个独立的 Flutter Plugin 包**，放入 `local_plugins/`。
主 App 只需在 `pubspec.yaml` 中添加路径引用，并在 `SttRegistry` 中注册即可。

以新增 **讯飞 STT** 为例：

### 第一步：新建 Flutter Plugin 包

```bash
cd /path/to/ai_agent_client

flutter create --template=plugin --platforms=android,ios \
  --org com.yourcompany -a kotlin -i swift \
  local_plugins/stt_xunfei
```

### 第二步：配置 pubspec.yaml（local_plugins/stt_xunfei/pubspec.yaml）

```yaml
name: stt_xunfei
description: iFlytek Speech-to-Text Flutter plugin

dependencies:
  flutter:
    sdk: flutter
  ai_plugin_interface:
    path: ../ai_plugin_interface   # 引用共享接口包
  plugin_platform_interface: ^2.1.8

dev_dependencies:
  pigeon: ^21.0.0
```

### 第三步：编写 Pigeon 消息定义，生成通道代码

```bash
# 复制 stt_azure 的 pigeons/stt_azure_messages.dart 为模板
cp local_plugins/stt_azure/pigeons/stt_azure_messages.dart \
   local_plugins/stt_xunfei/pigeons/stt_xunfei_messages.dart
# 修改包名和类名后生成
cd local_plugins/stt_xunfei
dart run pigeon --input pigeons/stt_xunfei_messages.dart
```

### 第四步：实现 Dart Plugin 类

```dart
// local_plugins/stt_xunfei/lib/src/stt_xunfei_plugin.dart

class SttXunfeiPlugin implements SttProvider {
  final String appId;
  final String apiKey;
  final String apiSecret;

  SttXunfeiPlugin({
    required this.appId,
    required this.apiKey,
    required this.apiSecret,
  });

  final _hostApi = SttXunfeiHostApi();
  final _resultController = StreamController<SttResult>.broadcast();

  // 注册 Pigeon FlutterApi 回调，适配到 SttProvider 接口
  // ... 参考 stt_azure_plugin.dart 实现
}
```

### 第五步：实现 Android 原生（Kotlin）

```kotlin
// local_plugins/stt_xunfei/android/.../SttXunfeiPlugin.kt

class SttXunfeiPlugin : FlutterPlugin, SttXunfeiHostApi {
    // 实现讯飞 SDK 调用，结果通过 SttXunfeiFlutterApi 回调
}
```

添加 Android 依赖（`android/build.gradle`）：
```groovy
implementation 'com.iflytek.cloud:speech-sdk:+'
```

### 第六步：实现 iOS 原生（Swift）

```swift
// local_plugins/stt_xunfei/ios/Classes/SttXunfeiPlugin.swift

public class SttXunfeiPlugin: NSObject, FlutterPlugin, SttXunfeiHostApi {
    // 实现讯飞 iOS SDK 调用
}
```

添加 iOS 依赖（`stt_xunfei.podspec`）：
```ruby
s.dependency 'iflyMSC'
```

### 第七步：在主 App 引用并注册

在主 App `pubspec.yaml` 的 dependencies 中添加：
```yaml
stt_xunfei: { path: local_plugins/stt_xunfei }
```

在枚举中添加新值：
```dart
// lib/core/config/env_keys.dart
static const xunfeiSttAppId    = 'XUNFEI_STT_APP_ID';
static const xunfeiSttApiKey   = 'XUNFEI_STT_API_KEY';
static const xunfeiSttApiSecret= 'XUNFEI_STT_API_SECRET';
```

在 Registry 中注册：
```dart
// lib/registry/stt_registry.dart
SttProviderType.xunfei: (c) => SttXunfeiPlugin(
  appId:     c.xunfeiSttAppId,
  apiKey:    c.xunfeiSttApiKey,
  apiSecret: c.xunfeiSttApiSecret,
),
```

### 第八步：更新 `.env.example`

```dotenv
XUNFEI_STT_APP_ID=...
XUNFEI_STT_API_KEY=...
XUNFEI_STT_API_SECRET=...
```

**完成！** TTS/LLM 新增步骤与此完全一致，翻译插件无原生层更简单。
详细原生实现规范见 [native-plugin.md](./native-plugin.md)。

---

## 5. 如何新增 Agent

以新增 **SummarizeAgent（文本摘要）** 为例：

### 第一步：创建 Agent 配置类

```dart
// lib/agents/summarize/summarize_agent_config.dart

class SummarizeAgentConfig {
  final LlmProviderType llmProvider;
  final String systemPrompt;
  final int maxSummaryLength;

  const SummarizeAgentConfig({
    this.llmProvider = LlmProviderType.openai,
    this.systemPrompt = '请对以下文本生成简洁的摘要：',
    this.maxSummaryLength = 500,
  });
}
```

### 第二步：实现 Agent

```dart
// lib/agents/summarize/summarize_agent.dart

class SummarizeAgent extends BaseAgent {
  SummarizeAgentConfig _config;
  LlmProvider? _llmProvider;

  SummarizeAgent(this._config);

  @override
  String get name => 'SummarizeAgent';

  @override
  Future<void> initialize() async {
    _updateStatus(AgentStatus.initializing);
    _llmProvider = LlmFactory.create(_config.llmProvider, appConfig);
    _updateStatus(AgentStatus.idle);
  }

  /// 对文本生成摘要
  Future<String> summarize(String text) async {
    _updateStatus(AgentStatus.processing);
    try {
      final messages = [
        Message(role: MessageRole.system, content: _config.systemPrompt),
        Message(role: MessageRole.user, content: text),
      ];
      final response = await _llmProvider!.chat(messages: messages);
      _updateStatus(AgentStatus.idle);
      return response.content;
    } on AppException {
      _updateStatus(AgentStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    await _llmProvider?.dispose();
    _updateStatus(AgentStatus.disposed);
  }

  @override
  Future<void> updateConfig(SummarizeAgentConfig config) async {
    _config = config;
    await dispose();
    await initialize();
  }
}
```

### 第三步：注册到 AgentRegistry

```dart
// lib/agents/registry/agent_registry.dart

class AgentRegistry {
  static final Map<String, BaseAgent> _agents = {};

  static void register(String key, BaseAgent agent) {
    _agents[key] = agent;
  }

  static T get<T extends BaseAgent>(String key) {
    return _agents[key] as T;
  }

  // 在 app 启动时调用
  static Future<void> initAll(AppConfig config) async {
    register('chat', ChatAgent(ChatAgentConfig.fromAppConfig(config)));
    register('translate', TranslateAgent(TranslateAgentConfig.fromAppConfig(config)));
    register('summarize', SummarizeAgent(SummarizeAgentConfig()));  // 新增
    for (final agent in _agents.values) {
      await agent.initialize();
    }
  }
}
```

### 第四步：创建 UI 模块

在 `lib/features/summarize/` 下创建对应的 Screen 和 State，通过 Riverpod Provider 调用 `AgentRegistry.get<SummarizeAgent>('summarize')`。

---

## 6. 常见开发任务

### 生成 Pigeon 通道代码

```bash
# 在 packages/ai_services_plugin/ 目录执行
dart run pigeon --input lib/pigeons/stt_messages.dart
dart run pigeon --input lib/pigeons/tts_messages.dart
dart run pigeon --input lib/pigeons/llm_messages.dart
dart run pigeon --input lib/pigeons/service_messages.dart
```

> 注意：每次修改 `lib/pigeons/*.dart` 后必须重新运行，不要手动修改 `lib/src/pigeon/*.g.dart`。

### 运行代码生成（Freezed + Riverpod）

```bash
dart run build_runner build --delete-conflicting-outputs
# 或监听模式（开发时）
dart run build_runner watch --delete-conflicting-outputs
```

### 检查代码质量

```bash
flutter analyze
dart format lib/
```

### 运行测试

```bash
flutter test
# 特定测试
flutter test test/providers/azure_stt_test.dart
```

### 添加新的图片/字体资源

1. 将文件放入 `assets/` 目录
2. 在 `pubspec.yaml` 的 `flutter.assets` 中注册
3. 运行 `flutter pub get`

---

## 7. 平台权限与后台服务配置

### iOS（ios/Runner/Info.plist）

```xml
<!-- 麦克风和语音识别权限 -->
<key>NSMicrophoneUsageDescription</key>
<string>需要麦克风权限用于语音识别和对话</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>需要语音识别权限用于将语音转换为文字</string>

<!-- 后台运行模式 -->
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>fetch</string>
    <string>processing</string>
    <string>voip</string>
</array>
```

在 Xcode 的 **Signing & Capabilities** 中还需要手动添加：
- Background Modes（勾选 Audio + Background fetch + Background processing + Voice over IP）
- Push Notifications（配合 VoIP 使用）

### Android（android/app/src/main/AndroidManifest.xml）

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<application ...>
    <!-- 后台服务声明（在插件包的 AndroidManifest 中声明，主 App 自动合并）-->
</application>
```

> 后台服务的 `<service>` 声明在插件包 `packages/ai_services_plugin/android/src/main/AndroidManifest.xml` 中定义，构建时自动 merge 到主 App。

### Android 电池优化白名单（运行时请求）

```kotlin
// 引导用户将 App 加入电池优化白名单，确保后台服务不被系统杀死
val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
    data = Uri.parse("package:$packageName")
}
startActivity(intent)
```

---

## 8. 项目约定

| 约定 | 规则 |
|------|------|
| 导入顺序 | dart: → package: → 相对路径，各组之间空行 |
| 常量命名 | `lowerCamelCase`（局部）或 `UPPER_SNAKE_CASE`（全局 env key）|
| 异步方法 | 返回 `Future<T>`，流式返回 `Stream<T>` |
| 注释语言 | 中文（业务逻辑），英文（代码注释可选）|
| Provider 文件位置 | `lib/providers/{type}/{vendor}/{vendor}_{type}_provider.dart` |
| Agent 文件位置 | `lib/agents/{name}/{name}_agent.dart` |
| 测试文件位置 | `test/` 下与 `lib/` 目录结构镜像 |

---

## 9. 调试技巧

### 查看 Provider 请求日志

在 `AppConfig` 中启用 debug 模式，所有 Provider 会打印请求/响应摘要（不含 API Key）：

```dotenv
DEBUG_MODE=true
LOG_LEVEL=debug   # debug | info | warning | error
```

### 模拟 Provider（Mock）

开发 UI 时可使用 Mock Provider 避免消耗 API 配额：

```dart
// 在 SttFactory 中添加 mock 类型
SttProviderType.mock => MockSttProvider(),
```

### 网络请求抓包

在 Dio 配置中启用日志拦截器，或使用 Charles/Proxyman 配置代理进行抓包调试。
