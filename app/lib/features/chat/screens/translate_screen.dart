import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:agents_server/agents_server.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/agent_screen_provider.dart';
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
    // 翻译界面同样四种类型都用 mic（ast-translate 端到端 / translate 三段式）。
    // 统一进入界面就请求一次，避免被拒后底层 AudioFlinger 静默失败。
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('需要麦克风权限才能进行语音翻译'),
        action: status.isPermanentlyDenied
            ? SnackBarAction(label: '去设置', onPressed: openAppSettings)
            : null,
      ));
      return;
    }
    ref.read(agentScreenProvider(widget.agentId).notifier).init();
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

  /// 输入框上显示的方向 chip：只展示"当前正在输入"的那一种语言（短）。
  /// 点击 chip 在 src ↔ dst 之间切换。
  String _directionLabel(AgentScreenState s) {
    final activeLang =
        s.translateDirection == 'dst_to_src' ? s.dstLang : s.srcLang;
    return langName(activeLang);
  }

  Future<void> _toggleConnection() async {
    final notifier = ref.read(agentScreenProvider(widget.agentId).notifier);
    final state = ref.read(agentScreenProvider(widget.agentId));
    if (state.connectionState == ServiceConnectionState.connected) {
      notifier.disconnectService();
      return;
    }
    // 重连前再校一次权限——用户可能在系统设置里撤销过。
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('需要麦克风权限才能进行语音翻译'),
        action: status.isPermanentlyDenied
            ? SnackBarAction(label: '去设置', onPressed: openAppSettings)
            : null,
      ));
      return;
    }
    notifier.connectService();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentScreenProvider(widget.agentId));
    final isE2E = state.isEndToEnd;

    ref.listen(
        agentScreenProvider(widget.agentId).select((s) => s.messages.length),
        (_, __) => _scrollToBottom());

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
          // Service chips + 互译 toggle (toggle 仅三段式 translate +
          // STT 厂商支持语言识别时显示)
          Builder(builder: (_) {
            final showBidi = state.agentType == 'translate' &&
                state.sttSupportsLanguageDetection;
            final hasChip = state.llmServiceName.isNotEmpty ||
                state.sttServiceName.isNotEmpty ||
                state.ttsServiceName.isNotEmpty;
            if (!hasChip && !showBidi) return const SizedBox.shrink();
            return Container(
              color: colors.surface,
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
                  if (showBidi) ...[
                    const Spacer(),
                    const Icon(Icons.translate,
                        size: 13, color: AppTheme.text2),
                    const SizedBox(width: 3),
                    const Text('互译',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.text2,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Transform.scale(
                      scale: 0.7,
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        height: 20,
                        child: Switch(
                          value: state.bidirectional,
                          onChanged: (v) => ref
                              .read(agentScreenProvider(widget.agentId)
                                  .notifier)
                              .setBidirectional(v),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

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
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .setSrcLang(code),
            ),
            onDstTap: () => showLangPicker(
              context,
              isSource: false,
              currentLang: state.dstLang,
              supported: state.dstLangs,
              onSelect: (code) => ref
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .setDstLang(code),
            ),
            onSwap: () => ref
                .read(agentScreenProvider(widget.agentId).notifier)
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
                      // 三段式 translate / ast-translate：以"识别文本的语言编码"决定左右——
                      //   detectedLang == dstLang（目标语言）→ 右侧；
                      //   detectedLang == srcLang（源语言）→ 左侧。
                      // 与界面顶部"来源语言（左）→ 目标语言（右）"的方向标识一致。
                      // 互译关下 STT/文本路径会把 detectedLang 强制打成 srcLang，
                      // 自然全部落在左侧；互译开则按 STT 真实识别结果分左右。
                      selfLang: state.dstLang,
                    ),
                  ),
          ),

          // Input bar: only when connected (or non-E2E)
          if (!isE2E ||
              state.connectionState ==
                  ServiceConnectionState.connected) ...[
            MultimodalInputBar(
              inputMode: state.inputMode,
              partialText: state.sttPartial,
              sessionState: state.sessionState,
              isEndToEnd: isE2E,
              connectionState: state.connectionState,
              translateDirectionLabel: state.agentType == 'translate'
                  ? _directionLabel(state)
                  : null,
              onTranslateDirectionToggle: () => ref
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .toggleTranslateDirection(),
              onModeChanged: (mode) => ref
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .setInputMode(mode),
              onTextSubmit: (text) {
                final requestId = _uuid.v4();
                ref
                    .read(agentScreenProvider(widget.agentId).notifier)
                    .sendText(requestId, text);
                _scrollToBottom();
              },
              onVoiceStart: () => ref
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .startListening(),
              onVoiceEnd: () => ref
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .stopListening(),
              onVoiceCancel: () => ref
                  .read(agentScreenProvider(widget.agentId).notifier)
                  .cancelListening(),
            ),
          ],
        ],
      ),
    );
  }
}
