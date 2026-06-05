import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import 'service_test_event.dart';

/// service_manager 对外统一的服务测试契约。
///
/// 三个后端实现它，保证 UI 平台无关：
/// - 移动端：MethodChannel → 原生 NativeServiceRegistry（`service_manager_bridge.dart`）；
/// - web / desktop：纯 Dart [DartServiceTester]。
abstract interface class ServiceManagerApi {
  Stream<ServiceTestEvent> get eventStream;

  Future<void> testSttStart({required String testId, required String serviceId});
  Future<void> testSttStop(String testId);

  Future<void> testTtsSpeak({
    required String testId,
    required String serviceId,
    required String text,
    String? voiceName,
    double speed,
    double pitch,
  });
  Future<void> testTtsStop(String testId);

  Future<void> testLlmChat({
    required String testId,
    required String serviceId,
    required String text,
  });
  Future<void> testLlmCancel(String testId);

  Future<void> testTranslate({
    required String testId,
    required String serviceId,
    required String text,
    required String targetLang,
    String? sourceLang,
  });

  Future<void> testStsConnect({required String testId, required String serviceId});
  Future<void> testStsStartAudio(String testId);
  Future<void> testStsStopAudio(String testId);
  Future<void> testStsDisconnect(String testId);

  Future<void> testAstConnect({
    required String testId,
    required String serviceId,
    String? extraConfigJson,
  });
  Future<void> testAstStartAudio(String testId);
  Future<void> testAstStopAudio(String testId);
  Future<void> testAstDisconnect(String testId);

  Future<void> autoTest({required String testId, required String serviceId});
  Future<void> releaseTest(String testId);
}

/// 厂商工厂抽象（service_manager 局部，独立于 agents_server 的同名接口以避免跨包依赖）。
abstract interface class ServiceTestFactory {
  ai.SttPlugin createStt(String vendor);
  ai.TtsPlugin createTts(String vendor);
  ai.LlmPlugin createLlm(String vendor);
  ai.StsPlugin createSts(String vendor);
  ai.AstPlugin createAst(String vendor);
  ai.TranslationPlugin createTranslation(String vendor);
}
