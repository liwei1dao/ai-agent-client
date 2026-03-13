import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:agent_runtime/agent_runtime.dart';
import '../providers/chat_agent_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/multimodal_input_bar.dart';

class ChatAgentScreen extends ConsumerStatefulWidget {
  const ChatAgentScreen({super.key, required this.agentId});
  final String agentId;

  @override
  ConsumerState<ChatAgentScreen> createState() => _ChatAgentScreenState();
}

class _ChatAgentScreenState extends ConsumerState<ChatAgentScreen> {
  final _uuid = const Uuid();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatAgentProvider(widget.agentId).notifier).init();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatAgentProvider(widget.agentId));
    return Scaffold(
      appBar: AppBar(
        title: Text(state.agentName),
        actions: [
          // Agent 状态指示
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StateChip(agentState: state.sessionState),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: state.messages.length,
              itemBuilder: (context, i) =>
                  MessageBubble(message: state.messages[i]),
            ),
          ),
          MultimodalInputBar(
            inputMode: state.inputMode,
            onModeChanged: (mode) => ref
                .read(chatAgentProvider(widget.agentId).notifier)
                .setInputMode(mode),
            onTextSubmit: (text) {
              // 文本模式：Flutter 生成 requestId
              final requestId = _uuid.v4();
              ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .sendText(requestId, text);
            },
            onVoiceStart: () => ref
                .read(chatAgentProvider(widget.agentId).notifier)
                .startListening(),
            onVoiceEnd: () => ref
                .read(chatAgentProvider(widget.agentId).notifier)
                .stopListening(),
          ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.agentState});
  final AgentSessionState agentState;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (agentState) {
      AgentSessionState.idle => ('待机', Colors.grey),
      AgentSessionState.listening => ('监听', Colors.green),
      AgentSessionState.stt => ('识别', Colors.blue),
      AgentSessionState.llm => ('思考', Colors.orange),
      AgentSessionState.tts => ('合成', Colors.purple),
      AgentSessionState.playing => ('播报', Colors.deepPurple),
      AgentSessionState.error => ('错误', Colors.red),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      padding: EdgeInsets.zero,
    );
  }
}
