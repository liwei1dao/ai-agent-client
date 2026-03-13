import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/agent_list_provider.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_agent_modal.dart';

class AgentPanelScreen extends ConsumerWidget {
  const AgentPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Agents')),
      body: agents.isEmpty
          ? const Center(child: Text('还没有 Agent，点击 + 创建'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: agents.length,
              itemBuilder: (context, i) => AgentCard(
                agent: agents[i],
                onTap: () {
                  final route = agents[i].type == 'chat'
                      ? '/agent/${agents[i].id}/chat'
                      : '/agent/${agents[i].id}/translate';
                  context.push(route);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => const AddAgentModal(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
