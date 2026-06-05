import 'dart:async';
import 'dart:convert';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import 'service_manager_api.dart';
import 'service_test_event.dart';

/// 纯 Dart 服务测试器 —— web 与 desktop 共用。
///
/// 从 LocalDb 加载服务配置 → 通过注入的 [ServiceTestFactory] 实例化对应能力插件 →
/// 执行测试 → 把插件事件映射为标准化 [ServiceTestEvent]。公开 API 见
/// [ServiceManagerApi]，与移动端 MethodChannel 桥接保持一致。
///
/// 平台差异只在 [ServiceTestFactory]（能用哪些 vendor 实现）。serviceId 配置加载
/// 通过注入的 [_loadConfig] 回调完成，避免本包直接依赖 local_db 的桥接实现。
class DartServiceTester implements ServiceManagerApi {
  DartServiceTester(this._factory, this._loadConfig);

  final ServiceTestFactory _factory;

  /// 按 serviceId 返回 `(type, vendor, configJson)`，找不到返回 null。
  final Future<ServiceConfigRecord?> Function(String serviceId) _loadConfig;

  final StreamController<ServiceTestEvent> _events =
      StreamController<ServiceTestEvent>.broadcast();
  final Map<String, _ActiveTest> _tests = {};

  @override
  Stream<ServiceTestEvent> get eventStream => _events.stream;

  // ── STT ────────────────────────────────────────────────────────────────

  @override
  Future<void> testSttStart({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadConfig(serviceId);
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
      plugin = _factory.createStt(cfg.vendor);
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

  @override
  Future<void> testSttStop(String testId) async {
    final t = _tests[testId];
    if (t == null) return;
    if (t.plugin is ai.SttPlugin) {
      await (t.plugin as ai.SttPlugin).stopListening();
    }
  }

  // ── TTS ────────────────────────────────────────────────────────────────

  @override
  Future<void> testTtsSpeak({
    required String testId,
    required String serviceId,
    required String text,
    String? voiceName,
    double speed = 1.0,
    double pitch = 1.0,
  }) async {
    final cfg = await _loadConfig(serviceId);
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
      plugin = _factory.createTts(cfg.vendor);
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

  @override
  Future<void> testTtsStop(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.TtsPlugin) {
      await (t!.plugin as ai.TtsPlugin).stop();
    }
  }

  // ── LLM ────────────────────────────────────────────────────────────────

  @override
  Future<void> testLlmChat({
    required String testId,
    required String serviceId,
    required String text,
  }) async {
    final cfg = await _loadConfig(serviceId);
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
      plugin = _factory.createLlm(cfg.vendor);
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
    final sub = plugin.chat(requestId: testId, messages: messages).listen((e) {
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

  @override
  Future<void> testLlmCancel(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.LlmPlugin) {
      (t!.plugin as ai.LlmPlugin).cancel(testId);
    }
  }

  // ── Translation ────────────────────────────────────────────────────────

  @override
  Future<void> testTranslate({
    required String testId,
    required String serviceId,
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    final cfg = await _loadConfig(serviceId);
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
      final plugin = _factory.createTranslation(cfg.vendor);
      final parsed = _decodeJson(cfg.configJson);
      final extra = <String, String>{
        for (final e in parsed.entries)
          if (e.key != 'apiKey' && e.value != null) e.key: e.value.toString(),
        for (final e in (parsed['extra'] as Map? ?? {}).entries)
          e.key.toString(): e.value?.toString() ?? '',
      };
      await plugin.initialize(
        apiKey: (parsed['apiKey'] as String?) ?? '',
        extra: extra,
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

  @override
  Future<void> testStsConnect({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadConfig(serviceId);
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
      plugin = _factory.createSts(cfg.vendor);
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
          _events.add(StsTestEvent(testId: testId, kind: StsTestEventKind.connected));
          break;
        case ai.StsEventType.disconnected:
          _events.add(StsTestEvent(testId: testId, kind: StsTestEventKind.disconnected));
          break;
        case ai.StsEventType.recognitionStart:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.recognitionStart,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.recognizing:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.recognizing,
              role: role,
              requestId: e.requestId,
              text: e.text));
          break;
        case ai.StsEventType.recognized:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.recognized,
              role: role,
              requestId: e.requestId,
              text: e.text));
          break;
        case ai.StsEventType.recognitionDone:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.recognitionDone,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.recognitionEnd:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.recognitionEnd,
              requestId: e.requestId));
          break;
        case ai.StsEventType.recognitionError:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.recognitionError,
              role: role,
              requestId: e.requestId,
              errorCode: e.errorCode,
              errorMessage: e.errorMessage));
          break;
        case ai.StsEventType.synthesisStart:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.synthesisStart,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.synthesizing:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.synthesizing,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.synthesized:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.synthesized,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.synthesisEnd:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.synthesisEnd,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.synthesisError:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.synthesisError,
              role: role,
              requestId: e.requestId,
              errorCode: e.errorCode,
              errorMessage: e.errorMessage));
          break;
        case ai.StsEventType.playbackStart:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.playbackStart,
              role: role,
              requestId: e.requestId));
          break;
        case ai.StsEventType.playbackEnd:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.playbackEnd,
              role: role,
              requestId: e.requestId,
              interrupted: e.interrupted));
          break;
        case ai.StsEventType.error:
          _events.add(StsTestEvent(
              testId: testId,
              kind: StsTestEventKind.error,
              requestId: e.requestId,
              errorCode: e.errorCode,
              errorMessage: e.errorMessage));
          break;
        case ai.StsEventType.audioChunk:
          // 音频块不上抛到测试 UI —— 桌面/web 本地播放。
          break;
      }
    });
    _tests[testId] = _ActiveTest(plugin, sub);
    await plugin.startCall();
  }

  @override
  Future<void> testStsStartAudio(String testId) async {}

  @override
  Future<void> testStsStopAudio(String testId) async {}

  @override
  Future<void> testStsDisconnect(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.StsPlugin) {
      await (t!.plugin as ai.StsPlugin).stopCall();
    }
  }

  // ── AST ────────────────────────────────────────────────────────────────

  @override
  Future<void> testAstConnect({
    required String testId,
    required String serviceId,
    String? extraConfigJson,
  }) async {
    final cfg = await _loadConfig(serviceId);
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
      plugin = _factory.createAst(cfg.vendor);
      await plugin.initialize(_parseAst(cfg.configJson, extraConfigJson));
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
          _events.add(AstTestEvent(testId: testId, kind: AstTestEventKind.connected));
          break;
        case ai.AstEventType.recognizing:
        case ai.AstEventType.recognized:
          final kind = e.role == ai.AstRole.translated
              ? AstTestEventKind.translatedSubtitle
              : AstTestEventKind.sourceSubtitle;
          _events.add(AstTestEvent(testId: testId, kind: kind, text: e.text));
          break;
        case ai.AstEventType.recognitionStart:
        case ai.AstEventType.recognitionDone:
        case ai.AstEventType.recognitionEnd:
          break;
        case ai.AstEventType.disconnected:
          _events.add(AstTestEvent(testId: testId, kind: AstTestEventKind.disconnected));
          break;
        case ai.AstEventType.recognitionError:
        case ai.AstEventType.error:
          _events.add(AstTestEvent(
              testId: testId,
              kind: AstTestEventKind.error,
              errorCode: e.errorCode,
              errorMessage: e.errorMessage));
          break;
      }
    });
    _tests[testId] = _ActiveTest(plugin, sub);
    await plugin.startCall();
  }

  @override
  Future<void> testAstStartAudio(String testId) async {}

  @override
  Future<void> testAstStopAudio(String testId) async {}

  @override
  Future<void> testAstDisconnect(String testId) async {
    final t = _tests[testId];
    if (t?.plugin is ai.AstPlugin) {
      await (t!.plugin as ai.AstPlugin).stopCall();
    }
  }

  // ── autoTest / release ─────────────────────────────────────────────────

  @override
  Future<void> autoTest({
    required String testId,
    required String serviceId,
  }) async {
    final cfg = await _loadConfig(serviceId);
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

  @override
  Future<void> releaseTest(String testId) async {
    final t = _tests.remove(testId);
    if (t == null) return;
    await t.subscription.cancel();
    try {
      await (t.plugin as dynamic).dispose();
    } catch (_) {}
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
        if (m['baseUrl'] != null) 'baseUrl': m['baseUrl'].toString(),
        if (m['appSecret'] != null) 'appSecret': m['appSecret'].toString(),
        if (m['agentId'] != null) 'agentId': m['agentId'].toString(),
      },
    );
  }

  ai.AstConfig _parseAst(String json, [String? extraConfigJson]) {
    final m = _decodeJson(json);
    // 测试面板可通过 extraConfigJson 覆盖 srcLang / dstLang / agentId 等。
    if (extraConfigJson != null && extraConfigJson.isNotEmpty) {
      m.addAll(_decodeJson(extraConfigJson));
    }
    return ai.AstConfig(
      apiKey: (m['accessToken'] as String?) ?? (m['apiKey'] as String?) ?? '',
      appId: (m['appId'] as String?) ?? '',
      srcLang: (m['srcLang'] as String?) ?? 'zh',
      dstLang: (m['dstLang'] as String?) ?? 'en',
      extraParams: {
        if (m['baseUrl'] != null) 'baseUrl': m['baseUrl'].toString(),
        if (m['appSecret'] != null) 'appSecret': m['appSecret'].toString(),
        if (m['agentId'] != null) 'agentId': m['agentId'].toString(),
      },
    );
  }
}

/// serviceId 对应的最小配置记录（解耦 local_db 的 DTO）。
class ServiceConfigRecord {
  const ServiceConfigRecord({
    required this.type,
    required this.vendor,
    required this.configJson,
  });
  final String type;
  final String vendor;
  final String configJson;
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
