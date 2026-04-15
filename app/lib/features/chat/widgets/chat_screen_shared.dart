import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agents_server/agents_server.dart';
import '../../../shared/themes/app_theme.dart';
import '../../agents/widgets/add_agent_modal.dart';
import '../../agents/providers/agent_list_provider.dart';
import '../providers/chat_provider.dart';
import '../screens/agent_log_screen.dart';

// ── Language helpers ──────────────────────────────────────────────────────────

const supportedLangs = [
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

String langName(String code) => switch (code) {
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

// ── Status helpers ───────────────────────────────────────────────────────────

String statusLabel(AgentSessionState s) => switch (s) {
      AgentSessionState.idle => '在线',
      AgentSessionState.listening => '监听中',
      AgentSessionState.stt => '识别中',
      AgentSessionState.llm => '思考中',
      AgentSessionState.tts => '合成中',
      AgentSessionState.playing => '朗读中',
      AgentSessionState.error => '出错',
    };

Color statusColor(AgentSessionState s) => switch (s) {
      AgentSessionState.idle => AppTheme.success,
      AgentSessionState.listening => AppTheme.success,
      AgentSessionState.stt => AppTheme.translateAccent,
      AgentSessionState.llm => AppTheme.warning,
      AgentSessionState.tts => AppTheme.primary,
      AgentSessionState.playing => AppTheme.primary,
      AgentSessionState.error => AppTheme.danger,
    };

// ── Service Chip ─────────────────────────────────────────────────────────────

class ChatServiceChip extends StatelessWidget {
  const ChatServiceChip({
    super.key,
    required this.label,
    required this.dot,
    required this.bg,
    required this.color,
  });
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

// ── Language Switch Button ───────────────────────────────────────────────────

class LanguageSwitchButton extends StatelessWidget {
  const LanguageSwitchButton({
    super.key,
    required this.currentLang,
    required this.onTap,
  });
  final String currentLang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 13, color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(
                langName(currentLang),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 14, color: AppTheme.primary),
            ],
          ),
        ),
      );
}

// ── Connection Chip ──────────────────────────────────────────────────────────

class ChatConnectionChip extends StatelessWidget {
  const ChatConnectionChip({
    super.key,
    required this.connectionState,
    this.onTap,
  });
  final ServiceConnectionState connectionState;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label, Color color, Color bg) =
        switch (connectionState) {
      ServiceConnectionState.connected => (
        Icons.link,
        '已连接',
        const Color(0xFF065F46),
        const Color(0xFFECFDF5)
      ),
      ServiceConnectionState.connecting => (
        Icons.sync,
        '连接中',
        const Color(0xFF92400E),
        const Color(0xFFFEF3C7)
      ),
      ServiceConnectionState.error => (
        Icons.link_off,
        '连接失败',
        AppTheme.danger,
        const Color(0xFFFEE2E2)
      ),
      ServiceConnectionState.disconnected => (
        Icons.link_off,
        '未连接',
        AppTheme.text2,
        const Color(0xFFF3F4F6)
      ),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connectionState == ServiceConnectionState.connecting)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              )
            else
              Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ── E2E Connect Overlay ─────────────────────────────────────────────────────

class E2eConnectOverlay extends StatelessWidget {
  const E2eConnectOverlay({
    super.key,
    required this.connectionState,
    required this.onConnect,
  });
  final ServiceConnectionState connectionState;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final isConnecting =
        connectionState == ServiceConnectionState.connecting;
    final isError = connectionState == ServiceConnectionState.error;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon / progress
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: isError
                  ? null
                  : const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFF818CF8)]),
              color: isError ? const Color(0xFFFEE2E2) : null,
              shape: BoxShape.circle,
              boxShadow: isConnecting
                  ? null
                  : [
                      BoxShadow(
                        color: (isError ? AppTheme.danger : AppTheme.primary)
                            .withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: isConnecting
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3),
                  )
                : Icon(
                    isError ? Icons.error_outline : Icons.phone_outlined,
                    color: isError ? AppTheme.danger : Colors.white,
                    size: 36,
                  ),
          ),
          const SizedBox(height: 20),
          // Status text
          Text(
            isConnecting
                ? '正在连接服务...'
                : isError
                    ? '连接失败'
                    : '点击连接开始通话',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isError ? AppTheme.danger : AppTheme.text1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isConnecting
                ? '请稍候'
                : isError
                    ? '请检查网络后重试'
                    : '连接后即可实时语音对话',
            style: const TextStyle(fontSize: 13, color: AppTheme.text2),
          ),
          // Connect / Retry button
          if (!isConnecting) ...[
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onConnect,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppTheme.primary, Color(0xFF818CF8)]),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  isError ? '重新连接' : '连接服务',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Wave Indicator ───────────────────────────────────────────────────────────

class ChatWaveIndicator extends StatelessWidget {
  const ChatWaveIndicator({super.key, required this.color});
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

// ── Menu Item ────────────────────────────────────────────────────────────────

class ChatMenuItem extends StatelessWidget {
  const ChatMenuItem({
    super.key,
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

// ── Translate Language Bar ────────────────────────────────────────────────────

class TranslateLanguageBar extends StatelessWidget {
  const TranslateLanguageBar({
    super.key,
    required this.srcLang,
    required this.dstLang,
    required this.srcLangs,
    required this.dstLangs,
    required this.onSrcTap,
    required this.onDstTap,
    required this.onSwap,
  });
  final String srcLang;
  final String dstLang;
  final List<String> srcLangs;
  final List<String> dstLangs;
  final VoidCallback onSrcTap;
  final VoidCallback onDstTap;
  final VoidCallback onSwap;

  String _supportedHint(List<String> codes) {
    return codes.map((c) => langName(c)).join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            // Source language
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onSrcTap,
                child: Column(
                  children: [
                    const Text('来源语言',
                        style: TextStyle(fontSize: 9, color: AppTheme.text2)),
                    const SizedBox(height: 2),
                    Text(
                      '${langName(srcLang)} \u25BE',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _supportedHint(srcLangs),
                      style: const TextStyle(
                        fontSize: 8,
                        color: AppTheme.text2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            // Swap button
            GestureDetector(
              onTap: onSwap,
              child: Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x4D0EA5E9),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child:
                    const Icon(Icons.swap_horiz, size: 15, color: Colors.white),
              ),
            ),
            // Target language
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDstTap,
                child: Column(
                  children: [
                    const Text('目标语言',
                        style: TextStyle(fontSize: 9, color: AppTheme.text2)),
                    const SizedBox(height: 2),
                    Text(
                      '${langName(dstLang)} \u25BE',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _supportedHint(dstLangs),
                      style: const TextStyle(
                        fontSize: 8,
                        color: AppTheme.text2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single Language Bar (for STS chat) ──────────────────────────────────────

class SingleLanguageBar extends StatelessWidget {
  const SingleLanguageBar({
    super.key,
    required this.currentLang,
    required this.supportedLangs,
    required this.onTap,
  });
  final String currentLang;
  final List<String> supportedLangs;
  final VoidCallback onTap;

  String _supportedHint(List<String> codes) {
    return codes.map((c) => langName(c)).join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              spreadRadius: 1,
            ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF818CF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.language, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('使用语言',
                        style: TextStyle(fontSize: 9, color: AppTheme.text2)),
                    const SizedBox(height: 1),
                    Text(
                      '${langName(currentLang)} \u25BE',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text1,
                      ),
                    ),
                  ],
                ),
              ),
              if (supportedLangs.length > 1)
                Flexible(
                  child: Text(
                    _supportedHint(supportedLangs),
                    style: const TextStyle(fontSize: 9, color: AppTheme.text2),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── TTS Playing Strip ────────────────────────────────────────────────────────

class TtsPlayingStrip extends StatelessWidget {
  const TtsPlayingStrip({
    super.key,
    required this.isTranslateMode,
    this.onInterrupt,
  });
  final bool isTranslateMode;
  final VoidCallback? onInterrupt;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF0FDF4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Row(
        children: [
          const ChatWaveIndicator(color: Color(0xFF16A34A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isTranslateMode ? '正在播报译文...' : '晓晓正在朗读...',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF16A34A)),
            ),
          ),
          GestureDetector(
            onTap: onInterrupt,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFA39E)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close, size: 12, color: Color(0xFFCF1322)),
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
    );
  }
}

// ── Language picker bottom sheet ──────────────────────────────────────────────

void showLangPicker(
  BuildContext context, {
  required bool isSource,
  required String currentLang,
  required List<String> supported,
  required ValueChanged<String> onSelect,
}) {
  final langs =
      supportedLangs.where((e) => supported.contains(e.$1)).toList();

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
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              isSource ? '来源语言' : '目标语言',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text1),
            ),
          ),
          const Divider(height: 1),
          ...[
            for (final (code, name) in langs)
              ListTile(
                dense: true,
                title: Text(name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: code == currentLang
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: code == currentLang
                          ? const Color(0xFF9A3412)
                          : AppTheme.text1,
                    )),
                trailing: code == currentLang
                    ? const Icon(Icons.check,
                        size: 18, color: Color(0xFF9A3412))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onSelect(code);
                },
              ),
          ],
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
        ],
      ),
    ),
  );
}

// ── Shared menu bottom sheet ─────────────────────────────────────────────────

void showAgentMenu(
  BuildContext context, {
  required WidgetRef ref,
  required String agentId,
}) {
  final agents = ref.read(agentListProvider);
  final agent = agents.where((a) => a.id == agentId).firstOrNull;

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
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.borderColor,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 4),
          ChatMenuItem(
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
          ChatMenuItem(
            icon: Icons.article_outlined,
            label: '查看日志',
            color: AppTheme.text1,
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AgentLogScreen(agentId: agentId),
              ));
            },
          ),
          const Divider(height: 1, indent: 20, endIndent: 20),
          ChatMenuItem(
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
              if (confirm == true) {
                await ref
                    .read(chatAgentProvider(agentId).notifier)
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
