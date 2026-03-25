import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:agents_server/agents_server.dart';
import '../../../shared/themes/app_theme.dart';
import '../../agents/widgets/add_agent_modal.dart';
import '../../agents/providers/agent_list_provider.dart';
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

  static const _supportedLangs = [
    ('zh', '中文'),
    ('en', 'English'),
    ('ja', '日本語'),
    ('ko', '한국어'),
    ('fr', 'Français'),
    ('de', 'Deutsch'),
    ('es', 'Español'),
    ('ru', 'Русский'),
    ('ar', 'العربية'),
    ('pt', 'Português'),
  ];

  void _showLangPicker(BuildContext context, {required bool isSource}) {
    final notifier = ref.read(chatAgentProvider(widget.agentId).notifier);
    final state = ref.read(chatAgentProvider(widget.agentId));
    final current = isSource ? state.srcLang : state.dstLang;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                isSource ? '源语言' : '目标语言',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.text1),
              ),
            ),
            const Divider(height: 1),
            ...[ for (final (code, name) in _supportedLangs)
              ListTile(
                dense: true,
                title: Text(name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: code == current ? FontWeight.w700 : FontWeight.w400,
                      color: code == current ? const Color(0xFF9A3412) : AppTheme.text1,
                    )),
                trailing: code == current
                    ? const Icon(Icons.check, size: 18, color: Color(0xFF9A3412))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  if (isSource) {
                    notifier.setSrcLang(code);
                  } else {
                    notifier.setDstLang(code);
                  }
                },
              ),
            ],
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final agents = ref.read(agentListProvider);
    final agent = agents.where((a) => a.id == widget.agentId).firstOrNull;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.borderColor,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 4),
            _MenuItem(
              icon: Icons.edit_outlined,
              label: '编辑 Agent',
              color: AppTheme.text1,
              onTap: () {
                Navigator.pop(context);
                if (agent != null) {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => AddAgentModal(agent: agent),
                  );
                }
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),
            _MenuItem(
              icon: Icons.delete_outline,
              label: '清除聊天记录',
              color: AppTheme.danger,
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dlgCtx) => AlertDialog(
                    title: const Text('清除聊天记录'),
                    content: const Text('确定要清除当前 Agent 的所有聊天记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dlgCtx, false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dlgCtx, true),
                        child: const Text('清除',
                            style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await ref
                      .read(chatAgentProvider(widget.agentId).notifier)
                      .clearHistory();
                }
              },
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatAgentProvider(widget.agentId));

    // Auto-scroll when messages change
    ref.listen(chatAgentProvider(widget.agentId).select((s) => s.messages.length),
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
                  _statusLabel(state.sessionState),
                  style: TextStyle(
                      fontSize: 11,
                      color: _statusColor(state.sessionState),
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
        titleSpacing: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz, color: AppTheme.text2),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Service chips / language bar ─────────────────────────────────
          if (state.agentType == 'ast' || state.agentType == 'translate')
            // AST / translate 翻译语言栏（可交互）
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  if (state.llmServiceName.isNotEmpty) ...[
                    _ServiceChip(
                      label: state.llmServiceName,
                      dot: const Color(0xFF9A3412),
                      bg: const Color(0xFFFFF7ED),
                      color: const Color(0xFF9A3412),
                    ),
                    const SizedBox(width: 10),
                  ],
                  _LangPill(
                    label: _langName(state.srcLang),
                    onTap: () => _showLangPicker(context, isSource: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: () => ref
                          .read(chatAgentProvider(widget.agentId).notifier)
                          .swapLanguages(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.swap_horiz, size: 16, color: Color(0xFF9A3412)),
                      ),
                    ),
                  ),
                  _LangPill(
                    label: _langName(state.dstLang),
                    onTap: () => _showLangPicker(context, isSource: false),
                  ),
                ],
              ),
            )
          else if (state.llmServiceName.isNotEmpty || state.sttServiceName.isNotEmpty || state.ttsServiceName.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  if (state.llmServiceName.isNotEmpty) ...[
                    _ServiceChip(
                      label: state.llmServiceName,
                      dot: const Color(0xFF7C3AED),
                      bg: const Color(0xFFF5F3FF),
                      color: const Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (state.sttServiceName.isNotEmpty) ...[
                    _ServiceChip(
                      label: state.sttServiceName,
                      dot: AppTheme.warning,
                      bg: const Color(0xFFFEF3C7),
                      color: const Color(0xFF92400E),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (state.ttsServiceName.isNotEmpty)
                    _ServiceChip(
                      label: state.ttsServiceName,
                      dot: AppTheme.success,
                      bg: const Color(0xFFECFDF5),
                      color: const Color(0xFF065F46),
                    ),
                ],
              ),
            ),
          const Divider(height: 1),

          // ── Message list ─────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              itemCount: state.messages.length,
              itemBuilder: (_, i) =>
                  MessageBubble(message: state.messages[i], agentName: state.agentName),
            ),
          ),

          // ── TTS strip (shown when AI is speaking in call mode) ───────────
          if (isCall && isPlaying)
            Container(
              color: const Color(0xFFF0FDF4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  _WaveIndicator(color: const Color(0xFF16A34A)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '晓晓正在朗读...',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16A34A)),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFFFA39E)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close,
                              size: 12, color: Color(0xFFCF1322)),
                          SizedBox(width: 3),
                          Text(
                            '打断',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFCF1322)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Input bar ────────────────────────────────────────────────────
          MultimodalInputBar(
            inputMode: state.inputMode,
            partialText: state.sttPartial,
            sessionState: state.sessionState,
            lockCallMode: state.agentType == 'sts',
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

  String _statusLabel(AgentSessionState s) => switch (s) {
        AgentSessionState.idle => '在线',
        AgentSessionState.listening => '监听中',
        AgentSessionState.stt => '识别中',
        AgentSessionState.llm => '思考中',
        AgentSessionState.tts => '合成中',
        AgentSessionState.playing => '朗读中',
        AgentSessionState.error => '出错',
      };

  Color _statusColor(AgentSessionState s) => switch (s) {
        AgentSessionState.idle => AppTheme.success,
        AgentSessionState.listening => AppTheme.success,
        AgentSessionState.stt => AppTheme.translateAccent,
        AgentSessionState.llm => AppTheme.warning,
        AgentSessionState.tts => AppTheme.primary,
        AgentSessionState.playing => AppTheme.primary,
        AgentSessionState.error => AppTheme.danger,
      };
}

// ── Local helpers ────────────────────────────────────────────────────────────

class _ServiceChip extends StatelessWidget {
  const _ServiceChip(
      {required this.label,
      required this.dot,
      required this.bg,
      required this.color});
  final String label;
  final Color dot, bg, color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      );
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color)),
        onTap: onTap,
      );
}

class _WaveIndicator extends StatelessWidget {
  const _WaveIndicator({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: List.generate(
          5,
          (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 3,
            height: [6.0, 10.0, 8.0, 12.0, 6.0][i],
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );
}

// ── Language helpers ─────────────────────────────────────────────────────────

String _langName(String code) => switch (code) {
      'zh' => '中文',
      'en' => 'English',
      'ja' => '日本語',
      'ko' => '한국어',
      'fr' => 'Français',
      'de' => 'Deutsch',
      'es' => 'Español',
      'ru' => 'Русский',
      'ar' => 'العربية',
      'pt' => 'Português',
      _ => code,
    };

class _LangPill extends StatelessWidget {
  const _LangPill({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF9A3412))),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                const Icon(Icons.expand_more, size: 14, color: Color(0xFF9A3412)),
              ],
            ],
          ),
        ),
      );
}

