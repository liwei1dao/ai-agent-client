import 'package:flutter/material.dart';
import 'package:local_db/local_db.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service});
  final ServiceConfigDto service;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: CircleAvatar(child: Text(_typeEmoji(service.type))),
        title: Text(service.name),
        subtitle: Text('${service.type.toUpperCase()} · ${service.vendor}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  String _typeEmoji(String type) => switch (type) {
        'stt' => '🎤',
        'tts' => '🔊',
        'llm' => '🤖',
        'sts' => '🔄',
        'translation' => '🌐',
        _ => '⚙️',
      };
}
