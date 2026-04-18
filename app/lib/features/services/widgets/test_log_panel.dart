import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/app_theme.dart';

/// Shared debug log panel for STS/AST test sessions. Styled to match
/// [AgentLogScreen] — dark monospace background, colored dot markers,
/// collapsible header with clear/copy actions.
class TestLogPanel extends StatelessWidget {
  const TestLogPanel({
    super.key,
    required this.logs,
    required this.expanded,
    required this.onToggle,
    required this.onClear,
  });

  final List<String> logs;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 4),
                Text(
                  '调试日志 (${logs.length})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const Spacer(),
                if (expanded && logs.isNotEmpty)
                  _HeaderAction(
                    icon: Icons.copy_all,
                    label: '复制',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: logs.join('\n')),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已复制 ${logs.length} 条日志'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                if (expanded && logs.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  _HeaderAction(
                    icon: Icons.clear_all,
                    label: '清空',
                    onTap: onClear,
                  ),
                ],
              ]),
            ),
          ),
          if (expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: logs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        '暂无日志',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    )
                  : Scrollbar(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        shrinkWrap: true,
                        reverse: true,
                        itemCount: logs.length,
                        itemBuilder: (_, i) => _LogLine(
                          log: logs[logs.length - 1 - i],
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.log});
  final String log;

  @override
  Widget build(BuildContext context) {
    final isError =
        log.contains('‼') || log.contains('Error') || log.contains(' err=');
    final isOut = log.contains('→');
    final isIn = log.contains('←');

    final Color dotColor;
    if (isError) {
      dotColor = AppTheme.danger;
    } else if (isOut) {
      dotColor = const Color(0xFFFACC15);
    } else if (isIn) {
      dotColor = const Color(0xFF38BDF8);
    } else {
      dotColor = const Color(0xFF22C55E);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 6, right: 6),
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              log,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
                color: isError ? AppTheme.danger : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
