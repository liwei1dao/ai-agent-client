# 桌面平台（macOS / Windows）支持

**日期**：2026-06-04
**状态**：macOS 全链路构建通过（`flutter build macos --debug` exit 0）。Windows 代码已就绪，**需在 Windows 机器上 `flutter build windows` 验证**（开发机为 macOS，无法在此编译 Windows）。

---

## 1. 核心设计：default 分支运行时 Platform 分派

项目原有三套实现：Android(Kotlin 原生)、iOS(Swift 原生)、Web(纯 Dart，条件导入 `dart.library.js_interop`)。

**关键约束**：Dart 条件导入只能用 `dart.library.X` 判别库是否存在，**无法区分 mobile 与 desktop**（两者都满足 `dart.library.io`、都不满足 `js_interop`）。因此桌面采用：

> **在 default（非 web）分支文件内，用运行时 `defaultTargetPlatform` 选择实现**：
> 移动端走原有 MethodChannel 原生；桌面（macOS/Windows/Linux）走纯 Dart。

判定：
```dart
final isDesktop = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
     defaultTargetPlatform == TargetPlatform.windows ||
     defaultTargetPlatform == TargetPlatform.linux);
```

桌面运行时**复用 Web 的纯 Dart 编排逻辑**（`agents_server/lib/src/web/` 的 4 个 agent 是平台无关的），只把音频 I/O 从浏览器 API 换成桌面 Dart 包。

---

## 2. 各层桌面落地

| 模块 | 文件 | 桌面方案 |
|---|---|---|
| 数据库 | `core/local_db/lib/src/local_db_bridge.dart` | `_MethodChannelLocalDb`(移动) / `_PrefsLocalDb`(桌面, SharedPreferences) 运行时分派 |
| Agent 运行时 | `agents/agents_server/lib/src/` | 抽 `AgentServiceFactory` + `AgentsServerApi` + 共享 `DartAgentRuntime`；web 注入 `WebServiceFactory`，桌面注入 `desktop/DesktopServiceFactory`；default bridge 运行时分派 |
| 服务测试 | `agents/service_manager/lib/src/` | 同模式：`ServiceManagerApi` + `ServiceTestFactory` + 共享 `DartServiceTester` |
| 设备域(蓝牙耳机) | `app/lib/core/services/device_service.dart` | 桌面用 `DefaultDeviceManager` 但**不注册任何 vendor**（空 stub，不支持蓝牙耳机） |

### vendor 级运行时分派（音频厂商）
每个音频 vendor 的 default 文件改为 `XxxPluginDart`/`XxxPlugin` 运行时分派移动/桌面实现：

| 能力 | 桌面实现文件 | 协议 | 音频 I/O |
|---|---|---|---|
| TTS azure | `tts_azure/lib/src/tts_azure_plugin_desktop.dart` | Azure REST(SSML) | `audioplayers` 播放 MP3 |
| STT azure | `stt_azure/lib/src/stt_azure_plugin_desktop.dart` | Azure 语音 **WebSocket(USP)** ⚠️ | `record` 采集 16k PCM |
| STS volcengine | `sts_volcengine/lib/src/sts_volcengine_plugin_desktop.dart` | 火山二进制帧+gzip(复用 web 协议) | `record` 采集 + `flutter_pcm_sound` 播放 24k |
| AST volcengine | `ast_volcengine/lib/src/ast_volcengine_plugin_desktop.dart` | protobuf(复用 web 协议) | `record` + `flutter_pcm_sound` |
| polychat sts/ast | （无桌面实现） | 用户单独提供 SDK | 桌面工厂落 stub/抛错 |

> **AST barrel 特例**：`ast_volcengine/lib/ast_volcengine.dart` 的 default 分支已从 web 文件改为桌面文件（纯 Dart），否则桌面/移动会把含 `package:web` 的 web 文件拉进编译而失败。web 侧工厂改从 `package:ast_volcengine/ast_volcengine_web.dart`（含 `export 'src/..._web.dart'`）取 `AstVolcenginePluginWeb`。

> **⚠️ STT azure 桌面未实机验证**：USP WebSocket 协议为纯 Dart 从零实现，未用 Azure 凭据跑通。首次接入请在「服务测试 → STT」用真实 key 核对，必要时按服务端报文微调（时间戳格式 / WAV 头 / requestId）。其余厂商协议直接复用 web 已验证逻辑。

---

## 3. 新增依赖与平台配置

- **app/相关 vendor pubspec**：`record`(麦克风采集 16k PCM)、`flutter_pcm_sound`(裸 PCM 流式播放)；`audioplayers`/`http`/`web_socket_channel` 已有。
- **macOS entitlements**（`macos/Runner/{DebugProfile,Release}.entitlements`）：`com.apple.security.network.client` + `com.apple.security.device.audio-input`；`Info.plist` 加 `NSMicrophoneUsageDescription`。
- **Windows**：经典 Win32 默认有网络与麦克风权限，无需 entitlements（仅 MSIX 打包才需声明）。

### ⚠️ record_linux 依赖覆盖（必读）
`record` 5.x 把 `record_linux` 锁在 `<1.0.0`，解析到过时的 `0.7.2`（不实现 `record_platform_interface` 1.6.0 的 `startStream`），**即使只构建 macOS/Windows 也会编译该 Dart 依赖而报错**。已在 `app/pubspec_overrides.yaml` 末尾加：
```yaml
  record_linux: 1.3.1
```
**注意**：`pubspec_overrides.yaml` 由 `melos bootstrap` 自动生成（仅含 path 覆盖），重新 bootstrap 会**丢失**此行——bootstrap 后若桌面构建报 `record_linux ... missing startStream`，重新补回即可。长期方案：待 `record` 放开 `record_linux` 上限后移除该覆盖。

---

## 4. 桌面已可用能力（macOS 构建验证）

文本对话(LLM)、翻译、MCP、TTS 语音输出、STS/AST 端到端语音、STT 语音输入、服务测试。
蓝牙耳机设备域桌面不支持（stub）。

## 5. 验证清单
- macOS：`flutter build macos --debug` ✅；运行后建议用真实 key 在「服务测试」逐项核对 STT/TTS/STS/AST。
- Windows：在 Windows 机器 `flutter build windows`（共享 Dart 代码两端通用，差异仅在原生插件与音频后端，record/flutter_pcm_sound/audioplayers 均支持 Windows）。
