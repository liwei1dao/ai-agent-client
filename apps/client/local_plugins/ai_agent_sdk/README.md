# ai_agent_sdk

AI Agent SDK 的门面包。一个依赖、一个 import，拿到完整的接口 + 容器 + 默认 vendor + 默认设备厂商。

## 安装

```yaml
# 业务方 pubspec.yaml
dependencies:
  ai_agent_sdk: ^0.1.0
```

```bash
export PUB_HOSTED_URL=http://localhost:4000   # 或公司内网私服
flutter pub get
```

## 使用

```dart
import 'package:ai_agent_sdk/ai_agent_sdk.dart';

void demo() {
  // 接口层（来自 ai_plugin_interface / device_plugin_interface）
  final llmCfg = LlmConfig(...);
  final caps = {DeviceCapability.audioUplink};

  // 容器层（来自 agents_server / service_manager / translate_server / ...）
  AgentsServerBridge(...);
  TranslateServer(...);
  AssistantServer(...);
}
```

## 包含什么

| 层 | 包 | 是否 export 类型 |
| --- | --- | --- |
| 接口 | `ai_plugin_interface` `device_plugin_interface` | ✓ |
| 容器 | `agents_server` `service_manager` `translate_server` `assistant_server` `device_manager` | ✓ |
| Agent 类型 | `agent_chat` `agent_sts_chat` `agent_translate` `agent_ast_translate` | ✗（仅作 native 自注册触发） |
| 设备厂商 | `device_jieli` | ✗（同上） |
| AI 厂商 | `stt_*` `tts_*` `llm_*` `sts_*` `ast_*` `translation_*` `mcp` | ✗（通过 `agents_server` transitive 自动安装） |

## 重要的命名冲突

`SttEvent` / `LlmEvent` / `TtsEvent` 在 `ai_plugin_interface` 和 `agents_server` 中都有定义但**语义不同**：

- `ai_plugin_interface` 版本：原始厂商插件事件（`type` / `isFinal` 字段）
- `agents_server` 版本：agent 级聚合事件（`sessionId` / `requestId` / `kind` 字段）

本 umbrella 默认导出 **agent 级**版本（更高频使用）。如需厂商级版本（写新厂商插件时），请直接：

```yaml
dependencies:
  ai_plugin_interface: ^0.1.0
```

## 选择性裁剪

如果业务方不需要某个默认 vendor / agent 类型 / 设备厂商，可以在自己的 `pubspec.yaml` 用 `dependency_overrides` 移除——但更简洁的做法是不直接用 umbrella，单独依赖你需要的那几个包。
