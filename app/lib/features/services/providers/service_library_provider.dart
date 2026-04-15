import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import 'package:uuid/uuid.dart';

final serviceLibraryProvider =
    StateNotifierProvider<ServiceLibraryNotifier, List<ServiceConfigDto>>((ref) {
  return ServiceLibraryNotifier();
});

class ServiceLibraryNotifier extends StateNotifier<List<ServiceConfigDto>> {
  ServiceLibraryNotifier() : super([]) {
    _load();
  }

  final _db = LocalDbBridge();
  final _uuid = const Uuid();

  Future<void> _load() async {
    await _migrateVoitransToPolychat();
    state = await _db.getAllServiceConfigs();
  }

  Future<void> reload() => _load();

  /// 旧版数据迁移：vendor='voitrans' → 'polychat'，Agent tag 'voitrans' → 'polychat'
  Future<void> _migrateVoitransToPolychat() async {
    // 1. 迁移 ServiceConfig
    final services = await _db.getAllServiceConfigs();
    for (final s in services) {
      if (s.vendor == 'voitrans') {
        await _db.upsertServiceConfig(ServiceConfigDto(
          id: s.id,
          type: s.type,
          vendor: 'polychat',
          name: s.name
              .replaceFirst('VoiTrans', 'PolyChat')
              .replaceFirst('voitrans', 'polychat'),
          configJson: s.configJson,
          createdAt: s.createdAt,
        ));
      }
    }

    // 2. 迁移 Agent tags
    final agents = await _db.getAllAgents();
    for (final a in agents) {
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        final tags = (cfg['tags'] as List?)?.cast<String>() ?? const [];
        if (tags.contains('voitrans')) {
          final newTags = tags.map((t) => t == 'voitrans' ? 'polychat' : t).toList();
          cfg['tags'] = newTags;
          await _db.upsertAgent(AgentDto(
            id: a.id,
            name: a.name,
            type: a.type,
            configJson: jsonEncode(cfg),
            createdAt: a.createdAt,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ));
        }
      } catch (_) {
        // ignore malformed agent configs
      }
    }
  }

  Future<void> addService({
    required String type,
    required String vendor,
    required String name,
    required Map<String, dynamic> config,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dto = ServiceConfigDto(
      id: _uuid.v4(),
      type: type,
      vendor: vendor,
      name: name,
      configJson: jsonEncode(config),
      createdAt: now,
    );
    await _db.upsertServiceConfig(dto);
    await _load();
  }

  Future<void> updateService({
    required String id,
    required String type,
    required String vendor,
    required String name,
    required Map<String, dynamic> config,
  }) async {
    final existing = state.firstWhere((s) => s.id == id);
    final dto = ServiceConfigDto(
      id: id,
      type: type,
      vendor: vendor,
      name: name,
      configJson: jsonEncode(config),
      createdAt: existing.createdAt,
    );
    await _db.upsertServiceConfig(dto);
    await _load();
  }

  Future<void> removeService(String id) async {
    await _db.deleteServiceConfig(id);
    await _load();
  }

  /// Export all local services as JSON string.
  String exportServicesJson() {
    final list = state.map((s) => {
      'type': s.type,
      'vendor': s.vendor,
      'name': s.name,
      'config': jsonDecode(s.configJson),
    }).toList();
    return jsonEncode({'services': list});
  }

  /// Parse import JSON and separate into conflicts and new services.
  ImportParseResult parseImportJson(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = data['services'] as List? ?? [];
    final conflicts = <ImportItem>[];
    final newItems = <ImportItem>[];
    for (final item in list) {
      final m = item as Map<String, dynamic>;
      final type = m['type'] as String?;
      final vendor = m['vendor'] as String?;
      final name = m['name'] as String?;
      final config = m['config'] as Map<String, dynamic>?;
      if (type == null || vendor == null || name == null || config == null) {
        continue;
      }
      final existing = state.where(
        (s) => s.type == type && s.vendor == vendor && s.name == name,
      );
      final importItem = ImportItem(
        type: type,
        vendor: vendor,
        name: name,
        config: config,
        existingId: existing.isNotEmpty ? existing.first.id : null,
      );
      if (existing.isNotEmpty) {
        conflicts.add(importItem);
      } else {
        newItems.add(importItem);
      }
    }
    return ImportParseResult(conflicts: conflicts, newItems: newItems);
  }

  /// Execute import with conflict resolution.
  Future<int> executeImport({
    required List<ImportItem> newItems,
    required List<ImportItem> conflicts,
    required Set<String> overwriteIds,
  }) async {
    int count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in newItems) {
      final dto = ServiceConfigDto(
        id: _uuid.v4(),
        type: item.type,
        vendor: item.vendor,
        name: item.name,
        configJson: jsonEncode(item.config),
        createdAt: now,
      );
      await _db.upsertServiceConfig(dto);
      count++;
    }
    for (final item in conflicts) {
      if (item.existingId != null && overwriteIds.contains(item.existingId)) {
        final existing = state.firstWhere((s) => s.id == item.existingId);
        final dto = ServiceConfigDto(
          id: item.existingId!,
          type: item.type,
          vendor: item.vendor,
          name: item.name,
          configJson: jsonEncode(item.config),
          createdAt: existing.createdAt,
        );
        await _db.upsertServiceConfig(dto);
        count++;
      }
    }
    await _load();
    return count;
  }
}

class ImportItem {
  final String type;
  final String vendor;
  final String name;
  final Map<String, dynamic> config;
  final String? existingId;

  const ImportItem({
    required this.type,
    required this.vendor,
    required this.name,
    required this.config,
    this.existingId,
  });
}

class ImportParseResult {
  final List<ImportItem> conflicts;
  final List<ImportItem> newItems;

  const ImportParseResult({required this.conflicts, required this.newItems});

  int get totalCount => conflicts.length + newItems.length;
  bool get hasConflicts => conflicts.isNotEmpty;
}
