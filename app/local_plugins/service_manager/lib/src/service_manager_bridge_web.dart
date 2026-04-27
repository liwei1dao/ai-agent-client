import 'dart:async';
import 'dart:convert';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;
import 'package:ast_polychat/ast_polychat_web.dart';
import 'package:ast_volcengine/ast_volcengine.dart';
import 'package:llm_openai/llm_openai.dart';
import 'package:llm_volcengine/llm_volcengine.dart';
import 'package:local_db/local_db.dart';
import 'package:sts_volcengine/sts_volcengine.dart';
import 'package:sts_polychat/sts_polychat_web.dart';
import 'package:stt_azure/stt_azure.dart';
import 'package:translation_aliyun/translation_aliyun.dart';
import 'package:translation_deepl/translation_deepl.dart';
import 'package:tts_azure/tts_azure.dart';

import 'service_test_event.dart';

/// Web implementation of [ServiceManagerBridge]. Loads service configs from
/// LocalDb (web impl = SharedPreferences), instantiates the appropriate web
/// service plugin, runs the test, and emits `ServiceTestEvent`s. Public API
/// must match the mobile bridge at `src/service_manager_bridge.dart`.
class ServiceManagerBridge {
  static final ServiceManagerBridge _instance = ServiceManagerBridge._();
  ServiceManagerBridge._();
  factory ServiceManagerBridge() => _instance;

  final StreamController<ServiceTestEvent> _events =
      StreamController<ServiceTestEvent>.broadcast();
  final Map<String, _ActiveTest> _tests = {};

  Stream<ServiceTestEvent> get eventStream => _events.stream;

  Future<ServiceConfigDto?> _loadServiceConfig(String serviceId) async {
    final all = await LocalDbBridge().getAllServiceConfigs();
    for (final c in all) {
      if (c.id == serviceId) return c;
    }
    return null;
  }

  // ── STT ────────────────────────────────────────────────────────────────

  Future<void> testSttStart({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(SttTestEvent(
        testId: testId,
        kind: SttTestEventKind.error,
        errorCode: 'service_not_found',
        errorMessage: serviceId,
      ));
      return;
    }
    late ai.SttPlugin plugin;
    try {
      plugin = _createStt(cfg.vendor);
      await plugin.initialize(_parseStt(cfg.configJson));
    } catch (e) {
      _events.add(SttTestEvent(
        testId: testId,
        kind: SttTestEventKind.error,
        errorCode: 'stt_init_failed',
        errorMessage: e.toString(),
      ));
      return;
    }

    final sub = plugin.eventStream.listen((e) {
      final kind = switch (e.type) {
        ai.SttEventType.listeningStarted => SttTestEventKind.listeningStarted,
        ai.SttEventType.vadSpeechStart => SttTestEventKind.vadSpeechStart,
        ai.SttEventType.vadSpeechEnd => SttTestEventKind.vadSpeechEnd,
        ai.SttEventType.partialResult => SttTestEventKind.partialResult,
        ai.SttEventType.finalResult => SttTestEventKind.finalResult,
        ai.SttEventType.listeningStopped => SttTestEventKind.listeningStopped,
        ai.SttEventType.error => SttTestEventKind.error,
      };
      _events.add(SttTestEvent(
        testId: testId,
        kind: kind,
        text: e.text,
        errorCode: e.errorCode,
        errorMessage: e.errorMessage,
      ));
    });
    _tests[testId] = _ActiveTest(plugin, sub);
    await plugin.startListening();
  }

  Future<void> testSttStop(String testId) async {
    final t = _tests[testId];
    if (t == null) return;
    if (t.plugin is ai.SttPlugin) {
      await (t.plugin as ai.SttPlugin).stopListening();
    }
  }

  // ── TTS ────────────────────────────────────────────────────────────────

  Future<void> testTtsSpeak({
    required String testId,
    required String serviceId,
    required String text,
    String? voiceName,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(TtsTestEvent(
        testId: testId,
        kind: TtsTestEventKind.error,
        errorCode: 'service_not_found',
        errorMessage: serviceId,
      ));
      return;
    }
    ai.TtsPlugin plugin;
    try {
      plugin = _createTts(cfg.vendor);
      final ttsCfg = _parseTts(cfg.configJson);
      await plugin.initialize(
        voiceName != null
            ? ai.TtsConfig(
                apiKey: ttsCfg.apiKey,
                region: ttsCfg.region,
                voiceName: voiceName,
                outputFormat: ttsCfg.outputFormat,
                extraParams: ttsCfg.extraParams,
              )
            : ttsCfg,
      );
    } catch (e) {
      _events.add(TtsTestEvent(
        testId: testId,
        kind: TtsTestEventKind.error,
        errorCode: 'tts_init_failed',
        errorMessage: e.toString(),
      ));
      return;
    }

    final sub = plugin.eventStream.listen((e) {
      final kind = switch (e.type) {
        ai.TtsEventType.synthesisStart => TtsTestEventKind.synthesisStart,
        ai.TtsEventType.synthesisReady => TtsTestEventKind.synthesisReady,
        ai.TtsEventType.playbackStart => TtsTestEventKind.playbackStart,
        ai.TtsEventType.playbackProgress => TtsTestEventKind.playbackProgress,
        ai.TtsEventType.playbackDone => TtsTestEventKind.playbackDone,
        ai.TtsEventType.playbackInterrupted =>
          TtsTestEventKind.playbackInterrupted,
        ai.TtsEventType.error => TtsTestEventKind.error,
      };
      _events.add(TtsTestEvent(
        testId: testId,
        kind: kind,
        progressMs: e.progressMs,
        durationMs: e.durationMs,
        errorCode: e.errorCode,
        errorMessage: e.errorMessage,
      ));
    });
    _tests[testId] = _ActiveTest(plugin, sub);
    await plugin.speak(text, requestId: testId);
  }

  Future<void> testTtsStop(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.TtsPlugin) {
      await (t!.plugin as ai.TtsPlugin).stop();
    }
  }

  // ── LLM ────────────────────────────────────────────────────────────────

  Future<void> testLlmChat({
    required String testId,
    required String serviceId,
    required String text,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(LlmTestEvent(
        testId: testId,
        kind: LlmTestEventKind.error,
        errorCode: 'service_not_found',
        errorMessage: serviceId,
      ));
      return;
    }
    late ai.LlmPlugin plugin;
    try {
      plugin = _createLlm(cfg.vendor);
      await plugin.initialize(_parseLlm(cfg.configJson));
    } catch (e) {
      _events.add(LlmTestEvent(
        testId: testId,
        kind: LlmTestEventKind.error,
        errorCode: 'llm_init_failed',
        errorMessage: e.toString(),
      ));
      return;
    }

    final messages = <ai.LlmMessage>[
      ai.LlmMessage(role: ai.MessageRole.user, content: text),
    ];
    final sub = plugin
        .chat(requestId: testId, messages: messages)
        .listen((e) {
      final kind = switch (e.type) {
        ai.LlmEventType.firstToken => LlmTestEventKind.firstToken,
        ai.LlmEventType.thinking => LlmTestEventKind.thinking,
        ai.LlmEventType.toolCallStart => LlmTestEventKind.toolCallStart,
        ai.LlmEventType.toolCallArguments => LlmTestEventKind.toolCallArguments,
        ai.LlmEventType.toolCallResult => LlmTestEventKind.toolCallResult,
        ai.LlmEventType.done => LlmTestEventKind.done,
        ai.LlmEventType.cancelled => LlmTestEventKind.cancelled,
        ai.LlmEventType.error => LlmTestEventKind.error,
      };
      _events.add(LlmTestEvent(
        testId: testId,
        kind: kind,
        textDelta: e.textDelta,
        thinkingDelta: e.thinkingDelta,
        toolCallId: e.toolCall?.id,
        toolName: e.toolCall?.name,
        toolArgumentsDelta: e.toolCall?.argumentsJson,
        toolResult: e.toolResult,
        fullText: e.fullText,
        errorCode: e.errorCode,
        errorMessage: e.errorMessage,
      ));
    });
    _tests[testId] = _ActiveTest(plugin, sub);
  }

  Future<void> testLlmCancel(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.LlmPlugin) {
      (t!.plugin as ai.LlmPlugin).cancel(testId);
    }
  }

  // ── Translation ────────────────────────────────────────────────────────

  Future<void> testTranslate({
    required String testId,
    required String serviceId,
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(TranslationTestEvent(
        testId: testId,
        kind: TranslationTestEventKind.error,
        errorCode: 'service_not_found',
        errorMessage: serviceId,
      ));
      return;
    }
    try {
      final plugin = _createTranslation(cfg.vendor);
      final parsed = _decodeJson(cfg.configJson);
      await plugin.initialize(
        apiKey: (parsed['apiKey'] as String?) ?? '',
        extra: {
          for (final e in (parsed['extra'] as Map? ?? {}).entries)
            e.key.toString(): e.value?.toString() ?? '',
        },
      );
      final result = await plugin.translate(
        text: text,
        targetLanguage: targetLang,
        sourceLanguage: sourceLang,
      );
      _events.add(TranslationTestEvent(
        testId: testId,
        kind: TranslationTestEventKind.result,
        sourceText: result.sourceText,
        translatedText: result.translatedText,
        sourceLanguage: result.sourceLanguage,
        targetLanguage: result.targetLanguage,
      ));
      await plugin.dispose();
    } catch (e) {
      _events.add(TranslationTestEvent(
        testId: testId,
        kind: TranslationTestEventKind.error,
        errorCode: 'translate_failed',
        errorMessage: e.toString(),
      ));
    }
  }

  // ── STS ────────────────────────────────────────────────────────────────

  Future<void> testStsConnect({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(StsTestEvent(
        testId: testId,
        kind: StsTestEventKind.error,
        errorCode: 'service_not_found',
        errorMessage: serviceId,
      ));
      return;
    }
    late ai.StsPlugin plugin;
    try {
      plugin = _createSts(cfg.vendor);
      await plugin.initialize(_parseSts(cfg.configJson));
    } catch (e) {
      _events.add(StsTestEvent(
        testId: testId,
        kind: StsTestEventKind.error,
        errorCode: 'sts_init_failed',
        errorMessage: e.toString(),
      ));
      return;
    }

    final sub = plugin.eventStream.listen((e) {
      final role = _mapStsRole(e.role);
      switch (e.type) {
        case ai.StsEventType.connected:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.connected,
          ));
          break;
        case ai.StsEventType.disconnected:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.disconnected,
          ));
          break;
        case ai.StsEventType.recognitionStart:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.recognitionStart,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.recognizing:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.recognizing,
            role: role,
            requestId: e.requestId,
            text: e.text,
          ));
          break;
        case ai.StsEventType.recognized:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.recognized,
            role: role,
            requestId: e.requestId,
            text: e.text,
          ));
          break;
        case ai.StsEventType.recognitionDone:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.recognitionDone,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.recognitionEnd:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.recognitionEnd,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.recognitionError:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.recognitionError,
            role: role,
            requestId: e.requestId,
            errorCode: e.errorCode,
            errorMessage: e.errorMessage,
          ));
          break;
        case ai.StsEventType.synthesisStart:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.synthesisStart,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.synthesizing:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.synthesizing,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.synthesized:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.synthesized,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.synthesisEnd:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.synthesisEnd,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.synthesisError:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.synthesisError,
            role: role,
            requestId: e.requestId,
            errorCode: e.errorCode,
            errorMessage: e.errorMessage,
          ));
          break;
        case ai.StsEventType.playbackStart:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.playbackStart,
            role: role,
            requestId: e.requestId,
          ));
          break;
        case ai.StsEventType.playbackEnd:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.playbackEnd,
            role: role,
            requestId: e.requestId,
            interrupted: e.interrupted,
          ));
          break;
        case ai.StsEventType.error:
          _events.add(StsTestEvent(
            testId: testId,
            kind: StsTestEventKind.error,
            requestId: e.requestId,
            errorCode: e.errorCode,
            errorMessage: e.errorMessage,
          ));
          break;
        case ai.StsEventType.audioChunk:
          // Audio chunks aren't surfaced to test UI — Web plays audio locally.
          break;
      }
    });
    _tests[testId] = _ActiveTest(plugin, sub);
    await plugin.startCall();
  }

  Future<void> testStsStartAudio(String testId) async {
    // On web the STS plugin self-manages the mic; startCall() already began it.
  }

  Future<void> testStsStopAudio(String testId) async {
    // Same — plugin's stopCall releases mic. Nothing to do between.
  }

  Future<void> testStsDisconnect(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.StsPlugin) {
      await (t!.plugin as ai.StsPlugin).stopCall();
    }
  }

  // ── AST ────────────────────────────────────────────────────────────────

  Future<void> testAstConnect({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(AstTestEvent(
        testId: testId,
        kind: AstTestEventKind.error,
        errorCode: 'service_not_found',
        errorMessage: serviceId,
      ));
      return;
    }
    late ai.AstPlugin plugin;
    try {
      plugin = _createAst(cfg.vendor);
      await plugin.initialize(_parseAst(cfg.configJson));
    } catch (e) {
      _events.add(AstTestEvent(
        testId: testId,
        kind: AstTestEventKind.error,
        errorCode: 'ast_init_failed',
        errorMessage: e.toString(),
      ));
      return;
    }

    final sub = plugin.eventStream.listen((e) {
      switch (e.type) {
        case ai.AstEventType.connected:
          _events.add(AstTestEvent(
            testId: testId,
            kind: AstTestEventKind.connected,
          ));
          break;
        case ai.AstEventType.recognizing:
        case ai.AstEventType.recognized:
          // Map both partial and final recognition output back to the UI
          // subtitle stream so the test panel keeps showing accumulating text.
          final kind = e.role == ai.AstRole.translated
              ? AstTestEventKind.translatedSubtitle
              : AstTestEventKind.sourceSubtitle;
          _events.add(AstTestEvent(
            testId: testId,
            kind: kind,
            text: e.text,
          ));
          break;
        case ai.AstEventType.recognitionStart:
        case ai.AstEventType.recognitionDone:
        case ai.AstEventType.recognitionEnd:
          // Lifecycle markers not surfaced to the test UI.
          break;
        case ai.AstEventType.disconnected:
          _events.add(AstTestEvent(
            testId: testId,
            kind: AstTestEventKind.disconnected,
          ));
          break;
        case ai.AstEventType.recognitionError:
        case ai.AstEventType.error:
          _events.add(AstTestEvent(
            testId: testId,
            kind: AstTestEventKind.error,
            errorCode: e.errorCode,
            errorMessage: e.errorMessage,
          ));
          break;
      }
    });
    _tests[testId] = _ActiveTest(plugin, sub);
    await plugin.startCall();
  }

  Future<void> testAstStartAudio(String testId) async {}
  Future<void> testAstStopAudio(String testId) async {}

  Future<void> testAstDisconnect(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.AstPlugin) {
      await (t!.plugin as ai.AstPlugin).stopCall();
    }
  }

  // ── autoTest / release ─────────────────────────────────────────────────

  Future<void> autoTest({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadServiceConfig(serviceId);
    if (cfg == null) {
      _events.add(ServiceTestDoneEvent(
        testId: testId,
        success: false,
        message: 'service not found',
      ));
      return;
    }
    switch (cfg.type) {
      case 'stt':
        await testSttStart(testId: testId, serviceId: serviceId);
        await Future.delayed(const Duration(seconds: 5));
        await testSttStop(testId);
        break;
      case 'tts':
        await testTtsSpeak(
          testId: testId,
          serviceId: serviceId,
          text: '这是一段自动测试文本。',
        );
        break;
      case 'llm':
        await testLlmChat(
          testId: testId,
          serviceId: serviceId,
          text: 'Hello, please reply briefly.',
        );
        break;
      case 'translation':
        await testTranslate(
          testId: testId,
          serviceId: serviceId,
          text: 'Hello world',
          targetLang: 'zh',
        );
        break;
      case 'sts':
        await testStsConnect(testId: testId, serviceId: serviceId);
        await Future.delayed(const Duration(seconds: 5));
        await testStsDisconnect(testId);
        break;
      case 'ast':
        await testAstConnect(testId: testId, serviceId: serviceId);
        await Future.delayed(const Duration(seconds: 5));
        await testAstDisconnect(testId);
        break;
    }
    _events.add(ServiceTestDoneEvent(testId: testId, success: true));
  }

  Future<void> releaseTest(String testId) async {
    final t = _tests.remove(testId);
    if (t == null) return;
    await t.subscription.cancel();
    try {
      await (t.plugin as dynamic).dispose();
    } catch (_) {}
  }

  // ── Factory methods ────────────────────────────────────────────────────

  ai.SttPlugin _createStt(String vendor) {
    switch (vendor) {
      case 'azure':
        return SttAzurePluginDart();
      default:
        throw UnimplementedError('STT vendor "$vendor" not available on web');
    }
  }

  ai.TtsPlugin _createTts(String vendor) {
    switch (vendor) {
      case 'azure':
        return TtsAzurePluginDart();
      default:
        throw UnimplementedError('TTS vendor "$vendor" not available on web');
    }
  }

  ai.LlmPlugin _createLlm(String vendor) {
    switch (vendor) {
      case 'openai':
        return LlmOpenaiPlugin();
      case 'volcengine':
      case 'doubao': // legacy alias
        return LlmVolcenginePlugin();
      default:
        throw UnimplementedError('LLM vendor "$vendor" not available on web');
    }
  }

  ai.StsPlugin _createSts(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao': // legacy alias
      case 'bytedance':
        return StsVolcenginePlugin();
      case 'polychat':
        return StsPolychatPluginWeb();
      default:
        throw UnimplementedError('STS vendor "$vendor" not available on web');
    }
  }

  ai.AstPlugin _createAst(String vendor) {
    switch (vendor) {
      case 'volcengine':
      case 'doubao': // legacy alias
      case 'bytedance':
        return AstVolcenginePluginWeb();
      case 'polychat':
        return AstPolychatPluginWeb();
      default:
        throw UnimplementedError('AST vendor "$vendor" not available on web');
    }
  }

  ai.TranslationPlugin _createTranslation(String vendor) {
    switch (vendor) {
      case 'deepl':
        return TranslationDeeplPlugin();
      case 'aliyun':
        return TranslationAliyunPlugin();
      default:
        throw UnimplementedError(
            'Translation vendor "$vendor" not available on web');
    }
  }

  // ── Config parsers ─────────────────────────────────────────────────────

  Map<String, dynamic> _decodeJson(String s) {
    if (s.isEmpty) return {};
    try {
      return (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  ai.SttConfig _parseStt(String json) {
    final m = _decodeJson(json);
    return ai.SttConfig(
      apiKey: (m['apiKey'] as String?) ?? '',
      region: (m['region'] as String?) ?? '',
      language: (m['language'] as String?) ?? 'zh-CN',
    );
  }

  ai.TtsConfig _parseTts(String json) {
    final m = _decodeJson(json);
    return ai.TtsConfig(
      apiKey: (m['apiKey'] as String?) ?? '',
      region: (m['region'] as String?) ?? '',
      voiceName: (m['voiceName'] as String?) ?? 'zh-CN-XiaoxiaoNeural',
      outputFormat:
          (m['outputFormat'] as String?) ?? 'audio-16khz-128kbitrate-mono-mp3',
    );
  }

  ai.LlmConfig _parseLlm(String json) {
    final m = _decodeJson(json);
    return ai.LlmConfig(
      apiKey: (m['apiKey'] as String?) ?? '',
      baseUrl: (m['baseUrl'] as String?) ?? 'https://api.openai.com/v1',
      model: (m['model'] as String?) ?? 'gpt-4o-mini',
      temperature: (m['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: (m['maxTokens'] as num?)?.toInt() ?? 2048,
      systemPrompt: m['systemPrompt'] as String?,
    );
  }

  ai.StsConfig _parseSts(String json) {
    final m = _decodeJson(json);
    final voice = (m['voiceType'] as String?) ??
        (m['voiceName'] as String?) ??
        'zh_female_tianmei';
    return ai.StsConfig(
      apiKey: (m['accessToken'] as String?) ?? (m['apiKey'] as String?) ?? '',
      appId: (m['appId'] as String?) ?? '',
      voiceName: voice,
      extraParams: {
        if (m['systemPrompt'] != null)
          'systemPrompt': m['systemPrompt'].toString(),
        // polychat-specific fields forwarded via extraParams so the polychat
        // web plugin can read them without changing the StsConfig contract.
        if (m['baseUrl'] != null) 'baseUrl': m['baseUrl'].toString(),
        if (m['appSecret'] != null) 'appSecret': m['appSecret'].toString(),
        if (m['agentId'] != null) 'agentId': m['agentId'].toString(),
      },
    );
  }

  ai.AstConfig _parseAst(String json) {
    final m = _decodeJson(json);
    return ai.AstConfig(
      apiKey: (m['accessToken'] as String?) ?? (m['apiKey'] as String?) ?? '',
      appId: (m['appId'] as String?) ?? '',
      srcLang: (m['srcLang'] as String?) ?? 'zh',
      dstLang: (m['dstLang'] as String?) ?? 'en',
      extraParams: {
        // polychat-specific fields forwarded via extraParams (see _parseSts).
        if (m['baseUrl'] != null) 'baseUrl': m['baseUrl'].toString(),
        if (m['appSecret'] != null) 'appSecret': m['appSecret'].toString(),
        if (m['agentId'] != null) 'agentId': m['agentId'].toString(),
      },
    );
  }
}

class _ActiveTest {
  _ActiveTest(this.plugin, this.subscription);
  final Object plugin;
  final StreamSubscription subscription;
}

StsTestRole? _mapStsRole(ai.StsRole? role) => switch (role) {
      ai.StsRole.user => StsTestRole.user,
      ai.StsRole.bot => StsTestRole.bot,
      null => null,
    };
