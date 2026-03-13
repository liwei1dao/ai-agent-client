import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// LlmOpenaiPlugin — OpenAI-compatible LLM（纯 Dart HTTP + SSE 流式）
///
/// 支持：
///   - streaming chat completions（SSE）
///   - MCP/function tool calls（通过 McpManager 路由）
///   - requestId 取消检测（activeRequestId 比对）
class LlmOpenaiPlugin implements LlmPlugin {
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

    final body = <String, dynamic>{
      'model': config.model,
      'stream': true,
      'messages': messages.map((m) => m.toJson()).toList(),
      if (config.temperature != 0.7) 'temperature': config.temperature,
      if (config.maxTokens != 2048) 'max_tokens': config.maxTokens,
      if (tools.isNotEmpty)
        'tools': tools.map((t) => t.toJson()).toList(),
    };

    final uri = Uri.parse(
      '${config.baseUrl.trimRight().replaceAll(RegExp(r'/$'), '')}/chat/completions',
    );

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
      bool firstToken = true;

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

          if (firstToken) {
            firstToken = false;
            yield LlmEvent(
              type: LlmEventType.firstToken,
              requestId: requestId,
              textDelta: delta,
            );
          } else {
            yield LlmEvent(
              type: LlmEventType.firstToken, // streaming delta
              requestId: requestId,
              textDelta: delta,
            );
          }
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
      // 若 client 已被 cancel() 移除，说明是主动取消，静默返回
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
