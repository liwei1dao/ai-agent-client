import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import 'package:uuid/uuid.dart';

final agentListProvider =
    StateNotifierProvider<AgentListNotifier, List<AgentDto>>((ref) {
  return AgentListNotifier();
});

class AgentListNotifier extends StateNotifier<List<AgentDto>> {
  AgentListNotifier() : super([]) {
    _load();
  }

  final _db = LocalDbBridge();
  final _uuid = const Uuid();

  Future<void> _load() async {
    state = await _db.getAllAgents();
  }

  Future<void> addAgent({
    required String name,
    required String type,
    required Map<String, dynamic> config,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dto = AgentDto(
      id: _uuid.v4(),
      name: name,
      type: type,
      configJson: jsonEncode(config),
      createdAt: now,
      updatedAt: now,
    );
    await _db.upsertAgent(dto);
    await _load();
  }

  Future<void> removeAgent(String id) async {
    await _db.deleteAgent(id);
    await _load();
  }
}
