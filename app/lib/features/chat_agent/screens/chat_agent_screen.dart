import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../agents/providers/agent_list_provider.dart';
import 'chat_type_screen.dart';
import 'translate_type_screen.dart';
import 'sts_type_screen.dart';
import 'ast_type_screen.dart';

/// Dispatcher screen that routes to the appropriate type-specific screen
/// based on the agent's type field.
class ChatAgentScreen extends ConsumerWidget {
  const ChatAgentScreen({super.key, required this.agentId});
  final String agentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentListProvider);
    final agent = agents.where((a) => a.id == agentId).firstOrNull;
    if (agent == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    return switch (agent.type) {
      'chat' => ChatTypeScreen(agentId: agentId),
      'translate' => TranslateTypeScreen(agentId: agentId),
      'sts' => StsTypeScreen(agentId: agentId),
      'ast' => AstTypeScreen(agentId: agentId),
      _ => ChatTypeScreen(agentId: agentId),
    };
  }
}
