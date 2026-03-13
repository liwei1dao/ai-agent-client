import 'package:flutter/material.dart';
import 'package:local_db/local_db.dart';

class AgentCard extends StatelessWidget {
  const AgentCard({super.key, required this.agent, required this.onTap});

  final AgentDto agent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isChat = agent.type == 'chat';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(isChat ? Icons.chat_bubble_outline : Icons.translate),
        ),
        title: Text(agent.name),
        subtitle: Text(isChat ? 'Chat Agent' : 'Translate Agent'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
