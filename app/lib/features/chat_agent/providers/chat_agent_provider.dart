import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agent_runtime/agent_runtime.dart';
import 'package:local_db/local_db.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.status,
  });
  final String id;
  final String role;
  String content;
  String status; // pending | streaming | done | cancelled | error
}

class ChatAgentState {
  const ChatAgentState({
    this.agentName = '',
    this.sessionId = '',
    this.sessionState = AgentSessionState.idle,
    this.inputMode = 'text',
    this.messages = const [],
    this.sttPartial = '',
  });

  final String agentName;
  final String sessionId;
  final AgentSessionState sessionState;
  final String inputMode;
  final List<ChatMessage> messages;
  final String sttPartial;

  ChatAgentState copyWith({
    String? agentName,
    String? sessionId,
    AgentSessionState? sessionState,
    String? inputMode,
    List<ChatMessage>? messages,
    String? sttPartial,
  }) =>
      ChatAgentState(
        agentName: agentName ?? this.agentName,
        sessionId: sessionId ?? this.sessionId,
        sessionState: sessionState ?? this.sessionState,
        inputMode: inputMode ?? this.inputMode,
        messages: messages ?? this.messages,
        sttPartial: sttPartial ?? this.sttPartial,
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final chatAgentProvider =
    StateNotifierProvider.family<ChatAgentNotifier, ChatAgentState, String>(
  (ref, agentId) => ChatAgentNotifier(agentId),
);

class ChatAgentNotifier extends StateNotifier<ChatAgentState> {
  ChatAgentNotifier(this._agentId) : super(const ChatAgentState());

  final String _agentId;
  final _bridge = AgentRuntimeBridge();
  final _db = LocalDbBridge();
  StreamSubscription<AgentEvent>? _eventSub;

  Future<void> init() async {
    // 加载历史消息
    final rows = await _db.getMessages(_agentId, limit: 50);
    final messages = rows.reversed
        .map((r) => ChatMessage(
              id: r.id,
              role: r.role,
              content: r.content,
              status: r.status,
            ))
        .toList();

    final sessionId = 'session_$_agentId';
    state = state.copyWith(
      sessionId: sessionId,
      messages: messages,
      agentName: 'Agent',
    );

    // 监听 Native 事件
    _eventSub = _bridge.eventStream
        .where((e) => e.sessionId == sessionId)
        .listen(_handleEvent);
  }

  void _handleEvent(AgentEvent event) {
    switch (event) {
      // 使用 `state: agentState` 把字段重命名，避免遮蔽 StateNotifier.state
      case SessionStateEvent(state: final agentState):
        state = state.copyWith(sessionState: agentState);

      case SttEvent(:final kind, :final text):
        if (kind == SttEventKind.partialResult) {
          state = state.copyWith(sttPartial: text ?? '');
        } else if (kind == SttEventKind.finalResult) {
          state = state.copyWith(sttPartial: '');
          final msgs = List<ChatMessage>.from(state.messages)
            ..add(ChatMessage(
              id: event.requestId,
              role: 'user',
              content: text ?? '',
              status: 'done',
            ));
          state = state.copyWith(messages: msgs);
        }

      case LlmEvent(:final kind, :final requestId, :final textDelta):
        final msgs = List<ChatMessage>.from(state.messages);
        final idx = msgs.indexWhere((m) => m.id == requestId && m.role == 'assistant');
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
          if (idx != -1) msgs[idx].status = 'error';
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
    await _bridge.sendText(state.sessionId, requestId, text);
  }

  Future<void> setInputMode(String mode) async {
    state = state.copyWith(inputMode: mode);
    await _bridge.setInputMode(state.sessionId, mode);
  }

  Future<void> startListening() => _bridge.interrupt(state.sessionId);
  Future<void> stopListening() => _bridge.interrupt(state.sessionId);

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}
