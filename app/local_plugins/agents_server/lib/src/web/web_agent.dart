import 'dart:convert';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;
import 'package:uuid/uuid.dart';

import '../agent_event.dart';

/// Agent config parsed from the Flutter API call.
class WebAgentConfig {
  WebAgentConfig({
    required this.agentId,
    this.inputMode = 'text',
    this.sttVendor,
    this.ttsVendor,
    this.llmVendor,
    this.stsVendor,
    this.astVendor,
    this.translationVendor,
    this.sttConfigJson,
    this.ttsConfigJson,
    this.llmConfigJson,
    this.stsConfigJson,
    this.astConfigJson,
    this.translationConfigJson,
    this.extraParams = const {},
  });

  final String agentId;
  String inputMode;
  final String? sttVendor;
  final String? ttsVendor;
  final String? llmVendor;
  final String? stsVendor;
  final String? astVendor;
  final String? translationVendor;
  final String? sttConfigJson;
  final String? ttsConfigJson;
  final String? llmConfigJson;
  final String? stsConfigJson;
  final String? astConfigJson;
  final String? translationConfigJson;
  final Map<String, String> extraParams;
}

/// Abstract contract every web agent must satisfy — mirrors `NativeAgent.kt`.
abstract class WebAgent {
  Future<void> initialize(WebAgentConfig config);
  Future<void> connectService() async {}
  Future<void> disconnectService() async {}
  Future<void> sendText(String requestId, String text);
  Future<void> startListening();
  Future<void> stopListening();
  Future<void> setInputMode(String mode);
  Future<void> interrupt();
  Future<void> release();
}

/// Utility for parsing common service config JSONs into strongly-typed configs.
class WebConfigParser {
  static ai.SttConfig parseStt(String json) {
    final m = _decode(json);
    return ai.SttConfig(
      apiKey: (m['apiKey'] as String?) ?? '',
      region: (m['region'] as String?) ?? '',
      language: (m['language'] as String?) ?? 'zh-CN',
      extraParams: _toStringMap(m['extra']),
    );
  }

  static ai.TtsConfig parseTts(String json) {
    final m = _decode(json);
    return ai.TtsConfig(
      apiKey: (m['apiKey'] as String?) ?? '',
      region: (m['region'] as String?) ?? '',
      voiceName: (m['voiceName'] as String?) ?? 'zh-CN-XiaoxiaoNeural',
      outputFormat:
          (m['outputFormat'] as String?) ?? 'audio-16khz-128kbitrate-mono-mp3',
      extraParams: _toStringMap(m['extra']),
    );
  }

  static ai.LlmConfig parseLlm(String json) {
    final m = _decode(json);
    return ai.LlmConfig(
      apiKey: (m['apiKey'] as String?) ?? '',
      baseUrl: (m['baseUrl'] as String?) ?? 'https://api.openai.com/v1',
      model: (m['model'] as String?) ?? 'gpt-4o-mini',
      temperature: (m['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: (m['maxTokens'] as num?)?.toInt() ?? 2048,
      systemPrompt: m['systemPrompt'] as String?,
      extraParams: _toStringMap({
        ...?(m['extra'] as Map?),
        if (m['enableThinking'] != null) 'enableThinking': m['enableThinking'],
      }),
    );
  }

  static ai.StsConfig parseSts(String json) {
    final m = _decode(json);
    final voice = (m['voiceType'] as String?) ??
        (m['voiceName'] as String?) ??
        'zh_female_tianmei';
    return ai.StsConfig(
      apiKey: (m['accessToken'] as String?) ?? (m['apiKey'] as String?) ?? '',
      appId: (m['appId'] as String?) ?? '',
      voiceName: voice,
      extraParams: _toStringMap({
        if (m['systemPrompt'] != null) 'systemPrompt': m['systemPrompt'],
        // polychat-specific fields forwarded via extraParams so the polychat
        // web plugin can read them without changing the StsConfig contract.
        if (m['baseUrl'] != null) 'baseUrl': m['baseUrl'],
        if (m['appSecret'] != null) 'appSecret': m['appSecret'],
        if (m['agentId'] != null) 'agentId': m['agentId'],
        ...?(m['extra'] as Map?),
      }),
    );
  }

  static ai.AstConfig parseAst(String json, {String? srcLang, String? dstLang}) {
    final m = _decode(json);
    return ai.AstConfig(
      apiKey: (m['accessToken'] as String?) ?? (m['apiKey'] as String?) ?? '',
      appId: (m['appId'] as String?) ?? '',
      srcLang: srcLang ?? (m['srcLang'] as String?) ?? 'zh',
      dstLang: dstLang ?? (m['dstLang'] as String?) ?? 'en',
      extraParams: _toStringMap({
        // polychat-specific fields forwarded via extraParams (see parseSts).
        if (m['baseUrl'] != null) 'baseUrl': m['baseUrl'],
        if (m['appSecret'] != null) 'appSecret': m['appSecret'],
        if (m['agentId'] != null) 'agentId': m['agentId'],
        ...?(m['extra'] as Map?),
      }),
    );
  }

  static Map<String, dynamic> _decode(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      return (jsonDecode(json) as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  static Map<String, String> _toStringMap(dynamic v) {
    if (v is! Map) return const {};
    return v.map((k, val) => MapEntry(k.toString(), val?.toString() ?? ''));
  }
}

/// Helper to emit a SessionStateEvent.
typedef AgentEventEmitter = void Function(AgentEvent event);

SessionStateEvent stateEvent(
  String agentId,
  AgentSessionState state, {
  String? requestId,
}) =>
    SessionStateEvent(sessionId: agentId, state: state, requestId: requestId);

/// Simple UUID helper.
final _uuid = Uuid();
String newRequestId() => _uuid.v4();

/// Latest-wins request tracker: each call to [start] returns a token and
/// invalidates older tokens. Use [isActive] to skip stale continuations.
class RequestGate {
  String? current;
  String start(String id) {
    current = id;
    return id;
  }

  bool isActive(String id) => current == id;

  void clear() {
    current = null;
  }
}

