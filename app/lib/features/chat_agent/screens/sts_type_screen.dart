import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:agents_server/agents_server.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/chat_agent_provider.dart';
import '../widgets/chat_screen_shared.dart';
import '../widgets/message_bubble.dart';
import '../widgets/multimodal_input_bar.dart';

/// STS-Chat type screen: end-to-end speech-to-speech chat.
/// Robot avatar (purple gradient), connection chip, service chip STS only,
/// single language selector at top, standard chat bubbles with avatars.
/// Manual connect, call mode by default.
class StsTypeScreen extends ConsumerStatefulWidget {
  const StsTypeScreen({super.key, required this.agentId});
  final String agentId;

  @override
  ConsumerState<StsTypeScreen> createState() => _StsTypeScreenState();
}

class _StsTypeScreenState extends ConsumerState<StsTypeScreen> {
  final _uuid = const Uuid();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initWithPermission());
  }

  Future<void> _initWithPermission() async {
    await Permission.microphone.request();
    if (!mounted) return;

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

    // Auto-scroll when messages change
    ref.listen(
        chatAgentProvider(widget.agentId).select((s) => s.messages.length),
        (_, __) => _scrollToBottom());

    final isPlaying = state.sessionState == AgentSessionState.playing ||
        state.sessionState == AgentSessionState.tts;
    final isCall = state.inputMode == 'call';

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppTheme.text2),
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
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.text1),
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
          // Connection chip
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ChatConnectionChip(
              connectionState: state.connectionState,
              onTap: _toggleConnection,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: AppTheme.text2),
            onPressed: () => showAgentMenu(context, ref: ref, agentId: widget.agentId),
          ),
        ],
      ),
      body: Column(
        children: [
          // Service chip — STS only
          if (state.llmServiceName.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  ChatServiceChip(
                    label: state.llmServiceName,
                    dot: const Color(0xFF7C3AED),
                    bg: const Color(0xFFF5F3FF),
                    color: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ),

          // Language selector
          SingleLanguageBar(
            currentLang: state.srcLang,
            supportedLangs: state.srcLangs,
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

          // Message list
          Expanded(
            child: ListView.builder(
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

          // TTS strip
          if (isCall && isPlaying)
            TtsPlayingStrip(isTranslateMode: false),

          // Input bar
          MultimodalInputBar(
            inputMode: state.inputMode,
            partialText: state.sttPartial,
            sessionState: state.sessionState,
            isEndToEnd: true,
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
      ),
    );
  }
}
