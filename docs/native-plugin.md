# 原生插件开发指南

**项目名称**：AI Agent Client
**版本**：v1.2
**日期**：2026-03-11
**变更**：插件改为 local_plugins/ 独立包结构，新增 ai_plugin_interface 共享接口包说明

---

## 1. 插件体系总览

### 1.1 结构关系

```
ai_plugin_interface/          ← 共享 Dart 包（抽象接口 + Pigeon 消息定义）
         ▲
         │ 依赖（path）
┌────────┴──────────────────────────────────────────┐
│  各厂商插件包（local_plugins/）                      │
│                                                   │
│  STT: stt_azure / stt_aliyun / stt_google / stt_doubao  │
│  TTS: tts_azure / tts_aliyun / tts_google / tts_doubao  │
│  LLM: llm_openai / llm_claude / llm_qwen / ...         │
│  Trans: translation_deepl / translation_google / ...    │
└────────┬──────────────────────────────────────────┘
         │ 依赖（path）
    主 App (ai_agent_client)
         │ pubspec.yaml 引用所有插件
         │ registry/ 根据配置选取激活插件
```

### 1.2 各类插件特点

| 类型 | 原生层 | 通信方式 | 是否需要 Pigeon |
|------|--------|---------|----------------|
| STT 插件 | Kotlin + Swift | Platform Channel | 是 |
| TTS 插件 | Kotlin + Swift | Platform Channel | 是 |
| LLM 插件 | Kotlin + Swift（HTTP SSE）| Platform Channel | 是 |
| Translation 插件 | 无（纯 Dart HTTP）| 直接 Dart 调用 | 否 |

---

## 2. ai_plugin_interface（共享接口包）

### 2.1 包结构

```
local_plugins/ai_plugin_interface/
├── pubspec.yaml
└── lib/
    ├── ai_plugin_interface.dart        # 统一导出
    └── src/
        ├── interfaces/
        │   ├── stt_provider.dart       # SttProvider 抽象类（同 api-spec.md 第 2 节）
        │   ├── tts_provider.dart
        │   ├── llm_provider.dart
        │   └── translation_provider.dart
        ├── models/
        │   ├── stt_config.dart
        │   ├── stt_result.dart
        │   ├── tts_request.dart
        │   ├── tts_voice.dart
        │   ├── llm_message.dart
        │   ├── llm_config.dart
        │   ├── llm_response.dart
        │   └── translation_result.dart
        ├── pigeon/                     # 共享消息类型定义（各插件 Pigeon 文件引用相同结构）
        │   ├── stt_messages.dart       # SttConfigMessage / SttResultMessage 等
        │   ├── tts_messages.dart
        │   └── llm_messages.dart
        └── errors/
            └── plugin_exception.dart   # PluginException 统一异常
```

### 2.2 Pigeon 消息类型共享方式

各插件的 `pigeons/xxx_messages.dart` 中**复用相同的消息结构**（字段一致），只修改：
- `@ConfigurePigeon` 中的输出路径（指向各自的 android/ios 目录）
- HostApi / FlutterApi 类名（加插件前缀，如 `SttAzureHostApi`）

这样确保主 App 中的 `SttResult`、`TtsRequest` 等数据模型语义统一。

---

## 3. 单个原生插件包完整结构

以 **stt_azure** 为例：

```
local_plugins/stt_azure/
├── pubspec.yaml
│
├── pigeons/
│   └── stt_azure_messages.dart        # Pigeon 源定义（手写，用于生成通道代码）
│
├── lib/
│   ├── stt_azure.dart                 # 公开导出：export 'src/stt_azure_plugin.dart'
│   └── src/
│       ├── stt_azure_plugin.dart      # 实现 SttProvider 接口，桥接 Pigeon ↔ ai_plugin_interface
│       └── pigeon/
│           └── stt_azure_api.g.dart   # Pigeon 生成（勿手改）
│
├── android/
│   ├── build.gradle                   # 引入 Azure Speech SDK
│   └── src/main/kotlin/com/yourcompany/stt_azure/
│       ├── SttAzurePlugin.kt          # FlutterPlugin 注册 + SttAzureHostApi 实现
│       └── AzureSttEngine.kt          # Azure SDK 封装（纯 Kotlin，无 Flutter 依赖）
│
└── ios/
    ├── stt_azure.podspec
    └── Classes/
        ├── SttAzurePlugin.swift       # FlutterPlugin 注册 + SttAzureHostApi 实现
        └── AzureSttEngine.swift       # Azure SDK 封装（纯 Swift，无 Flutter 依赖）
```

### 3.1 Pigeon 源定义（pigeons/stt_azure_messages.dart）

```dart
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/pigeon/stt_azure_api.g.dart',
  kotlinOut: 'android/src/main/kotlin/com/yourcompany/stt_azure/SttAzureApi.kt',
  kotlinOptions: KotlinOptions(package: 'com.yourcompany.stt_azure'),
  swiftOut: 'ios/Classes/SttAzureApi.swift',
))

// 消息类型（与 ai_plugin_interface 中的定义结构一致）
class SttAzureConfigMessage {
  String language = 'zh-CN';
  int sampleRate = 16000;
  String subscriptionKey = '';
  String region = 'eastasia';
}

class SttAzureResultMessage {
  String text = '';
  bool isFinal = false;
  double confidence = 0.0;
}

// Flutter → Native（控制指令）
@HostApi()
abstract class SttAzureHostApi {
  void startStream(SttAzureConfigMessage config);
  void stopStream();
  void dispose();
}

// Native → Flutter（数据回调）
@FlutterApi()
abstract class SttAzureFlutterApi {
  void onResult(SttAzureResultMessage result);
  void onError(String code, String message);
  void onStreamStopped();
}
```

### 3.2 Dart Plugin 实现（lib/src/stt_azure_plugin.dart）

```dart
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

class SttAzurePlugin implements SttProvider {
  final String subscriptionKey;
  final String region;

  SttAzurePlugin({required this.subscriptionKey, required this.region});

  final _hostApi = SttAzureHostApi();
  final _resultController = StreamController<SttResult>.broadcast();
  bool _isStreaming = false;

  SttAzurePlugin._init({required this.subscriptionKey, required this.region}) {
    // 注册 Native → Flutter 回调
    SttAzureFlutterApi.setUp(_SttAzureCallback(
      onResult: (msg) {
        _resultController.add(SttResult(
          text: msg.text,
          type: msg.isFinal ? SttResultType.final_ : SttResultType.partial,
          confidence: msg.confidence,
        ));
      },
      onError: (code, message) {
        _resultController.addError(PluginException(
          code: code, message: message, pluginName: 'stt_azure',
        ));
      },
      onStopped: () => _isStreaming = false,
    ));
  }

  factory SttAzurePlugin({required String subscriptionKey, required String region}) {
    return SttAzurePlugin._init(subscriptionKey: subscriptionKey, region: region);
  }

  @override
  String get name => 'Azure STT';

  @override
  bool get supportsStreaming => true;

  @override
  Stream<SttResult> startStream({
    required String language,
    int sampleRate = 16000,
    int channels = 1,
  }) {
    _isStreaming = true;
    _hostApi.startStream(SttAzureConfigMessage(
      language: language,
      sampleRate: sampleRate,
      subscriptionKey: subscriptionKey,
      region: region,
    ));
    return _resultController.stream;
  }

  @override
  Future<void> stopStream() async {
    await _hostApi.stopStream();
  }

  @override
  Future<SttResult> recognize({
    required Uint8List audioData,
    required String language,
    int sampleRate = 16000,
  }) async {
    // 一次性识别（通过 Completer 等待 FlutterApi 回调）
    throw UnimplementedError('TODO');
  }

  @override
  Future<void> dispose() async {
    await _hostApi.dispose();
    await _resultController.close();
  }
}
```

### 3.3 Android 原生实现（SttAzurePlugin.kt）

```kotlin
package com.yourcompany.stt_azure

import com.microsoft.cognitiveservices.speech.*
import io.flutter.embedding.engine.plugins.FlutterPlugin

class SttAzurePlugin : FlutterPlugin, SttAzureHostApi {

    private lateinit var flutterApi: SttAzureFlutterApi
    private var engine: AzureSttEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SttAzureHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = SttAzureFlutterApi(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        SttAzureHostApi.setUp(binding.binaryMessenger, null)
        engine?.dispose()
    }

    // ---- SttAzureHostApi 实现 ----

    override fun startStream(config: SttAzureConfigMessage) {
        engine = AzureSttEngine(
            subscriptionKey = config.subscriptionKey,
            region          = config.region,
            language        = config.language,
            sampleRate      = config.sampleRate.toInt(),
            onResult        = { text, isFinal ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    flutterApi.onResult(
                        SttAzureResultMessage(text = text, isFinal = isFinal, confidence = 0.0)
                    ) {}
                }
            },
            onError = { code, msg ->
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    flutterApi.onError(code, msg) {}
                }
            },
            onStopped = {
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    flutterApi.onStreamStopped {}
                }
            }
        )
        engine?.start()
    }

    override fun stopStream() {
        engine?.stop()
    }

    override fun dispose() {
        engine?.dispose()
        engine = null
    }
}
```

```kotlin
// AzureSttEngine.kt —— 纯 Azure SDK 封装，无 Flutter 依赖

class AzureSttEngine(
    private val subscriptionKey: String,
    private val region: String,
    private val language: String,
    private val sampleRate: Int,
    private val onResult: (String, Boolean) -> Unit,
    private val onError: (String, String) -> Unit,
    private val onStopped: () -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null
    private var audioStream: PushAudioInputStream? = null
    private var audioRecord: android.media.AudioRecord? = null

    fun start() {
        val speechConfig = SpeechConfig.fromSubscription(subscriptionKey, region).apply {
            speechRecognitionLanguage = language
        }
        audioStream = AudioInputStream.createPushStream()
        val audioConfig = AudioConfig.fromStreamInput(audioStream)

        recognizer = SpeechRecognizer(speechConfig, audioConfig).apply {
            recognizing.addEventListener { _, e -> onResult(e.result.text, false) }
            recognized.addEventListener { _, e ->
                if (e.result.reason == ResultReason.RecognizedSpeech)
                    onResult(e.result.text, true)
            }
            canceled.addEventListener { _, e ->
                if (e.reason == CancellationReason.Error)
                    onError("AZURE_CANCELED", e.errorDetails)
            }
            startContinuousRecognitionAsync()
        }
        startMicCapture()
    }

    private fun startMicCapture() {
        val bufferSize = android.media.AudioRecord.getMinBufferSize(
            sampleRate,
            android.media.AudioFormat.CHANNEL_IN_MONO,
            android.media.AudioFormat.ENCODING_PCM_16BIT
        )
        audioRecord = android.media.AudioRecord(
            android.media.MediaRecorder.AudioSource.MIC,
            sampleRate,
            android.media.AudioFormat.CHANNEL_IN_MONO,
            android.media.AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        audioRecord?.startRecording()

        Thread {
            val buffer = ByteArray(bufferSize)
            while (audioRecord?.recordingState == android.media.AudioRecord.RECORDSTATE_RECORDING) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                if (read > 0) audioStream?.write(buffer, read)
            }
        }.start()
    }

    fun stop() {
        recognizer?.stopContinuousRecognitionAsync()
        audioRecord?.stop()
        audioStream?.close()
        onStopped()
    }

    fun dispose() {
        stop()
        recognizer?.close()
        audioRecord?.release()
    }
}
```

### 3.4 iOS 原生实现（SttAzurePlugin.swift）

```swift
import Flutter
import MicrosoftCognitiveServicesSpeech

public class SttAzurePlugin: NSObject, FlutterPlugin, SttAzureHostApi {

    private var flutterApi: SttAzureFlutterApi?
    private var engine: AzureSttEngine?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SttAzurePlugin()
        SttAzureHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
        instance.flutterApi = SttAzureFlutterApi(binaryMessenger: registrar.messenger())
    }

    public func startStream(config: SttAzureConfigMessage) throws {
        engine = AzureSttEngine(
            subscriptionKey: config.subscriptionKey,
            region: config.region,
            language: config.language,
            sampleRate: Int(config.sampleRate),
            onResult: { [weak self] text, isFinal in
                DispatchQueue.main.async {
                    self?.flutterApi?.onResult(
                        SttAzureResultMessage(text: text, isFinal: isFinal, confidence: 0),
                        completion: { _ in }
                    )
                }
            },
            onError: { [weak self] code, msg in
                DispatchQueue.main.async {
                    self?.flutterApi?.onError(code: code, message: msg) { _ in }
                }
            },
            onStopped: { [weak self] in
                DispatchQueue.main.async {
                    self?.flutterApi?.onStreamStopped { _ in }
                }
            }
        )
        try engine?.start()
    }

    public func stopStream() throws {
        engine?.stop()
    }

    public func dispose() throws {
        engine?.dispose()
        engine = nil
    }
}
```

```swift
// AzureSttEngine.swift —— 纯 Azure SDK 封装

import MicrosoftCognitiveServicesSpeech
import AVFoundation

class AzureSttEngine {
    private var reco: SPXSpeechRecognizer?
    private var audioStream: SPXPushAudioInputStream?
    private var audioEngine: AVAudioEngine?

    private let onResult: (String, Bool) -> Void
    private let onError: (String, String) -> Void
    private let onStopped: () -> Void

    init(subscriptionKey: String, region: String, language: String, sampleRate: Int,
         onResult: @escaping (String, Bool) -> Void,
         onError: @escaping (String, String) -> Void,
         onStopped: @escaping () -> Void) {
        self.onResult  = onResult
        self.onError   = onError
        self.onStopped = onStopped

        let speechConfig = try! SPXSpeechConfiguration(subscription: subscriptionKey, region: region)
        speechConfig.speechRecognitionLanguage = language

        audioStream = SPXPushAudioInputStream()
        let audioConfig = SPXAudioConfiguration(streamInput: audioStream!)

        reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig,
                                        audioConfiguration: audioConfig)
        reco!.addRecognizingEventHandler { [weak self] _, e in
            self?.onResult(e.result.text, false)
        }
        reco!.addRecognizedEventHandler { [weak self] _, e in
            if e.result.reason == .recognizedSpeech {
                self?.onResult(e.result.text, true)
            }
        }
    }

    func start() throws {
        try reco?.startContinuousRecognition()
        startMicCapture()
    }

    private func startMicCapture() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        audioEngine = AVAudioEngine()
        let input = audioEngine!.inputNode
        let fmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            if let p = buffer.int16ChannelData?.pointee {
                self?.audioStream?.write(Data(bytes: p, count: Int(buffer.frameLength) * 2))
            }
        }
        try? audioEngine?.start()
    }

    func stop() {
        try? reco?.stopContinuousRecognition()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioStream?.close()
        onStopped()
    }

    func dispose() {
        stop()
        reco = nil
    }
}
```

---

## 4. 后台服务（主 App 管理）

后台服务不属于任何单个插件，由**主 App** 的 Android/iOS 原生代码统一管理，各 STT/TTS 插件在录音/播放期间自然持有音频资源，配合后台服务保持进程活跃。

### 4.1 Android（主 App AISupervisoryService）

```
android/app/src/main/kotlin/com/yourcompany/ai_agent_client/
└── AISupervisoryService.kt     # ForegroundService（START_STICKY）
```

服务声明（`android/app/src/main/AndroidManifest.xml`）：
```xml
<service
    android:name=".AISupervisoryService"
    android:foregroundServiceType="microphone|mediaPlayback"
    android:exported="false" />
```

各 STT/TTS 插件无需自己声明 Service，它们的录音/播放操作自然会触发系统对前台服务的感知，而前台服务由主 App 负责持有并展示通知。

### 4.2 iOS（主 App AIServiceManager）

```
ios/Runner/
└── AIServiceManager.swift      # AVAudioSession 激活 + BGTaskScheduler 注册
```

App 启动时在 `AppDelegate` 中调用：
```swift
AIServiceManager.shared.startService()
```

STT/TTS 插件只需正常使用 `AVAudioEngine` 和 `AVSpeechSynthesizer`，因为主 App 已经将 `AVAudioSession` 设置为 `.playAndRecord` + background audio 模式，插件录音/播放不会在后台被打断。

---

## 5. LLM 插件特殊说明（HTTP SSE）

LLM 插件与 STT/TTS 不同，它不需要音频权限，而是在后台执行长 HTTP SSE 连接。

**Android**：OkHttp 的连接在 ForegroundService 的线程池中执行（主 App 服务持有线程，插件在其线程上发起请求）。
**iOS**：`URLSession` background configuration 或依赖 AVAudioSession 的后台激活来保持 App 存活。

LLM 插件 Android 实现关键点：
```kotlin
// llm_openai/android/.../LlmOpenAiPlugin.kt

class LlmOpenAiPlugin : FlutterPlugin, LlmOpenAiHostApi {

    private val client = OkHttpClient.Builder()
        .readTimeout(0, java.util.concurrent.TimeUnit.MILLISECONDS)  // SSE 不超时
        .build()

    override fun chatStream(messages: List<LlmOpenAiMessageMessage?>, config: LlmOpenAiConfigMessage) {
        // 在后台线程执行 SSE 请求，通过 flutterApi.onToken 回调 Flutter
        Thread {
            // OkHttp SSE 实现
        }.start()
    }
}
```

---

## 6. 新增原生插件检查清单

**创建插件包**
- [ ] `flutter create --template=plugin` 创建包
- [ ] `pubspec.yaml` 引用 `ai_plugin_interface`
- [ ] 编写 `pigeons/xxx_messages.dart` 并生成代码

**Dart 层**
- [ ] 实现 `SttProvider` / `TtsProvider` / `LlmProvider` 接口
- [ ] 注册 `FlutterApi` 回调（在构造函数或 `onAttachedToEngine` 中）
- [ ] 所有异常包装为 `PluginException`

**Android 层**
- [ ] `XxxPlugin.kt` 实现 `FlutterPlugin` + `XxxHostApi`
- [ ] `XxxEngine.kt` 纯 SDK 封装（无 Flutter 依赖）
- [ ] `build.gradle` 添加 SDK 依赖
- [ ] 回调切回主线程（`Handler(Looper.getMainLooper()).post { }`）

**iOS 层**
- [ ] `XxxPlugin.swift` 实现 `FlutterPlugin` + `XxxHostApi`
- [ ] `XxxEngine.swift` 纯 SDK 封装
- [ ] `podspec` 添加 SDK 依赖
- [ ] 回调切回主线程（`DispatchQueue.main.async { }`）

**主 App 集成**
- [ ] `pubspec.yaml` 添加路径依赖
- [ ] `EnvKeys` + `AppConfig` 添加配置字段
- [ ] `SttRegistry` / `TtsRegistry` / `LlmRegistry` 注册工厂函数
- [ ] `.env.example` 添加示例 Key
- [ ] `flutter pub get` + `pod install`
