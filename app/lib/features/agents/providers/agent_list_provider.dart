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

  Future<void> reload() => _load();

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

  Future<void> updateAgent({
    required String id,
    required String name,
    required String type,
    required Map<String, dynamic> config,
  }) async {
    final existing = state.firstWhere((a) => a.id == id);
    final dto = AgentDto(
      id: id,
      name: name,
      type: type,
      configJson: jsonEncode(config),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _db.upsertAgent(dto);
    await _load();
  }

  Future<void> removeAgent(String id) async {
    await _db.deleteAgent(id);
    await _load();
  }

  /// Export all local agents as JSON string.
  String exportAgentsJson() {
    final list = state.map((a) => {
      'name': a.name,
      'type': a.type,
      'config': jsonDecode(a.configJson),
    }).toList();
    return jsonEncode({'agents': list});
  }

  /// Parse import JSON and separate into conflicts and new agents.
  AgentImportParseResult parseImportJson(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = data['agents'] as List? ?? [];
    final conflicts = <AgentImportItem>[];
    final newItems = <AgentImportItem>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final name = m['name'] as String?;
      final type = m['type'] as String?;
      final config = m['config'] as Map<String, dynamic>?;
      if (name == null || type == null || config == null) continue;
      final existing = state.where((a) => a.name == name && a.type == type);
      final importItem = AgentImportItem(
        name: name,
        type: type,
        config: config,
        existingId: existing.isNotEmpty ? existing.first.id : null,
      );
      if (existing.isNotEmpty) {
        conflicts.add(importItem);
      } else {
        newItems.add(importItem);
      }
    }
    return AgentImportParseResult(conflicts: conflicts, newItems: newItems);
  }

  /// Execute import with conflict resolution.
  Future<int> executeImport({
    required List<AgentImportItem> newItems,
    required List<AgentImportItem> conflicts,
    required Set<String> overwriteIds,
  }) async {
    int count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in newItems) {
      final dto = AgentDto(
        id: _uuid.v4(),
        name: item.name,
        type: item.type,
        configJson: jsonEncode(item.config),
        createdAt: now,
        updatedAt: now,
      );
      await _db.upsertAgent(dto);
      count++;
    }
    for (final item in conflicts) {
      if (item.existingId != null && overwriteIds.contains(item.existingId)) {
        final existing = state.firstWhere((a) => a.id == item.existingId);
        final dto = AgentDto(
          id: item.existingId!,
          name: item.name,
          type: item.type,
          configJson: jsonEncode(item.config),
          createdAt: existing.createdAt,
          updatedAt: now,
        );
        await _db.upsertAgent(dto);
        count++;
      }
    }
    await _load();
    return count;
  }
}

class AgentImportItem {
  final String name;
  final String type;
  final Map<String, dynamic> config;
  final String? existingId;

  const AgentImportItem({
    required this.name,
    required this.type,
    required this.config,
    this.existingId,
  });
}

class AgentImportParseResult {
  final List<AgentImportItem> conflicts;
  final List<AgentImportItem> newItems;

  const AgentImportParseResult({required this.conflicts, required this.newItems});

  int get totalCount => conflicts.length + newItems.length;
  bool get hasConflicts => conflicts.isNotEmpty;
}
