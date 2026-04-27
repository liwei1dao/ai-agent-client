import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agents_server/agents_server.dart';
import 'package:local_db/local_db.dart';
// ─── State ────────────────────────────────────────────────────────────────────

const _sentinel = Object();

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.status,
    this.translatedContent,
    this.detectedLang,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id;
  final String role;
  String content;
  String status; // pending | streaming | done | cancelled | error
  String? translatedContent; // 翻译文本（AST翻译模式：原文在content，译文在此）
  String? detectedLang;      // 检测到的源语言代码（用于翻译模式对齐）
  final DateTime createdAt;

  /// 是否为翻译配对消息（同时包含原文和译文）
  bool get isTranslationPair => translatedContent != null;
}

class ChatAgentState {
  const ChatAgentState({
    this.agentName = '',
    this.agentType = 'chat',
    this.sessionId = '',
    this.sessionState = AgentSessionState.idle,
    this.connectionState = ServiceConnectionState.disconnected,
    this.inputMode = 'text',
    this.messages = const [],
    this.sttPartial = '',
    this.recordingMsgId,
    this.pendingVoiceText = '',
    this.llmServiceName = '',
    this.sttServiceName = '',
    this.ttsServiceName = '',
    this.srcLang = 'zh',
    this.dstLang = 'en',
    this.srcLangs = const ['zh', 'en'],
    this.dstLangs = const ['en'],
    this.logs = const [],
  });

  final String agentName;
  final String agentType; // 'chat' | 'translate' | 'sts' | 'ast'
  final String sessionId;
  final AgentSessionState sessionState;
  final ServiceConnectionState connectionState; // 端到端连接状态
  final String inputMode;
  final List<ChatMessage> messages;
  final String sttPartial;
  final String? recordingMsgId; // 录音中的临时气泡 id
  final String pendingVoiceText; // 松开后要发送的最终识别文本
  final String llmServiceName;
  final String sttServiceName;
  final String ttsServiceName;
  final String srcLang;  // 当前激活的源语言
  final String dstLang;  // 当前激活的目标语言
  final List<String> srcLangs; // Agent 配置支持的源语言列表
  final List<String> dstLangs; // Agent 配置支持的目标语言列表
  final List<String> logs;     // 运行日志（启动、连接、事件、错误）

  /// 是否为端到端模式（STS 聊天 / AST 翻译）
  bool get isEndToEnd => agentType == 'sts-chat' || agentType == 'ast-translate';

  /// 是否为翻译类 Agent（AST 翻译 / translate）
  bool get isTranslateMode => agentType == 'ast-translate' || agentType == 'translate';

  ChatAgentState copyWith({
    String? agentName,
    String? agentType,
    String? sessionId,
    AgentSessionState? sessionState,
    ServiceConnectionState? connectionState,
    String? inputMode,
    List<ChatMessage>? messages,
    String? sttPartial,
    Object? recordingMsgId = _sentinel,
    String? pendingVoiceText,
    String? llmServiceName,
    String? sttServiceName,
    String? ttsServiceName,
    String? srcLang,
    String? dstLang,
    List<String>? srcLangs,
    List<String>? dstLangs,
    List<String>? logs,
  }) =>
      ChatAgentState(
        agentName: agentName ?? this.agentName,
        agentType: agentType ?? this.agentType,
        sessionId: sessionId ?? this.sessionId,
        sessionState: sessionState ?? this.sessionState,
        connectionState: connectionState ?? this.connectionState,
        inputMode: inputMode ?? this.inputMode,
        messages: messages ?? this.messages,
        sttPartial: sttPartial ?? this.sttPartial,
        recordingMsgId: recordingMsgId == _sentinel
            ? this.recordingMsgId
            : recordingMsgId as String?,
        pendingVoiceText: pendingVoiceText ?? this.pendingVoiceText,
        llmServiceName: llmServiceName ?? this.llmServiceName,
        sttServiceName: sttServiceName ?? this.sttServiceName,
        ttsServiceName: ttsServiceName ?? this.ttsServiceName,
        srcLang: srcLang ?? this.srcLang,
        dstLang: dstLang ?? this.dstLang,
        srcLangs: srcLangs ?? this.srcLangs,
        dstLangs: dstLangs ?? this.dstLangs,
        logs: logs ?? this.logs,
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final chatAgentProvider =
    StateNotifierProvider.autoDispose
        .family<ChatAgentNotifier, ChatAgentState, String>(
  (ref, agentId) => ChatAgentNotifier(agentId),
);

class ChatAgentNotifier extends StateNotifier<ChatAgentState> {
  ChatAgentNotifier(this._agentId) : super(const ChatAgentState());

  final String _agentId;
  final _bridge = AgentsServerBridge();
  final _db = LocalDbBridge();
  StreamSubscription<AgentEvent>? _eventSub;
  bool _voiceCancelled = false; // 上滑取消标志

  /// Append a timestamped log entry to state and debugPrint
  void _log(String level, String msg) {
    final ts = DateTime.now().toString().substring(11, 23); // HH:mm:ss.mmm
    final entry = '[$ts] $level: $msg';
    debugPrint('[Agent] $msg');
    state = state.copyWith(logs: [...state.logs, entry]);
  }

  Future<void> init() async {
    final initSw = Stopwatch()..start();
    _log('INFO', 'init start, agentId=$_agentId');
    try {
      // Load agent info
      final agents = await _db.getAllAgents();
      final agent = agents.firstWhere((a) => a.id == _agentId,
          orElse: () => throw Exception('Agent not found'));
      final agentCfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
      _log('INFO', 'loaded agent: name=${agent.name}, type=${agent.type}');

      // Load history messages
      final rows = await _db.getMessages(_agentId, limit: 50);
      final isTranslate = agent.type == 'ast-translate' || agent.type == 'translate';
      final rawMessages = rows.reversed.toList();
      final messages = <ChatMessage>[];

      if (isTranslate) {
        // 翻译类 Agent：配对连续的 user + assistant 消息为双语气泡
        int i = 0;
        while (i < rawMessages.length) {
          final r = rawMessages[i];
          if (r.role == 'user' && i + 1 < rawMessages.length && rawMessages[i + 1].role == 'assistant') {
            final trans = rawMessages[i + 1];
            messages.add(ChatMessage(
              id: r.id,
              role: r.role,
              content: r.content,
              status: r.status,
              translatedContent: trans.content,
              detectedLang: _detectLang(r.content),
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ));
            i += 2; // skip the paired assistant message
          } else {
            messages.add(ChatMessage(
              id: r.id,
              role: r.role,
              content: r.content,
              status: r.status,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
            ));
            i++;
          }
        }
        _log('INFO', 'loaded ${rawMessages.length} rows → ${messages.length} paired messages');
      } else {
        for (final r in rawMessages) {
          messages.add(ChatMessage(
            id: r.id,
            role: r.role,
            content: r.content,
            status: r.status,
            createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
          ));
        }
      }

      final sessionId = 'session_$_agentId';

      // Listen to Native events (agents_server uses agentId as sessionId)
      _eventSub = _bridge.eventStream
          .where((e) => e.sessionId == _agentId)
          .listen(_handleEvent);

      // Load referenced service configs
      final allServices = await _db.getAllServiceConfigs();

      String svcCfg(String? id) {
        if (id == null) return '{}';
        try {
          return allServices.firstWhere((s) => s.id == id).configJson;
        } catch (_) {
          return '{}';
        }
      }
      String svcVendor(String? id) {
        if (id == null) return '';
        try {
          return allServices.firstWhere((s) => s.id == id).vendor;
        } catch (_) {
          return '';
        }
      }

      String svcName(String? id) {
        if (id == null) return '';
        try {
          return allServices.firstWhere((s) => s.id == id).name;
        } catch (_) {
          return '';
        }
      }

      final llmId = agentCfg['llmServiceId'] as String?;
      final sttId = agentCfg['sttServiceId'] as String?;
      final ttsId = agentCfg['ttsServiceId'] as String?;
      final stsId = agentCfg['stsServiceId'] as String?;
      final astId = agentCfg['astServiceId'] as String?;
      final translationId = agentCfg['translationServiceId'] as String?;
      // Read supported language lists with fallback
      final srcLangsList = (agentCfg['srcLangs'] as List?)?.cast<String>();
      final dstLangsList = (agentCfg['dstLangs'] as List?)?.cast<String>();
      final srcLangs = srcLangsList ?? [agentCfg['srcLang'] as String? ?? 'zh'];
      final dstLangs = dstLangsList ?? [agentCfg['dstLang'] as String? ?? 'en'];
      var srcLang = agentCfg['srcLang'] as String? ?? srcLangs.first;
      var dstLang = agentCfg['dstLang'] as String? ?? dstLangs.first;

      // Agent type 直接决定模式，不再做 effectiveType 转换
      final agentType = agent.type;
      final isE2E = agentType == 'sts-chat' || agentType == 'ast-translate';

      // AST 不支持 auto 语言，降级为第一个真实语言
      if (agentType == 'ast-translate' && srcLang == 'auto') {
        srcLang = srcLangs.firstWhere((l) => l != 'auto', orElse: () => 'zh');
        _log('INFO', 'AST: srcLang "auto" not supported, fallback to "$srcLang"');
      }

      final e2eServiceId = agentType == 'ast-translate' ? astId : stsId;

      // 把 Agent 级别的 LLM 偏好（如 enableThinking）合入 LLM 服务的配置 JSON
      String buildLlmConfigJson(String? serviceId) {
        final base = svcCfg(serviceId);
        final map = jsonDecode(base) as Map<String, dynamic>;
        final v = agentCfg['enableThinking'];
        if (v != null) map['enableThinking'] = v;
        return jsonEncode(map);
      }

      // Build E2E config — 从 ServiceConfigDto 读取凭证，注入语言和 agentId
      String buildE2eConfigJson(String? serviceId) {
        final base = svcCfg(serviceId);
        final map = jsonDecode(base) as Map<String, dynamic>;
        map['srcLang'] = srcLang;
        map['dstLang'] = dstLang;
        // 注入 Agent 特有的 agentId（polychat 远端 Agent 需要）
        final agentRemoteId = agentCfg['agentId'] as String?;
        if (agentRemoteId != null) {
          map['agentId'] = agentRemoteId;
        }
        return jsonEncode(map);
      }

      String resolveE2eVendor() {
        final id = agentType == 'ast-translate' ? astId : stsId;
        return svcVendor(id);
      }

      String resolveE2eServiceName() {
        return svcName(e2eServiceId ?? llmId);
      }

      _log('INFO', 'agentType=$agentType, isE2E=$isE2E, srcLang=$srcLang, dstLang=$dstLang');
      _log('INFO', 'services: llm=${svcName(llmId)}, stt=${svcName(sttId)}, tts=${svcName(ttsId)}, sts=${svcName(stsId)}, ast=${svcName(astId)}, translation=${svcName(translationId)}');

      state = state.copyWith(
        sessionId: sessionId,
        messages: messages,
        agentName: agent.name,
        agentType: agentType,
        inputMode: isE2E ? 'call' : 'text',
        connectionState: ServiceConnectionState.disconnected,
        srcLang: srcLang,
        dstLang: dstLang,
        srcLangs: srcLangs,
        dstLangs: dstLangs,
        llmServiceName: resolveE2eServiceName(),
        sttServiceName: svcName(sttId),
        ttsServiceName: svcName(ttsId),
      );

      // Create native agent via agents_server
      try {
        final e2eVendor = resolveE2eVendor();
        await _bridge.createAgent(
          agentId: _agentId,
          agentType: agentType,
          inputMode: isE2E ? 'call' : 'text',
          sttVendor: svcVendor(sttId).isNotEmpty ? svcVendor(sttId) : null,
          ttsVendor: svcVendor(ttsId).isNotEmpty ? svcVendor(ttsId) : null,
          llmVendor: svcVendor(llmId).isNotEmpty ? svcVendor(llmId) : null,
          stsVendor: (agentType == 'sts-chat' && e2eVendor.isNotEmpty)
              ? e2eVendor : null,
          astVendor: (agentType == 'ast-translate' && e2eVendor.isNotEmpty)
              ? e2eVendor : null,
          translationVendor: svcVendor(translationId).isNotEmpty ? svcVendor(translationId) : null,
          translationConfigJson: svcCfg(translationId),
          sttConfigJson: svcCfg(sttId),
          ttsConfigJson: svcCfg(ttsId),
          llmConfigJson: buildLlmConfigJson(llmId),
          stsConfigJson: agentType == 'sts-chat' ? buildE2eConfigJson(stsId) : null,
          astConfigJson: agentType == 'ast-translate' ? buildE2eConfigJson(astId) : null,
          extraParams: {
            'srcLang': srcLang,
            'dstLang': dstLang,
            'source_lang': srcLang,
            'target_lang': dstLang,
          },
        );
        _log('INFO', 'createAgent OK in ${initSw.elapsedMilliseconds}ms: type=$agentType e2eSvc=$e2eServiceId');

        // 端到端 Agent 不再自动连接，由用户手动点击连接
        if (isE2E) {
          _log('INFO', 'E2E agent ready, waiting for manual connect');
        }
      } catch (e) {
        _log('ERROR', 'createAgent failed: $e');
        final errMsg = e.toString().replaceFirst('Exception: ', '');
        final msgs = List<ChatMessage>.from(state.messages)
          ..add(ChatMessage(
            id: 'create_err_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            content: 'Agent 创建失败: $errMsg',
            status: 'error',
          ));
        state = state.copyWith(
          messages: msgs,
          connectionState: isE2E ? ServiceConnectionState.error : state.connectionState,
        );
      }
    } catch (e) {
      _log('ERROR', 'init failed: $e');
      final errMsg = e.toString().replaceFirst('Exception: ', '');
      final msgs = List<ChatMessage>.from(state.messages)
        ..add(ChatMessage(
          id: 'init_err_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content: '初始化失败: $errMsg',
          status: 'error',
        ));
      state = state.copyWith(messages: msgs);
    }
  }

  Future<void> _handleEvent(AgentEvent event) async {
    switch (event) {
      // 使用 `state: agentState` 把字段重命名，避免遮蔽 StateNotifier.state
      case SessionStateEvent(state: final agentState):
        _log('EVENT', 'sessionState → $agentState');
        state = state.copyWith(sessionState: agentState);

      case SttEvent(:final kind, :final text):
        if (kind == SttEventKind.partialResult) {
          if (state.inputMode == 'call' && (text ?? '').isNotEmpty) {
            // call 模式（端到端 / 三段式通用）：实时更新用户气泡
            final msgs = List<ChatMessage>.from(state.messages);
            final existingIdx = msgs.lastIndexWhere(
                (m) => m.role == 'user' && m.status == 'streaming');
            if (existingIdx != -1) {
              msgs[existingIdx].content = text!;
            } else {
              final msgId = state.isTranslateMode
                  ? 'ast_src_${DateTime.now().millisecondsSinceEpoch}'
                  : (state.isEndToEnd
                      ? 'sts_user_${DateTime.now().millisecondsSinceEpoch}'
                      : 'call_user_${DateTime.now().millisecondsSinceEpoch}');
              msgs.add(ChatMessage(
                id: msgId,
                role: 'user',
                content: text!,
                status: 'streaming',
                detectedLang: state.isTranslateMode ? _detectLang(text) : null,
              ));
            }
            state = state.copyWith(messages: msgs, sttPartial: text ?? '');
          } else {
            // 非 call 模式：只更新预览文字（push-to-talk）
            state = state.copyWith(sttPartial: text ?? '');
          }
        } else if (kind == SttEventKind.finalResult) {
          // call 模式：定稿用户识别文字（端到端 / 三段式通用）
          if (state.inputMode == 'call' && (text ?? '').isNotEmpty) {
            final msgs = List<ChatMessage>.from(state.messages);
            // 找到正在 streaming 的 user 气泡，标记为 done
            final existingIdx = msgs.lastIndexWhere(
                (m) => m.role == 'user' && m.status == 'streaming');
            if (existingIdx != -1) {
              msgs[existingIdx].content = text!;
              msgs[existingIdx].status = 'done';
              if (state.isTranslateMode) {
                msgs[existingIdx].detectedLang = _detectLang(text);
              }
            } else {
              final msgId = state.isTranslateMode
                  ? 'ast_src_${DateTime.now().millisecondsSinceEpoch}'
                  : 'sts_user_${DateTime.now().millisecondsSinceEpoch}';
              msgs.add(ChatMessage(
                id: msgId,
                role: 'user',
                content: text!,
                status: 'done',
                detectedLang: state.isTranslateMode ? _detectLang(text) : null,
              ));
            }
            _log('EVENT', 'STT finalResult → user msg: "${text!.substring(0, text.length.clamp(0, 40))}"');
            state = state.copyWith(messages: msgs, sttPartial: '');
          } else {
            // 非 STS 模式：暂存最终识别文本，松开时再发送
            state = state.copyWith(
              sttPartial: text ?? '',
              pendingVoiceText: text ?? '',
            );
          }
        } else if (kind == SttEventKind.listeningStopped) {
          // 松开后 STT 停止：移除气泡，若未取消则发送
          // fallback to sttPartial in case finalResult arrived after listeningStopped
          final pending = state.pendingVoiceText.isNotEmpty
              ? state.pendingVoiceText
              : state.sttPartial;
          final msgs = List<ChatMessage>.from(state.messages)
            ..removeWhere((m) => m.id == state.recordingMsgId);
          state = state.copyWith(
            sttPartial: '',
            pendingVoiceText: '',
            messages: msgs,
            recordingMsgId: null,
          );
          if (!_voiceCancelled && pending.isNotEmpty) {
            final requestId = 'voice_${DateTime.now().millisecondsSinceEpoch}';
            final sendMsgs = List<ChatMessage>.from(state.messages)
              ..add(ChatMessage(
                  id: requestId, role: 'user', content: pending, status: 'done'));
            state = state.copyWith(messages: sendMsgs);
            await _bridge.sendText(_agentId, requestId, pending);
          }
          _voiceCancelled = false;
        }

      case LlmEvent(:final kind, :final requestId, :final textDelta, :final errorMessage):
        final msgs = List<ChatMessage>.from(state.messages);
        final idx = msgs.indexWhere((m) => m.id == requestId && m.role == 'assistant');

        // Helper: ensure assistant placeholder exists for this request
        void ensureAssistant(String status, String content) {
          if (idx == -1) {
            msgs.add(ChatMessage(id: requestId, role: 'assistant', content: content, status: status));
          } else {
            msgs[idx].content = content.isNotEmpty ? msgs[idx].content + content : msgs[idx].content;
            msgs[idx].status = status;
          }
        }

        if (kind == LlmEventKind.firstToken && textDelta != null) {
          if (state.isTranslateMode && state.isEndToEnd) {
            // AST 翻译模式：译文写入最近一条 user 消息的 translatedContent
            final userIdx = msgs.lastIndexWhere(
              (m) => m.role == 'user' && m.detectedLang != null);
            if (userIdx != -1) {
              msgs[userIdx].translatedContent = textDelta;
              _log('EVENT', 'LLM firstToken → paired translation: "${textDelta.substring(0, textDelta.length.clamp(0, 30))}"');
            }
          } else if (idx == -1) {
            msgs.add(ChatMessage(id: requestId, role: 'assistant', content: textDelta, status: 'streaming'));
          } else {
            // textDelta 始终是增量片段：
            //   - 三段式 LLM：每次回调一个 token delta
            //   - STS 端到端：web 桥已把 cumulative 快照转成 delta，Android 桥按句下发
            msgs[idx].content += textDelta;
            msgs[idx].status = 'streaming';
          }
        } else if (kind == LlmEventKind.done) {
          if (state.isTranslateMode && state.isEndToEnd) {
            // AST 翻译模式：done 只是标记翻译完成，不需要额外处理
            _log('EVENT', 'LLM done → translation round complete');
          } else if (idx != -1) {
            msgs[idx].status = 'done';
          }
        } else if (kind == LlmEventKind.cancelled) {
          if (idx != -1) msgs[idx].status = 'cancelled';
        } else if (kind == LlmEventKind.error) {
          ensureAssistant('error', errorMessage ?? '');
        }
        state = state.copyWith(messages: msgs);

      case ServiceConnectionStateEvent(:final connectionState, :final errorMessage):
        _log(connectionState == ServiceConnectionState.error ? 'ERROR' : 'EVENT',
            'connectionState → $connectionState${errorMessage != null ? ' ($errorMessage)' : ''}');
        state = state.copyWith(connectionState: connectionState);
        if (connectionState == ServiceConnectionState.error && errorMessage != null) {
          final msgs = List<ChatMessage>.from(state.messages)
            ..add(ChatMessage(
              id: 'conn_err_${DateTime.now().millisecondsSinceEpoch}',
              role: 'assistant',
              content: '连接失败: $errorMessage',
              status: 'error',
            ));
          state = state.copyWith(messages: msgs);
        }

      case AgentErrorEvent(:final errorCode, :final message):
        _log('ERROR', 'AgentError: [$errorCode] $message');
        final msgs = List<ChatMessage>.from(state.messages)
          ..add(ChatMessage(
            id: 'err_${DateTime.now().millisecondsSinceEpoch}',
            role: 'assistant',
            content: '[$errorCode] $message',
            status: 'error',
          ));
        state = state.copyWith(messages: msgs);

      default:
        break;
    }
  }

  // ─── 端到端连接控制 ──────────────────────────────────────────────────────

  Future<void> connectService() async {
    if (!state.isEndToEnd) return;
    state = state.copyWith(connectionState: ServiceConnectionState.connecting);
    try {
      await _bridge.connectService(_agentId);
    } catch (e) {
      _log('ERROR', 'connectService failed: $e');
      state = state.copyWith(connectionState: ServiceConnectionState.error);
    }
  }

  Future<void> disconnectService() async {
    if (!state.isEndToEnd) return;
    await _bridge.disconnectService(_agentId);
    state = state.copyWith(connectionState: ServiceConnectionState.disconnected);
  }

  /// 暂停音频传输（端到端挂断时调用），切到 short_voice 模式
  Future<void> pauseAudio() async {
    if (!state.isEndToEnd) return;
    await _bridge.pauseAudio(_agentId);
    state = state.copyWith(inputMode: 'short_voice');
  }

  /// 恢复音频传输（端到端恢复通话时调用），切到 call 模式
  Future<void> resumeAudio() async {
    if (!state.isEndToEnd) return;
    await _bridge.resumeAudio(_agentId);
    state = state.copyWith(inputMode: 'call');
  }

  Future<void> sendText(String requestId, String text) async {
    // 立即添加到 UI
    final msgs = List<ChatMessage>.from(state.messages)
      ..add(ChatMessage(id: requestId, role: 'user', content: text, status: 'done'));
    state = state.copyWith(messages: msgs);
    await _bridge.sendText(_agentId, requestId, text);
  }

  Future<void> setInputMode(String mode) async {
    // 端到端模式禁止切到 text
    if (state.isEndToEnd && mode == 'text') return;

    // 端到端模式切换：call ↔ short_voice 需要控制音频流
    if (state.isEndToEnd) {
      if (state.inputMode == 'call' && mode == 'short_voice') {
        // 挂断：暂停持续音频流
        await _bridge.pauseAudio(_agentId);
      } else if (state.inputMode == 'short_voice' && mode == 'call') {
        // 恢复通话：恢复持续音频流
        await _bridge.resumeAudio(_agentId);
      }
    }

    state = state.copyWith(inputMode: mode);
    await _bridge.setInputMode(_agentId, mode);
  }

  Future<void> startListening() async {
    // 立即打断当前 AI 回复（停止 LLM + TTS）
    await _bridge.interrupt(_agentId);
    // 添加临时录音气泡
    final recId = 'recording_${DateTime.now().millisecondsSinceEpoch}';
    final msgs = List<ChatMessage>.from(state.messages)
      ..add(ChatMessage(id: recId, role: 'user', content: '', status: 'recording'));
    state = state.copyWith(messages: msgs, recordingMsgId: recId, pendingVoiceText: '', sttPartial: '');
    await _bridge.startListening(_agentId);
  }

  Future<void> stopListening() {
    _voiceCancelled = false;
    return _bridge.stopListening(_agentId);
  }

  Future<void> cancelListening() async {
    _voiceCancelled = true;
    // 立即移除录音气泡，清空状态
    if (state.recordingMsgId != null) {
      final msgs = List<ChatMessage>.from(state.messages)
        ..removeWhere((m) => m.id == state.recordingMsgId);
      state = state.copyWith(
        sttPartial: '',
        pendingVoiceText: '',
        messages: msgs,
        recordingMsgId: null,
      );
    }
    await _bridge.stopListening(_agentId);
  }

  Future<void> swapLanguages() async {
    final src = state.srcLang;
    final dst = state.dstLang;
    state = state.copyWith(srcLang: dst, dstLang: src);
    await _persistLanguages(dst, src);
  }

  /// 设置会话语言（STS 聊天模式：同时设置 src 和 dst）
  Future<void> setConversationLang(String lang) async {
    state = state.copyWith(srcLang: lang, dstLang: lang);
    await _persistLanguages(lang, lang);
  }

  Future<void> setSrcLang(String lang) async {
    state = state.copyWith(srcLang: lang);
    await _persistLanguages(lang, state.dstLang);
  }

  Future<void> setDstLang(String lang) async {
    state = state.copyWith(dstLang: lang);
    await _persistLanguages(state.srcLang, lang);
  }

  /// 通过 CJK 字符占比检测文本语言
  static String _detectLang(String text) {
    final cjk = text.runes.where((c) => c >= 0x4e00 && c <= 0x9fff).length;
    final total = text.runes.where((c) => c > 0x20).length;
    return (total == 0 || cjk / total > 0.3) ? 'zh' : 'en';
  }

  Future<void> _persistLanguages(String src, String dst) async {
    try {
      final agents = await _db.getAllAgents();
      final agent = agents.firstWhere((a) => a.id == _agentId);
      final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
      cfg['srcLang'] = src;
      cfg['dstLang'] = dst;
      await _db.upsertAgent(AgentDto(
        id: agent.id,
        name: agent.name,
        type: agent.type,
        configJson: jsonEncode(cfg),
        createdAt: agent.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (_) {}
  }

  Future<void> clearHistory() async {
    await LocalDbBridge().deleteMessages(_agentId);
    state = state.copyWith(messages: []);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    // 退出时停止 Agent（释放服务资源、断开连接）
    _bridge.stopAgent(_agentId).ignore();
    super.dispose();
  }
}
