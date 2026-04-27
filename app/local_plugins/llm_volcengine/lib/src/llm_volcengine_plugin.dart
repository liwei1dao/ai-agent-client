import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// LlmVolcenginePlugin — 火山引擎 Ark LLM（apiKey + 接入点 ID + SSE 流式）
///
/// 配置字段：
///   - apiKey: ARK API Key
///   - model:  接入点 ID（ep-xxx）或模型名
///   - baseUrl: 可选，默认 https://ark.cn-beijing.volces.com/api/v3
class LlmVolcenginePlugin implements LlmPlugin {
  static const String _defaultBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3';

  LlmConfig? _config;
  final Map<String, http.Client> _activeClients = {};

  @override
  Future<void> initialize(LlmConfig config) async {
    _config = config;
  }

  @override
  Stream<LlmEvent> chat({
    required String requestId,
    required List<LlmMessage> messages,
    List<LlmTool> tools = const [],
  }) async* {
    final config = _config!;
    final client = http.Client();
    _activeClients[requestId] = client;

    final enableThinking =
        config.extraParams['enableThinking']?.toLowerCase() == 'true';
    final body = <String, dynamic>{
      'model': config.model,
      'stream': true,
      'messages': messages.map((m) => m.toJson()).toList(),
      if (config.temperature != 0.7) 'temperature': config.temperature,
      if (config.maxTokens != 2048) 'max_tokens': config.maxTokens,
      if (tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
      'thinking': {'type': enableThinking ? 'enabled' : 'disabled'},
    };

    final base = _normalizeBaseUrl(config.baseUrl);
    final uri = Uri.parse('$base/chat/completions');

    final request = http.Request('POST', uri)
      ..headers['Authorization'] = 'Bearer ${config.apiKey}'
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);

    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        yield LlmEvent(
          type: LlmEventType.error,
          requestId: requestId,
          errorCode: 'http_${response.statusCode}',
          errorMessage: response.reasonPhrase,
        );
        return;
      }

      final fullText = StringBuffer();

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('data: ')) continue;
          final data = trimmed.substring(6);
          if (data == '[DONE]') {
            yield LlmEvent(
              type: LlmEventType.done,
              requestId: requestId,
              fullText: fullText.toString(),
            );
            return;
          }

          final delta = _parseTextDelta(data);
          if (delta == null || delta.isEmpty) continue;

          fullText.write(delta);

          yield LlmEvent(
            type: LlmEventType.firstToken,
            requestId: requestId,
            textDelta: delta,
          );
        }
      }

      yield LlmEvent(
        type: LlmEventType.done,
        requestId: requestId,
        fullText: fullText.toString(),
      );
    } on http.ClientException catch (e) {
      yield LlmEvent(
        type: LlmEventType.error,
        requestId: requestId,
        errorCode: 'client_error',
        errorMessage: e.message,
      );
    } catch (e) {
      if (_activeClients.containsKey(requestId)) {
        yield LlmEvent(
          type: LlmEventType.error,
          requestId: requestId,
          errorCode: 'unknown',
          errorMessage: e.toString(),
        );
      }
    } finally {
      _activeClients.remove(requestId)?.close();
    }
  }

  @override
  void cancel(String requestId) {
    _activeClients.remove(requestId)?.close();
  }

  @override
  Future<void> dispose() async {
    for (final client in _activeClients.values) {
      client.close();
    }
    _activeClients.clear();
  }

  String _normalizeBaseUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return _defaultBaseUrl;
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (u.endsWith('/chat/completions')) {
      u = u.substring(0, u.length - '/chat/completions'.length);
    }
    return u;
  }

  String? _parseTextDelta(String json) {
    try {
      final obj = jsonDecode(json) as Map<String, dynamic>;
      final choices = obj['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final delta = choices[0]['delta'] as Map<String, dynamic>?;
      return delta?['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}
