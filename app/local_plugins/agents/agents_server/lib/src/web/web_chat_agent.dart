import 'dart:async';
import 'dart:convert';

import 'package:ai_plugin_interface/ai_plugin_interface.dart' as ai;

import '../agent_event.dart';
import '../mcp/mcp_router.dart';
import 'web_agent.dart';
import 'web_service_factory.dart';

/// Chat agent — STT + LLM + TTS pipeline. Ports ChatAgentSession.kt.
/// Message persistence is skipped on web; history is maintained in-memory only.
class WebChatAgent implements WebAgent {
  WebChatAgent(this._emit);

  final AgentEventEmitter _emit;

  late WebAgentConfig _config;
  late ai.SttPlugin _stt;
  late ai.LlmPlugin _llm;
  late ai.TtsPlugin _tts;
  McpRouter? _mcp;

  /// 由 LLM 服务配置带入的指令列表（name -> def），用于 tool 路由分流。
  final Map<String, ai.LlmInstructionDef> _instructions = {};

  /// 合并后的 LLM tools 缓存（MCP tools + 指令转换出的 tools）。
  List<ai.LlmTool> _mergedTools = const [];

  StreamSubscription<ai.SttEvent>? _sttSub;
  StreamSubscription<ai.TtsEvent>? _ttsSub;

  final _gate = RequestGate();
  final List<ai.LlmMessage> _history = [];
  String _inputMode = 'text';
  AgentSessionState _state = AgentSessionState.idle;

  /// 单次用户输入 → LLM 多轮 tool loop 的上限，防止死循环。
  static const int _maxToolIterations = 5;

  void _setState(AgentSessionState s, {String? requestId}) {
    _state = s;
    _emit(stateEvent(_config.agentId, s, requestId: requestId));
  }

  @override
  Future<void> initialize(WebAgentConfig config) async {
    _config = config;
    _inputMode = config.inputMode;

    _stt = WebServiceFactory.createStt(config.sttVendor ?? 'azure');
    _llm = WebServiceFactory.createLlm(config.llmVendor ?? 'openai');
    _tts = WebServiceFactory.createTts(config.ttsVendor ?? 'azure');

    await _stt.initialize(
      WebConfigParser.parseStt(config.sttConfigJson ?? '{}'),
    );
    await _llm.initialize(
      WebConfigParser.parseLlm(config.llmConfigJson ?? '{}'),
    );
    await _tts.initialize(
      WebConfigParser.parseTts(config.ttsConfigJson ?? '{}'),
    );

    _sttSub = _stt.eventStream.listen(_onStt);
    _ttsSub = _tts.eventStream.listen(_onTts);

    // Seed system prompt into history if present.
    final llmCfg = WebConfigParser.parseLlm(config.llmConfigJson ?? '{}');
    final sys = llmCfg.systemPrompt;
    if (sys != null && sys.isNotEmpty) {
      _history.add(ai.LlmMessage(role: ai.MessageRole.system, content: sys));
    }

    // 加载用户在 LLM 服务里登记的指令（指令名 -> 定义）。
    for (final def in llmCfg.instructions) {
      if (def.name.isEmpty) continue;
      _instructions[def.name] = def;
    }

    // 连接 MCP 服务器（每个 server 独立失败容忍）。
    final servers = WebConfigParser.parseMcpServers(config.mcpServersJson);
    if (servers.isNotEmpty) {
      _mcp = McpRouter(
        pluginFactory: WebServiceFactory.createMcp,
      );
      for (final s in servers) {
        await _mcp!.addServer(s);
      }
    }

    _rebuildMergedTools();
  }

  void _rebuildMergedTools() {
    final out = <ai.LlmTool>[];
    final mcpTools = _mcp?.llmTools ?? const <ai.LlmTool>[];
    out.addAll(mcpTools);
    // 指令同名时 MCP 优先（避免覆盖真实工具）。
    final mcpNames = mcpTools.map((t) => t.name).toSet();
    for (final def in _instructions.values) {
      if (mcpNames.contains(def.name)) continue;
      out.add(def.toLlmTool());
    }
    _mergedTools = out;
  }

  @override
  Future<void> connectService() async {
    // 三段式 agent 无远端长连接：服务在 initialize 阶段已就位，立即上报 ready。
    _emit(AgentReadyEvent(sessionId: _config.agentId, ready: true));
  }

  @override
  Future<void> disconnectService() async {}

  @override
  Future<void> sendText(String requestId, String text) =>
      _runPipeline(requestId, text);

  @override
  Future<void> startListening() async {
    _setState(AgentSessionState.listening);
    await _stt.startListening();
  }

  @override
  Future<void> stopListening() async => _stt.stopListening();

  @override
  Future<void> setOption(String key, String value) async {}

  @override
  Future<void> setInputMode(String mode) async {
    _inputMode = mode;
    _config.inputMode = mode;
    if (mode == 'call') {
      final id = _gate.current;
      if (id != null) _llm.cancel(id);
      await _tts.stop();
      _gate.clear();
      _setState(AgentSessionState.listening);
      await _stt.startListening();
    } else if (mode == 'text') {
      await _stt.stopListening();
    }
  }

  @override
  Future<void> interrupt() async {
    final id = _gate.current;
    if (id != null) _llm.cancel(id);
    await _tts.stop();
    _gate.clear();
    _setState(AgentSessionState.idle);
  }

  @override
  Future<void> release() async {
    await _sttSub?.cancel();
    await _ttsSub?.cancel();
    await _stt.dispose();
    await _tts.dispose();
    await _llm.dispose();
    await _mcp?.dispose();
  }

  void _onStt(ai.SttEvent e) {
    switch (e.type) {
      case ai.SttEventType.listeningStarted:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.listeningStarted,
        ));
        break;
      case ai.SttEventType.vadSpeechStart:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.vadSpeechStart,
        ));
        _interruptForVoiceInput();
        break;
      case ai.SttEventType.vadSpeechEnd:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.vadSpeechEnd,
        ));
        break;
      case ai.SttEventType.partialResult:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.partialResult,
          text: e.text,
        ));
        break;
      case ai.SttEventType.finalResult:
        final rid = newRequestId();
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: rid,
          kind: SttEventKind.finalResult,
          text: e.text,
        ));
        if (_inputMode == 'call' && (e.text ?? '').isNotEmpty) {
          _runPipeline(rid, e.text!);
        }
        break;
      case ai.SttEventType.listeningStopped:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.listeningStopped,
        ));
        break;
      case ai.SttEventType.error:
        _emit(SttEvent(
          sessionId: _config.agentId,
          requestId: '',
          kind: SttEventKind.error,
          errorCode: e.errorCode,
          errorMessage: e.errorMessage,
        ));
        break;
    }
  }

  void _onTts(ai.TtsEvent e) {
    final rid = _gate.current ?? '';
    final kind = switch (e.type) {
      ai.TtsEventType.synthesisStart => TtsEventKind.synthesisStart,
      ai.TtsEventType.synthesisReady => TtsEventKind.synthesisReady,
      ai.TtsEventType.playbackStart => TtsEventKind.playbackStart,
      ai.TtsEventType.playbackProgress => TtsEventKind.playbackProgress,
      ai.TtsEventType.playbackDone => TtsEventKind.playbackDone,
      ai.TtsEventType.playbackInterrupted => TtsEventKind.playbackInterrupted,
      ai.TtsEventType.error => TtsEventKind.error,
    };
    _emit(TtsEvent(
      sessionId: _config.agentId,
      requestId: rid,
      kind: kind,
      progressMs: e.progressMs,
      durationMs: e.durationMs,
      errorCode: e.errorCode,
      errorMessage: e.errorMessage,
    ));
  }

  Future<void> _runPipeline(String requestId, String text) async {
    _gate.start(requestId);
    _history.add(ai.LlmMessage(role: ai.MessageRole.user, content: text));

    _setState(AgentSessionState.llm, requestId: requestId);

    String finalText = '';
    bool produced = false;

    for (int iter = 0; iter < _maxToolIterations; iter++) {
      final buffer = StringBuffer();
      List<ai.ToolCall>? pendingToolCalls;
      bool aborted = false;

      try {
        await for (final event in _llm.chat(
          requestId: requestId,
          messages: _history,
          tools: _mergedTools,
        )) {
          if (!_gate.isActive(requestId)) return;
          switch (event.type) {
            case ai.LlmEventType.firstToken:
              final delta = event.textDelta ?? '';
              if (delta.isNotEmpty) {
                buffer.write(delta);
                _emit(LlmEvent(
                  sessionId: _config.agentId,
                  requestId: requestId,
                  kind: LlmEventKind.firstToken,
                  textDelta: delta,
                ));
              }
              break;
            case ai.LlmEventType.thinking:
              _emit(LlmEvent(
                sessionId: _config.agentId,
                requestId: requestId,
                kind: LlmEventKind.thinking,
                thinkingDelta: event.thinkingDelta,
              ));
              break;
            case ai.LlmEventType.done:
              final full = event.fullText ?? buffer.toString();
              pendingToolCalls = event.toolCalls;
              if (pendingToolCalls == null || pendingToolCalls.isEmpty) {
                _emit(LlmEvent(
                  sessionId: _config.agentId,
                  requestId: requestId,
                  kind: LlmEventKind.done,
                  fullText: full,
                ));
                if (full.isNotEmpty) {
                  _history.add(ai.LlmMessage(
                    role: ai.MessageRole.assistant,
                    content: full,
                  ));
                  finalText = full;
                  produced = true;
                }
              } else {
                // 工具调用阶段：把 assistant 的 tool_calls 消息加进历史
                // OpenAI 协议：tool_calls 时 content 可空
                _history.add(ai.LlmMessage(
                  role: ai.MessageRole.assistant,
                  content: full,
                  toolCalls: pendingToolCalls,
                ));
              }
              break;
            case ai.LlmEventType.cancelled:
              _emit(LlmEvent(
                sessionId: _config.agentId,
                requestId: requestId,
                kind: LlmEventKind.cancelled,
              ));
              return;
            case ai.LlmEventType.error:
              _emit(LlmEvent(
                sessionId: _config.agentId,
                requestId: requestId,
                kind: LlmEventKind.error,
                errorCode: event.errorCode,
                errorMessage: event.errorMessage,
              ));
              aborted = true;
              break;
            case ai.LlmEventType.toolCallStart:
            case ai.LlmEventType.toolCallArguments:
            case ai.LlmEventType.toolCallResult:
              // plugin 暂不发中间事件；预留以兼容未来流式 tool_call UI。
              break;
          }
        }
      } catch (e) {
        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: requestId,
          kind: LlmEventKind.error,
          errorCode: 'llm.exception',
          errorMessage: e.toString(),
        ));
        return;
      }

      if (aborted) return;
      if (!_gate.isActive(requestId)) return;

      if (pendingToolCalls == null || pendingToolCalls.isEmpty) {
        // 没有 tool 调用 — 跳出 loop 进 TTS
        break;
      }

      // 执行 tool calls，结果回灌为 tool 角色消息，准备下一轮
      for (final tc in pendingToolCalls) {
        if (!_gate.isActive(requestId)) return;

        Map<String, dynamic> args = const {};
        try {
          if (tc.argumentsJson.isNotEmpty) {
            final decoded = jsonDecode(tc.argumentsJson);
            if (decoded is Map) args = decoded.cast<String, dynamic>();
          }
        } catch (_) {
          // 无效 JSON 参数：留空交给 handler / MCP server 自行处理 / 报错
        }

        final instructionDef = _instructions[tc.name];
        if (instructionDef != null) {
          // 指令路径：派发 instructionTriggered 事件，由 InstructionHandlerRegistry
          // 处理副作用（未注册时填默认 "ok" 让 LLM 对话能继续）。
          final handlerResult = await ai.InstructionHandlerRegistry.instance
              .dispatch(tc.name, args);
          final resultText = handlerResult ??
              '{"status":"ok","instruction":"${tc.name}"}';

          _emit(LlmEvent(
            sessionId: _config.agentId,
            requestId: requestId,
            kind: LlmEventKind.instructionTriggered,
            toolCallId: tc.id,
            toolName: tc.name,
            toolArgumentsDelta: tc.argumentsJson,
            toolResult: resultText,
          ));

          _history.add(ai.LlmMessage(
            role: ai.MessageRole.tool,
            content: resultText,
            toolCallId: tc.id,
            name: tc.name,
          ));
          continue;
        }

        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: requestId,
          kind: LlmEventKind.toolCallStart,
          toolCallId: tc.id,
          toolName: tc.name,
          toolArgumentsDelta: tc.argumentsJson,
        ));

        final result = _mcp == null
            ? ai.McpToolResult(
                content: 'Error: no MCP servers configured',
                isError: true,
              )
            : await _mcp!.callTool(tc.name, args);

        _emit(LlmEvent(
          sessionId: _config.agentId,
          requestId: requestId,
          kind: LlmEventKind.toolCallResult,
          toolCallId: tc.id,
          toolName: tc.name,
          toolResult: result.content,
        ));

        _history.add(ai.LlmMessage(
          role: ai.MessageRole.tool,
          content: result.content,
          toolCallId: tc.id,
          name: tc.name,
        ));
      }
      // 继续下一轮 LLM
    }

    if (!_gate.isActive(requestId)) return;

    if (produced && finalText.isNotEmpty) {
      _setState(AgentSessionState.tts, requestId: requestId);
      await _tts.speak(finalText, requestId: requestId);
    }

    if (_gate.isActive(requestId)) {
      _setState(AgentSessionState.idle);
      if (_inputMode == 'call') {
        _setState(AgentSessionState.listening);
        await _stt.startListening();
      }
    }
  }

  void _interruptForVoiceInput() {
    if (_state == AgentSessionState.idle ||
        _state == AgentSessionState.listening) {
      return;
    }
    final prev = _gate.current;
    if (prev != null) _llm.cancel(prev);
    _tts.stop();
    _gate.clear();
    _setState(AgentSessionState.listening);
  }
}
