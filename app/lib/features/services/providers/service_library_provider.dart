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
    state = await _db.getAllServiceConfigs();
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

  /// Parse import JSON and separate into conflicts and new services.
  /// Returns ({List<ImportItem> conflicts, List<ImportItem> newItems}).
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
      if (type == null || vendor == null || name == null || config == null) continue;
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
  /// [overwriteIds] contains existingIds of conflicting items the user chose to overwrite.
  Future<int> executeImport({
    required List<ImportItem> newItems,
    required List<ImportItem> conflicts,
    required Set<String> overwriteIds,
  }) async {
    int count = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Import all new items
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
    // Import conflicting items that user chose to overwrite
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
  final String? existingId; // non-null if conflicts with local service

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
