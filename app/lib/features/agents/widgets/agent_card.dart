import 'package:flutter/material.dart';
import 'package:local_db/local_db.dart';
import '../../../shared/themes/app_theme.dart';

class AgentCard extends StatelessWidget {
  const AgentCard({super.key, required this.agent, required this.onTap});
  final AgentDto agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (Color borderColor, Color badgeBg, Color badgeColor, String badgeLabel, String typeLabel) =
        switch (agent.type) {
      'chat'      => (AppTheme.primary,              AppTheme.primaryLight,      AppTheme.primaryDark,       '💬 聊天',     '聊天 Agent'),
      'translate' => (AppTheme.translateAccent,      const Color(0xFFE0F2FE),    const Color(0xFF0369A1),    '🌐 翻译',     '翻译 Agent'),
      'sts'       => (const Color(0xFFF97316),       const Color(0xFFFFF7ED),    const Color(0xFF9A3412),    '🎙 端到端对话', '端到端语音'),
      _           => (const Color(0xFF10B981),       const Color(0xFFECFDF5),    const Color(0xFF065F46),    '🔄 端到端翻译', '端到端翻译'),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(agent.name,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.text1)),
                          const SizedBox(height: 2),
                          Text(typeLabel,
                              style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: badgeColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Service chips placeholder
                Wrap(
                  spacing: 5,
                  children: [
                    _ServiceChip(label: 'GPT-4o', color: const Color(0xFF7C3AED), bg: const Color(0xFFF5F3FF)),
                    _ServiceChip(label: 'Azure STT', color: const Color(0xFF92400E), bg: const Color(0xFFFEF3C7)),
                    _ServiceChip(label: '晓晓 TTS', color: const Color(0xFF065F46), bg: const Color(0xFFECFDF5)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 12, color: AppTheme.text2),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text('最近使用: 刚刚', style: TextStyle(fontSize: 11, color: AppTheme.text2)),
                    ),
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.center,
                      child: const Text('打开', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.label, required this.color, required this.bg});
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
