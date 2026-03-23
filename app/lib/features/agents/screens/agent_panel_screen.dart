import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/agent_list_provider.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_agent_modal.dart';

class AgentPanelScreen extends ConsumerWidget {
  const AgentPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Agents', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(
              '已配置 ${agents.length} 个 Agent',
              style: const TextStyle(fontSize: 11, color: AppTheme.text2, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            onPressed: () => _showAddAgent(context),
          ),
        ],
      ),
      body: agents.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined, size: 64, color: AppTheme.text2.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  const Text('还没有 Agent', style: TextStyle(color: AppTheme.text2, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('点击右上角 + 创建第一个', style: TextStyle(color: AppTheme.text2, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              itemCount: agents.length,
              itemBuilder: (context, i) => AgentCard(
                agent: agents[i],
                onTap: () {
                  context.push('/agent/${agents[i].id}/chat');
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAgent(context),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddAgent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddAgentModal(),
    );
  }
}
