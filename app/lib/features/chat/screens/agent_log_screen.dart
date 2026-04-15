import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/chat_provider.dart';

class AgentLogScreen extends ConsumerWidget {
  const AgentLogScreen({super.key, required this.agentId});
  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(chatAgentProvider(agentId).select((s) => s.logs));
    final agentName = ref.watch(chatAgentProvider(agentId).select((s) => s.agentName));

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: Text('$agentName 日志', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, size: 20),
            tooltip: '复制全部日志',
            onPressed: () {
              if (logs.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('暂无日志')),
                );
                return;
              }
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已复制 ${logs.length} 条日志到剪贴板'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('暂无日志', style: TextStyle(color: Colors.white38, fontSize: 14)),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: logs.length,
              itemBuilder: (_, i) => _LogLine(log: logs[i]),
            ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.log});
  final String log;

  @override
  Widget build(BuildContext context) {
    // Format: [HH:mm:ss.mmm] LEVEL: message
    final isError = log.contains('ERROR:');
    final isEvent = log.contains('EVENT:');

    final Color color;
    if (isError) {
      color = const Color(0xFFEF4444);
    } else if (isEvent) {
      color = const Color(0xFF38BDF8);
    } else {
      color = const Color(0xFF10B981);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4, height: 4,
            margin: const EdgeInsets.only(top: 6, right: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Expanded(
            child: Text(
              log,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: isError ? color : Colors.white70,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
