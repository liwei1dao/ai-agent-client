import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:llm_openai/llm_openai.dart';
import 'package:mcp/mcp.dart';
import 'package:translation_aliyun/translation_aliyun.dart';
import 'package:translation_deepl/translation_deepl.dart';
import 'package:translation_volcengine/translation_volcengine.dart';
import 'package:tts_azure/tts_azure.dart';
import 'package:sts_volcengine/sts_volcengine.dart';
import 'package:ast_volcengine/ast_volcengine.dart';
import 'package:stt_azure/stt_azure.dart';

import '../agent_service_factory.dart';

/// 桌面（macOS / Windows / Linux）厂商工厂。
///
/// - **文本能力**（LLM / 翻译 / MCP）：纯 Dart HTTP 实现，与移动/web 完全一致，
///   开箱即用。
/// - **语音能力**（STT / TTS / STS / AST）：桌面无原生实现。当前用 no-op stub
///   占位，保证三段式 chat / translate agent 在文本模式下能正常初始化与运行；
///   真实桌面音频实现（record 采集 + PCM/MP3 播放）按 vendor 逐个补齐后替换。
///
/// TODO(desktop-audio): 用真实桌面实现替换以下 stub：
///   - tts_azure   → Azure REST + audioplayers（web 已有 REST 逻辑可复用）
///   - stt_azure   → Azure 语音 WebSocket（web 端用的是浏览器 SpeechRecognition，不可移植）
///   - sts/ast volcengine → record 采集 + ws + PCM 无缝播放
class DesktopServiceFactory implements AgentServiceFactory {
  const DesktopServiceFactory();

  @override
  SttPlugin createStt(String vendor) {
    switch (vendor) {
      case 'azure':
        // SttAzurePluginDart 在桌面运行时分派到 Azure 语音 WebSocket + record。
        return SttAzurePluginDart();
      default:
        return _StubStt(vendor);
    }
  }

  @override
  TtsPlugin createTts(String vendor) {
    switch (vendor) {
      case 'azure':
        // TtsAzurePluginDart 在桌面运行时分派到 Azure REST + audioplayers 实现。
        return TtsAzurePluginDart();
      default:
        return _StubTts(vendor);
    }
  }

  @override
  LlmPlugin createLlm(String vendor) {
    switch (vendor) {
      case 'openai':
        return LlmOpenaiPlugin();
      default:
        throw UnimplementedError('LLM vendor "$vendor" 桌面端暂不支持');
    }
  }

  @override
  StsPlugin createSts(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao': // legacy alias
      case 'bytedance':
        // StsVolcenginePlugin 在桌面运行时分派到纯 Dart 协议 + record + pcm_sound。
        return StsVolcenginePlugin();
      default:
        return _StubSts(vendor);
    }
  }

  @override
  AstPlugin createAst(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao': // legacy alias
      case 'bytedance':
        return AstVolcengineDesktop();
      default:
        return _StubAst(vendor);
    }
  }

  @override
  TranslationPlugin createTranslation(String vendor) {
    switch (vendor) {
      case 'deepl':
        return TranslationDeeplPlugin();
      case 'aliyun':
        return TranslationAliyunPlugin();
      case 'volcengine':
        return TranslationVolcenginePlugin();
      default:
        throw UnimplementedError('Translation vendor "$vendor" 桌面端暂不支持');
    }
  }

  @override
  McpPlugin createMcp(String transport) {
    switch (transport) {
      case 'streamable_http':
      case 'http':
        return McpHttpPlugin();
      default:
        throw UnimplementedError('MCP transport "$transport" 桌面端暂不支持');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────
// 临时 no-op stub —— 仅保证 agent 能初始化；不产生任何音频事件。
// 真实桌面音频实现就绪后逐个删除并改走 [AgentServiceFactory] 对应分支。
// ─────────────────────────────────────────────────────────────────────────

class _StubStt implements SttPlugin {
  _StubStt(this.vendor);
  final String vendor;
  final _c = StreamController<SttEvent>.broadcast();

  @override
  bool get supportsLanguageDetection => false;

  @override
  Future<void> initialize(SttConfig config) async {}

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  Stream<SttEvent> get eventStream => _c.stream;

  @override
  Future<void> dispose() async {
    await _c.close();
  }
}

class _StubTts implements TtsPlugin {
  _StubTts(this.vendor);
  final String vendor;
  final _c = StreamController<TtsEvent>.broadcast();

  @override
  Future<void> initialize(TtsConfig config) async {}

  @override
  Future<void> speak(String text, {String? requestId}) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<TtsEvent> get eventStream => _c.stream;

  @override
  Future<void> dispose() async {
    await _c.close();
  }
}

class _StubSts implements StsPlugin {
  _StubSts(this.vendor);
  final String vendor;
  final _c = StreamController<StsEvent>.broadcast();

  @override
  Future<void> initialize(StsConfig config) async {}

  @override
  Future<void> startCall() async {}

  @override
  void sendAudio(List<int> pcmData) {}

  @override
  Future<void> stopCall() async {}

  @override
  Stream<StsEvent> get eventStream => _c.stream;

  @override
  Future<void> dispose() async {
    await _c.close();
  }
}

class _StubAst implements AstPlugin {
  _StubAst(this.vendor);
  final String vendor;
  final _c = StreamController<AstEvent>.broadcast();

  @override
  Future<void> initialize(AstConfig config) async {}

  @override
  Future<void> startCall() async {}

  @override
  void sendAudio(List<int> pcmData) {}

  @override
  Future<void> stopCall() async {}

  @override
  Stream<AstEvent> get eventStream => _c.stream;

  @override
  Future<void> dispose() async {
    await _c.close();
  }
}
