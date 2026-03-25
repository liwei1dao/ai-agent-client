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
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  final String id;
  final String role;
  String content;
  String status; // pending | streaming | done | cancelled | error
  final DateTime createdAt;
}

class ChatAgentState {
  const ChatAgentState({
    this.agentName = '',
    this.agentType = 'chat',
    this.sessionId = '',
    this.sessionState = AgentSessionState.idle,
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
  });

  final String agentName;
  final String agentType; // 'chat' | 'translate' | 'sts' | 'ast'
  final String sessionId;
  final AgentSessionState sessionState;
  final String inputMode;
  final List<ChatMessage> messages;
  final String sttPartial;
  final String? recordingMsgId; // 录音中的临时气泡 id
  final String pendingVoiceText; // 松开后要发送的最终识别文本
  final String llmServiceName;
  final String sttServiceName;
  final String ttsServiceName;
  final String srcLang;  // ast 源语言
  final String dstLang;  // ast 目标语言

  ChatAgentState copyWith({
    String? agentName,
    String? agentType,
    String? sessionId,
    AgentSessionState? sessionState,
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
  }) =>
      ChatAgentState(
        agentName: agentName ?? this.agentName,
        agentType: agentType ?? this.agentType,
        sessionId: sessionId ?? this.sessionId,
        sessionState: sessionState ?? this.sessionState,
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

  Future<void> init() async {
    try {
      // Load agent info
      final agents = await _db.getAllAgents();
      final agent = agents.firstWhere((a) => a.id == _agentId,
          orElse: () => throw Exception('Agent not found'));
      final agentCfg = jsonDecode(agent.configJson) as Map<String, dynamic>;

      // Load history messages
      final rows = await _db.getMessages(_agentId, limit: 50);
      final messages = rows.reversed
          .map((r) => ChatMessage(
                id: r.id,
                role: r.role,
                content: r.content,
                status: r.status,
                createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
              ))
          .toList();

      final sessionId = 'session_$_agentId';

      state = state.copyWith(
        sessionId: sessionId,
        messages: messages,
        agentName: agent.name,
        agentType: agent.type,
        // STS agent 默认未连接（text 模式），用户点电话按钮才连接
        inputMode: 'text',
        srcLang: agentCfg['srcLang'] as String? ?? 'zh',
        dstLang: agentCfg['dstLang'] as String? ?? 'en',
      );

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
      final agentType = agent.type; // 'chat' | 'translate' | 'sts' | 'ast'

      final srcLang = agentCfg['srcLang'] as String? ?? 'zh';
      final dstLang = agentCfg['dstLang'] as String? ?? 'en';

      // Build STS/AST config with language params
      String buildStsConfigJson() {
        final base = svcCfg(stsId);
        if (agentType != 'ast' && agentType != 'sts') return base;
        final map = jsonDecode(base) as Map<String, dynamic>;
        map['srcLang'] = srcLang;
        map['dstLang'] = dstLang;
        return jsonEncode(map);
      }

      state = state.copyWith(
        llmServiceName: svcName(stsId ?? llmId),
        sttServiceName: svcName(sttId),
        ttsServiceName: svcName(ttsId),
      );

      // Create native agent via agents_server
      try {
        await _bridge.createAgent(
          agentId: _agentId,
          agentType: agentType,
          inputMode: 'text',
          sttVendor: svcVendor(sttId).isNotEmpty ? svcVendor(sttId) : null,
          ttsVendor: svcVendor(ttsId).isNotEmpty ? svcVendor(ttsId) : null,
          llmVendor: svcVendor(llmId).isNotEmpty ? svcVendor(llmId) : null,
          stsVendor: (agentType == 'sts' && svcVendor(stsId).isNotEmpty)
              ? svcVendor(stsId) : null,
          astVendor: (agentType == 'ast' && svcVendor(stsId).isNotEmpty)
              ? svcVendor(stsId) : null,
          translationVendor: null, // TODO: add translation service for translate agent
          sttConfigJson: svcCfg(sttId),
          ttsConfigJson: svcCfg(ttsId),
          llmConfigJson: svcCfg(llmId),
          stsConfigJson: agentType == 'sts' ? buildStsConfigJson() : null,
          astConfigJson: agentType == 'ast' ? buildStsConfigJson() : null,
          extraParams: {'srcLang': srcLang, 'dstLang': dstLang},
        );
        debugPrint('[Agent] created: agentType=$agentType id=$_agentId');
      } catch (e) {
        debugPrint('[Agent] createAgent failed: $e');
      }
    } catch (e) {
      debugPrint('[Agent] init failed: $e');
    }
  }

  Future<void> _handleEvent(AgentEvent event) async {
    switch (event) {
      // 使用 `state: agentState` 把字段重命名，避免遮蔽 StateNotifier.state
      case SessionStateEvent(state: final agentState):
        state = state.copyWith(sessionState: agentState);

      case SttEvent(:final kind, :final text):
        if (kind == SttEventKind.partialResult) {
          // 只更新按钮上方的实时预览文字，气泡保持等待动画不变
          state = state.copyWith(sttPartial: text ?? '');
        } else if (kind == SttEventKind.finalResult) {
          // STS 模式：直接显示用户识别文字（不等 listeningStopped，因为 STS 不会发）
          if ((state.agentType == 'sts' || state.agentType == 'ast') &&
              state.inputMode == 'call' &&
              (text ?? '').isNotEmpty) {
            final msgs = List<ChatMessage>.from(state.messages)
              ..add(ChatMessage(
                id: 'sts_user_${DateTime.now().millisecondsSinceEpoch}',
                role: 'user',
                content: text!,
                status: 'done',
              ));
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
          if (idx == -1) {
            msgs.add(ChatMessage(id: requestId, role: 'assistant', content: textDelta, status: 'streaming'));
          } else {
            msgs[idx].content += textDelta;
            msgs[idx].status = 'streaming';
          }
        } else if (kind == LlmEventKind.done) {
          if (idx != -1) msgs[idx].status = 'done';
        } else if (kind == LlmEventKind.cancelled) {
          if (idx != -1) msgs[idx].status = 'cancelled';
        } else if (kind == LlmEventKind.error) {
          ensureAssistant('error', errorMessage ?? '');
        }
        state = state.copyWith(messages: msgs);

      default:
        break;
    }
  }

  Future<void> sendText(String requestId, String text) async {
    // 立即添加到 UI
    final msgs = List<ChatMessage>.from(state.messages)
      ..add(ChatMessage(id: requestId, role: 'user', content: text, status: 'done'));
    state = state.copyWith(messages: msgs);
    await _bridge.sendText(_agentId, requestId, text);
  }

  Future<void> setInputMode(String mode) async {
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

  Future<void> setSrcLang(String lang) async {
    state = state.copyWith(srcLang: lang);
    await _persistLanguages(lang, state.dstLang);
  }

  Future<void> setDstLang(String lang) async {
    state = state.copyWith(dstLang: lang);
    await _persistLanguages(state.srcLang, lang);
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
