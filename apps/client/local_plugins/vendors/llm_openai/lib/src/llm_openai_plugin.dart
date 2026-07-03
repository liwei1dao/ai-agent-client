import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ai_plugin_interface/ai_plugin_interface.dart';

/// LlmOpenaiPlugin — OpenAI-compatible LLM（纯 Dart HTTP + SSE 流式）
///
/// 支持：
///   - streaming chat completions（SSE）
///   - tool_calls SSE 增量解析（按 index 累积 id/name/arguments）
///   - 在 done 事件携带完整 toolCalls 列表，多轮 loop 由 chat agent 容器在外层做
///   - cancel(requestId) 取消
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
      if (tools.isNotEmpty) 'tools': tools.map((t) => t.toJson()).toList(),
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
      // tool_calls 累积器：index → 渐进 state
      final toolBuilders = <int, _ToolCallBuilder>{};
      bool firstToken = true;
      String pending = ''; // 跨 chunk 行缓冲

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        pending += chunk;
        // SSE 按行切分；最后一行可能不完整，留到下次
        final lines = pending.split('\n');
        pending = lines.removeLast();

        for (final raw in lines) {
          final line = raw.trim();
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          if (data == '[DONE]') break;

          final parsed = _parseDelta(data);
          if (parsed == null) continue;

          // 文本增量
          final textDelta = parsed.contentDelta;
          if (textDelta != null && textDelta.isNotEmpty) {
            fullText.write(textDelta);
            yield LlmEvent(
              type: firstToken ? LlmEventType.firstToken : LlmEventType.firstToken,
              requestId: requestId,
              textDelta: textDelta,
            );
            firstToken = false;
          }

          // tool_calls 增量
          for (final tc in parsed.toolCallDeltas) {
            final builder = toolBuilders.putIfAbsent(
              tc.index,
              () => _ToolCallBuilder(),
            );
            if (tc.id != null) builder.id = tc.id;
            if (tc.name != null) builder.name = tc.name;
            if (tc.argumentsDelta != null) {
              builder.arguments.write(tc.argumentsDelta);
            }
          }
        }
      }

      final finalToolCalls = toolBuilders.values
          .where((b) => (b.name ?? '').isNotEmpty)
          .map((b) => ToolCall(
                id: b.id ?? '',
                name: b.name ?? '',
                argumentsJson: b.arguments.toString(),
              ))
          .toList();

      yield LlmEvent(
        type: LlmEventType.done,
        requestId: requestId,
        fullText: fullText.toString(),
        toolCalls: finalToolCalls.isEmpty ? null : finalToolCalls,
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

  // ─────────────────────────────────────────────────
  // SSE delta 解析
  // ─────────────────────────────────────────────────

  _DeltaParsed? _parseDelta(String json) {
    try {
      final obj = jsonDecode(json) as Map<String, dynamic>;
      final choices = obj['choices'] as List?;
      if (choices == null || choices.isEmpty) return null;
      final delta = (choices[0]['delta'] as Map?)?.cast<String, dynamic>();
      if (delta == null) return _DeltaParsed(null, const []);

      final content = delta['content'] as String?;

      final tcs = delta['tool_calls'] as List?;
      final toolDeltas = <_ToolCallDelta>[];
      if (tcs != null) {
        for (final tc in tcs.whereType<Map>()) {
          final fn = (tc['function'] as Map?)?.cast<String, dynamic>();
          toolDeltas.add(_ToolCallDelta(
            index: (tc['index'] as num?)?.toInt() ?? 0,
            id: tc['id'] as String?,
            name: fn?['name'] as String?,
            argumentsDelta: fn?['arguments'] as String?,
          ));
        }
      }
      return _DeltaParsed(content, toolDeltas);
    } catch (_) {
      return null;
    }
  }
}

class _DeltaParsed {
  _DeltaParsed(this.contentDelta, this.toolCallDeltas);
  final String? contentDelta;
  final List<_ToolCallDelta> toolCallDeltas;
}

class _ToolCallDelta {
  _ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsDelta,
  });
  final int index;
  final String? id;
  final String? name;
  final String? argumentsDelta;
}

class _ToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
