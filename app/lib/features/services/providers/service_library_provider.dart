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

  Future<void> removeService(String id) async {
    await _db.deleteServiceConfig(id);
    await _load();
  }
}
