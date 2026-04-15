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

/// Unified translate screen for both standard (translate) and end-to-end (ast-translate) agents.
/// Determines mode from agent type internally.
class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key, required this.agentId});
  final String agentId;

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> {
  final _uuid = const Uuid();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAgent());
  }

  Future<void> _initAgent() async {
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
                    colors: [AppTheme.translateAccent, Color(0xFF38BDF8)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.language,
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
          if (isE2E)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChatConnectionChip(
                connectionState: state.connectionState,
                onTap: _toggleConnection,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: AppTheme.text2),
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
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  if (state.llmServiceName.isNotEmpty) ...[
                    ChatServiceChip(
                      label: state.llmServiceName,
                      dot: const Color(0xFF9A3412),
                      bg: const Color(0xFFFFF7ED),
                      color: const Color(0xFF9A3412),
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
                ],
              ),
            ),

          // Language bar
          TranslateLanguageBar(
            srcLang: state.srcLang,
            dstLang: state.dstLang,
            srcLangs: state.srcLangs,
            dstLangs: state.dstLangs,
            onSrcTap: () => showLangPicker(
              context,
              isSource: true,
              currentLang: state.srcLang,
              supported: state.srcLangs,
              onSelect: (code) => ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .setSrcLang(code),
            ),
            onDstTap: () => showLangPicker(
              context,
              isSource: false,
              currentLang: state.dstLang,
              supported: state.dstLangs,
              onSelect: (code) => ref
                  .read(chatAgentProvider(widget.agentId).notifier)
                  .setDstLang(code),
            ),
            onSwap: () => ref
                .read(chatAgentProvider(widget.agentId).notifier)
                .swapLanguages(),
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
                      isTranslateMode: true,
                      srcLang: state.srcLang,
                      dstLang: state.dstLang,
                    ),
                  ),
          ),

          // TTS strip + Input bar: only when connected (or non-E2E)
          if (!isE2E ||
              state.connectionState ==
                  ServiceConnectionState.connected) ...[
            if (isCall && isPlaying) TtsPlayingStrip(isTranslateMode: true),
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
