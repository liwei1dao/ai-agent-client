import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/app_theme.dart';

/// Renders a native service request as a curl-style command block for the
/// debug log, so the tester can see exactly which endpoint + parameters a
/// service is started with. [endpoint] is a readable label for the native
/// MethodChannel call (not a real URL — the transport is a MethodChannel,
/// not HTTP); [args] are scalar top-level arguments rendered as `-d k=v`;
/// [bodyJson] is the effective service config sent as the request body.
///
/// Body keys are colon-aligned for readability; sensitive values (apiKey /
/// token / secret / password) are partially masked — the copyable debug log
/// must never leak full credentials. Every line is prefixed with `·` so
/// [TestLogPanel] renders the block as dimmed "detail" rows.
List<String> describeServiceRequest({
  required String endpoint,
  Map<String, String> args = const {},
  required String bodyJson,
}) {
  Map<String, dynamic>? body;
  try {
    final decoded = jsonDecode(bodyJson);
    if (decoded is Map<String, dynamic>) body = decoded;
  } catch (_) {
    // Unparseable → emitted below as a raw single-line -d payload.
  }

  // Each clause is one `-d ...` shell argument; the JSON body clause spans
  // several physical lines (newlines inside single quotes are literal).
  final clauses = <List<String>>[];
  for (final e in args.entries) {
    clauses.add(["-d ${e.key}='${e.value}'"]);
  }
  if (body != null && body.isNotEmpty) {
    final keys = body.keys.toList()..sort();
    final width = keys.fold<int>(0, (m, k) => k.length > m ? k.length : m);
    final block = <String>["-d '{"];
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final pad = ' ' * (width - k.length);
      final comma = i == keys.length - 1 ? '' : ',';
      block.add('  "$k":$pad ${_maskedJsonValue(k, body[k])}$comma');
    }
    block.add("}'");
    clauses.add(block);
  } else if (bodyJson.trim().isNotEmpty) {
    clauses.add(["-d '${bodyJson.trim()}'"]);
  }

  final lines = <String>[
    "· \$ curl -X POST '$endpoint'${clauses.isEmpty ? '' : ' \\'}",
  ];
  for (var c = 0; c < clauses.length; c++) {
    final clause = clauses[c];
    final isLastClause = c == clauses.length - 1;
    for (var l = 0; l < clause.length; l++) {
      // The continuation backslash sits only on the last physical line of a
      // clause — never inside the quoted JSON body.
      final backslash = (l == clause.length - 1 && !isLastClause) ? ' \\' : '';
      lines.add('·     ${clause[l]}$backslash');
    }
  }
  return lines;
}

/// Mask + JSON-encode a single config value for display inside a request
/// body. Booleans / numbers stay unquoted; strings are JSON-quoted, and
/// credential-like values (apiKey / token / secret / password) are masked.
String _maskedJsonValue(String key, Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  if (value is Map || value is List) {
    final s = jsonEncode(value);
    return s.length > 80 ? '"${s.substring(0, 78)}…"' : s;
  }
  final v = value.toString();
  final lower = key.toLowerCase();
  final sensitive = lower.contains('key') ||
      lower.contains('token') ||
      lower.contains('secret') ||
      lower.contains('password');
  if (sensitive && v.length > 8) {
    return '"${v.substring(0, 4)}***${v.substring(v.length - 4)}"';
  }
  if (sensitive && v.isNotEmpty) return '"***"';
  return jsonEncode(v);
}

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
    final isOk = log.contains('✓');
    final isOut = log.contains('→');
    final isIn = log.contains('←');
    final isDetail = log.contains('·');

    final Color dotColor;
    if (isError) {
      dotColor = AppTheme.danger;
    } else if (isOk) {
      dotColor = const Color(0xFF22C55E);
    } else if (isOut) {
      dotColor = const Color(0xFFFACC15);
    } else if (isIn) {
      dotColor = const Color(0xFF38BDF8);
    } else if (isDetail) {
      dotColor = const Color(0xFF64748B);
    } else {
      dotColor = const Color(0xFF22C55E);
    }

    final Color textColor;
    if (isError) {
      textColor = AppTheme.danger;
    } else if (isDetail && !isOk) {
      textColor = const Color(0xFF94A3B8);
    } else {
      textColor = const Color(0xFFCBD5E1);
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
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
