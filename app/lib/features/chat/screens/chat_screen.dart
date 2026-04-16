import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:agents_server/agents_server.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_screen_shared.dart';
import '../widgets/message_bubble.dart';
import '../widgets/multimodal_input_bar.dart';

/// Unified chat screen for both standard (chat) and end-to-end (sts-chat) agents.
/// Determines mode from agent type internally.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.agentId});
  final String agentId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _uuid = const Uuid();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAgent());
  }

  Future<void> _initAgent() async {
    // E2E agents need microphone permission
    final state = ref.read(chatAgentProvider(widget.agentId));
    if (state.isEndToEnd) {
      await Permission.microphone.request();
      if (!mounted) return;
    }
    ref.read(chatAgentProvider(widget.agentId).notifier).init();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleConnection() {
    final notifier = ref.read(chatAgentProvider(widget.agentId).notifier);
    final state = ref.read(chatAgentProvider(widget.agentId));
    if (state.connectionState == ServiceConnectionState.connected) {
      notifier.disconnectService();
    } else {
      notifier.connectService();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatAgentProvider(widget.agentId));
    final isE2E = state.isEndToEnd;

    ref.listen(
        chatAgentProvider(widget.agentId).select((s) => s.messages.length),
        (_, __) => _scrollToBottom());

    final isPlaying = state.sessionState == AgentSessionState.playing ||
        state.sessionState == AgentSessionState.tts;
    final isCall = state.inputMode == 'call';

    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new,
              size: 18, color: colors.text2),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF818CF8)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.agentName,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.text1),
                ),
                Text(
                  statusLabel(state.sessionState),
                  style: TextStyle(
                      fontSize: 11,
                      color: statusColor(state.sessionState),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        titleSpacing: 0,
        actions: [
          if (isE2E)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChatConnectionChip(
                connectionState: state.connectionState,
                onTap: _toggleConnection,
              ),
            ),
          IconButton(
            icon: Icon(Icons.more_horiz, color: colors.text2),
            onPressed: () =>
                showAgentMenu(context, ref: ref, agentId: widget.agentId),
          ),
        ],
      ),
      body: Column(
        children: [
          // Service chips
          if (state.llmServiceName.isNotEmpty ||
              state.sttServiceName.isNotEmpty ||
              state.ttsServiceName.isNotEmpty)
            Container(
              color: colors.surface,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  if (state.llmServiceName.isNotEmpty) ...[
                    ChatServiceChip(
                      label: state.llmServiceName,
                      dot: const Color(0xFF7C3AED),
                      bg: const Color(0xFFF5F3FF),
                      color: const Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (state.sttServiceName.isNotEmpty) ...[
                    ChatServiceChip(
                      label: state.sttServiceName,
                      dot: AppTheme.warning,
                      bg: const Color(0xFFFEF3C7),
                      color: const Color(0xFF92400E),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (state.ttsServiceName.isNotEmpty)
                    ChatServiceChip(
                      label: state.ttsServiceName,
                      dot: AppTheme.success,
                      bg: const Color(0xFFECFDF5),
                      color: const Color(0xFF065F46),
                    ),
                  if (isE2E) ...[
                    const Spacer(),
                    LanguageSwitchButton(
                      currentLang: state.srcLang,
                      onTap: () => showLangPicker(
                        context,
                        isSource: true,
                        currentLang: state.srcLang,
                        supported: state.srcLangs,
                        onSelect: (code) => ref
                            .read(chatAgentProvider(widget.agentId).notifier)
                            .setConversationLang(code),
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Center area: connect overlay (E2E disconnected) or message list
          Expanded(
            child: isE2E &&
                    state.connectionState !=
                        ServiceConnectionState.connected
                ? E2eConnectOverlay(
                    connectionState: state.connectionState,
                    onConnect: _toggleConnection,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    itemCount: state.messages.length,
                    itemBuilder: (_, i) => MessageBubble(
                      message: state.messages[i],
                      agentName: state.agentName,
                      isTranslateMode: false,
                      srcLang: state.srcLang,
                      dstLang: state.dstLang,
                    ),
                  ),
          ),

          // TTS strip + Input bar: only when connected (or non-E2E)
          if (!isE2E ||
              state.connectionState ==
                  ServiceConnectionState.connected) ...[
            if (isCall && isPlaying) TtsPlayingStrip(isTranslateMode: false),
            MultimodalInputBar(
              inputMode: state.inputMode,
              partialText: state.sttPartial,
              sessionState: state.sessionState,
              isEndToEnd: isE2E,
              connectionState: state.connectionState,
              onModeChanged: (mode) => ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .setInputMode(mode),
              onTextSubmit: (text) {
                final requestId = _uuid.v4();
                ref
                    .read(chatAgentProvider(widget.agentId).notifier)
                    .sendText(requestId, text);
                _scrollToBottom();
              },
              onVoiceStart: () => ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .startListening(),
              onVoiceEnd: () => ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .stopListening(),
              onVoiceCancel: () => ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .cancelListening(),
            ),
          ],
        ],
      ),
    );
  }
}
