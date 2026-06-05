import 'dart:async';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:llm_openai/llm_openai.dart';
import 'package:llm_volcengine/llm_volcengine.dart';
import 'package:local_db/local_db.dart';
import 'package:translation_aliyun/translation_aliyun.dart';
import 'package:translation_azure/translation_azure.dart';
import 'package:translation_deepl/translation_deepl.dart';
import 'package:translation_volcengine/translation_volcengine.dart';
import 'package:tts_azure/tts_azure.dart';
import 'package:sts_volcengine/sts_volcengine.dart';
import 'package:ast_volcengine/ast_volcengine.dart';
import 'package:stt_azure/stt_azure.dart';

import 'dart_service_tester.dart';
import 'service_manager_api.dart';
import 'service_test_event.dart';

/// ServiceManagerBridge — 服务测试统一门面（default / 非 web 分支）。
///
/// 条件导入无法区分 mobile 与 desktop（都满足 `dart.library.io`），故运行时
/// [defaultTargetPlatform] 选择后端：
/// - **移动端**：[_MethodChannelServiceManager] —— MethodChannel → 原生
///   NativeServiceRegistry。
/// - **桌面**：[DartServiceTester] + [_DesktopServiceTestFactory] —— 纯 Dart
///   测试器；文本厂商（LLM / 翻译）可用，语音厂商（STT/TTS/STS/AST）桌面暂未实现，
///   抛 UnimplementedError 后由测试器转成 *_init_failed 错误事件（不崩溃）。
class ServiceManagerBridge implements ServiceManagerApi {
  static final ServiceManagerBridge _instance = ServiceManagerBridge._();
  ServiceManagerBridge._() : _impl = _pickImpl();
  factory ServiceManagerBridge() => _instance;

  final ServiceManagerApi _impl;

  static ServiceManagerApi _pickImpl() {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (isDesktop) {
      return DartServiceTester(const _DesktopServiceTestFactory(), _loadConfig);
    }
    return _MethodChannelServiceManager();
  }

  static Future<ServiceConfigRecord?> _loadConfig(String serviceId) async {
    final all = await LocalDbBridge().getAllServiceConfigs();
    for (final c in all) {
      if (c.id == serviceId) {
        return ServiceConfigRecord(
          type: c.type,
          vendor: c.vendor,
          configJson: c.configJson,
        );
      }
    }
    return null;
  }

  @override
  Stream<ServiceTestEvent> get eventStream => _impl.eventStream;

  @override
  Future<void> testSttStart({
    required String testId,
    required String serviceId,
  }) =>
      _impl.testSttStart(testId: testId, serviceId: serviceId);

  @override
  Future<void> testSttStop(String testId) => _impl.testSttStop(testId);

  @override
  Future<void> testTtsSpeak({
    required String testId,
    required String serviceId,
    required String text,
    String? voiceName,
    double speed = 1.0,
    double pitch = 1.0,
  }) =>
      _impl.testTtsSpeak(
        testId: testId,
        serviceId: serviceId,
        text: text,
        voiceName: voiceName,
        speed: speed,
        pitch: pitch,
      );

  @override
  Future<void> testTtsStop(String testId) => _impl.testTtsStop(testId);

  @override
  Future<void> testLlmChat({
    required String testId,
    required String serviceId,
    required String text,
  }) =>
      _impl.testLlmChat(testId: testId, serviceId: serviceId, text: text);

  @override
  Future<void> testLlmCancel(String testId) => _impl.testLlmCancel(testId);

  @override
  Future<void> testTranslate({
    required String testId,
    required String serviceId,
    required String text,
    required String targetLang,
    String? sourceLang,
  }) =>
      _impl.testTranslate(
        testId: testId,
        serviceId: serviceId,
        text: text,
        targetLang: targetLang,
        sourceLang: sourceLang,
      );

  @override
  Future<void> testStsConnect({
    required String testId,
    required String serviceId,
  }) =>
      _impl.testStsConnect(testId: testId, serviceId: serviceId);

  @override
  Future<void> testStsStartAudio(String testId) =>
      _impl.testStsStartAudio(testId);

  @override
  Future<void> testStsStopAudio(String testId) =>
      _impl.testStsStopAudio(testId);

  @override
  Future<void> testStsDisconnect(String testId) =>
      _impl.testStsDisconnect(testId);

  @override
  Future<void> testAstConnect({
    required String testId,
    required String serviceId,
    String? extraConfigJson,
  }) =>
      _impl.testAstConnect(
        testId: testId,
        serviceId: serviceId,
        extraConfigJson: extraConfigJson,
      );

  @override
  Future<void> testAstStartAudio(String testId) =>
      _impl.testAstStartAudio(testId);

  @override
  Future<void> testAstStopAudio(String testId) =>
      _impl.testAstStopAudio(testId);

  @override
  Future<void> testAstDisconnect(String testId) =>
      _impl.testAstDisconnect(testId);

  @override
  Future<void> autoTest({
    required String testId,
    required String serviceId,
  }) =>
      _impl.autoTest(testId: testId, serviceId: serviceId);

  @override
  Future<void> releaseTest(String testId) => _impl.releaseTest(testId);
}

/// 桌面厂商工厂：文本能力真实可用，语音能力暂未实现（抛错由上层转成错误事件）。
class _DesktopServiceTestFactory implements ServiceTestFactory {
  const _DesktopServiceTestFactory();

  @override
  ai.SttPlugin createStt(String vendor) {
    switch (vendor) {
      case 'azure':
        return SttAzurePluginDart();
      default:
        throw UnimplementedError('STT vendor "$vendor" 桌面端暂未实现');
    }
  }

  @override
  ai.TtsPlugin createTts(String vendor) {
    switch (vendor) {
      case 'azure':
        return TtsAzurePluginDart();
      default:
        throw UnimplementedError('TTS vendor "$vendor" 桌面端暂未实现');
    }
  }

  @override
  ai.LlmPlugin createLlm(String vendor) {
    switch (vendor) {
      case 'openai':
        return LlmOpenaiPlugin();
      case 'volcengine':
      case 'doubao':
        return LlmVolcenginePlugin();
      default:
        throw UnimplementedError('LLM vendor "$vendor" 桌面端暂不支持');
    }
  }

  @override
  ai.StsPlugin createSts(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao':
      case 'bytedance':
        return StsVolcenginePlugin();
      default:
        throw UnimplementedError('STS vendor "$vendor" 桌面端暂未实现');
    }
  }

  @override
  ai.AstPlugin createAst(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao':
      case 'bytedance':
        return AstVolcengineDesktop();
      default:
        throw UnimplementedError('AST vendor "$vendor" 桌面端暂未实现');
    }
  }

  @override
  ai.TranslationPlugin createTranslation(String vendor) {
    switch (vendor) {
      case 'deepl':
        return TranslationDeeplPlugin();
      case 'aliyun':
        return TranslationAliyunPlugin();
      case 'azure':
      case 'microsoft':
        return TranslationAzurePlugin();
      case 'volcengine':
        return TranslationVolcenginePlugin();
      default:
        throw UnimplementedError('Translation vendor "$vendor" 桌面端暂不支持');
    }
  }
}

/// 移动端实现：所有命令通过 MethodChannel 发出，事件通过 [eventStream] 接收。
class _MethodChannelServiceManager implements ServiceManagerApi {
  static const _commandChannel = MethodChannel('service_manager/commands');
  static const _eventChannel = EventChannel('service_manager/events');

  Stream<ServiceTestEvent>? _eventStream;

  @override
  Stream<ServiceTestEvent> get eventStream {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) => parseServiceTestEvent(raw as Map<Object?, Object?>))
        .where((e) => e != null)
        .cast<ServiceTestEvent>();
    return _eventStream!;
  }

  @override
  Future<void> testSttStart({
    required String testId,
    required String serviceId,
  }) =>
      _commandChannel.invokeMethod('testSttStart', {
        'testId': testId,
        'serviceId': serviceId,
      });

  @override
  Future<void> testSttStop(String testId) =>
      _commandChannel.invokeMethod('testSttStop', {'testId': testId});

  @override
  Future<void> testTtsSpeak({
    required String testId,
    required String serviceId,
    required String text,
    String? voiceName,
    double speed = 1.0,
    double pitch = 1.0,
  }) =>
      _commandChannel.invokeMethod('testTtsSpeak', {
        'testId': testId,
        'serviceId': serviceId,
        'text': text,
        'voiceName': voiceName,
        'speed': speed,
        'pitch': pitch,
      });

  @override
  Future<void> testTtsStop(String testId) =>
      _commandChannel.invokeMethod('testTtsStop', {'testId': testId});

  @override
  Future<void> testLlmChat({
    required String testId,
    required String serviceId,
    required String text,
  }) =>
      _commandChannel.invokeMethod('testLlmChat', {
        'testId': testId,
        'serviceId': serviceId,
        'text': text,
      });

  @override
  Future<void> testLlmCancel(String testId) =>
      _commandChannel.invokeMethod('testLlmCancel', {'testId': testId});

  @override
  Future<void> testTranslate({
    required String testId,
    required String serviceId,
    required String text,
    required String targetLang,
    String? sourceLang,
  }) =>
      _commandChannel.invokeMethod('testTranslate', {
        'testId': testId,
        'serviceId': serviceId,
        'text': text,
        'targetLang': targetLang,
        'sourceLang': sourceLang,
      });

  @override
  Future<void> testStsConnect({
    required String testId,
    required String serviceId,
  }) =>
      _commandChannel.invokeMethod('testStsConnect', {
        'testId': testId,
        'serviceId': serviceId,
      });

  @override
  Future<void> testStsStartAudio(String testId) =>
      _commandChannel.invokeMethod('testStsStartAudio', {'testId': testId});

  @override
  Future<void> testStsStopAudio(String testId) =>
      _commandChannel.invokeMethod('testStsStopAudio', {'testId': testId});

  @override
  Future<void> testStsDisconnect(String testId) =>
      _commandChannel.invokeMethod('testStsDisconnect', {'testId': testId});

  @override
  Future<void> testAstConnect({
    required String testId,
    required String serviceId,
    String? extraConfigJson,
  }) =>
      _commandChannel.invokeMethod('testAstConnect', {
        'testId': testId,
        'serviceId': serviceId,
        if (extraConfigJson != null) 'extraConfigJson': extraConfigJson,
      });

  @override
  Future<void> testAstStartAudio(String testId) =>
      _commandChannel.invokeMethod('testAstStartAudio', {'testId': testId});

  @override
  Future<void> testAstStopAudio(String testId) =>
      _commandChannel.invokeMethod('testAstStopAudio', {'testId': testId});

  @override
  Future<void> testAstDisconnect(String testId) =>
      _commandChannel.invokeMethod('testAstDisconnect', {'testId': testId});

  @override
  Future<void> autoTest({
    required String testId,
    required String serviceId,
  }) =>
      _commandChannel.invokeMethod('autoTest', {
        'testId': testId,
        'serviceId': serviceId,
      });

  @override
  Future<void> releaseTest(String testId) =>
      _commandChannel.invokeMethod('releaseTest', {'testId': testId});
}
