import 'dart:async';
import 'dart:io';

import '../models/meeting.dart';
import '../models/meeting_detail.dart';
import '../models/template.dart';
import 'meeting_storage.dart';

/// CRUD facade over [MeetingStorage]. Holds an in-memory cache of the index so
/// list updates are O(1) and providers can subscribe to a broadcast stream.
class MeetingRepository {
  MeetingRepository(this._storage);

  final MeetingStorage _storage;

  List<Meeting>? _cache;
  final _changes = StreamController<List<Meeting>>.broadcast();

  Stream<List<Meeting>> get changes => _changes.stream;

  Future<List<Meeting>> list({bool forceReload = false}) async {
    if (_cache != null && !forceReload) return _cache!;
    final loaded = await _storage.readIndex();
    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _cache = loaded;
    return loaded;
  }

  Future<Meeting?> getById(String id) async {
    final list = await this.list();
    for (final m in list) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> upsert(Meeting m) async {
    final list = await this.list();
    final i = list.indexWhere((e) => e.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.insert(0, m);
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await _storage.writeIndex(list);
    _emit();
  }

  Future<void> delete(String id) async {
    final list = await this.list();
    Meeting? removed;
    list.removeWhere((m) {
      if (m.id == id) {
        removed = m;
        return true;
      }
      return false;
    });
    await _storage.writeIndex(list);
    if (removed != null) {
      await _storage.deleteDetail(id);
      await _storage.deleteAudio(removed!.audioPath);
    }
    _emit();
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    final ks = ids.toSet();
    final list = await this.list();
    final removed = <Meeting>[];
    list.removeWhere((m) {
      if (ks.contains(m.id)) {
        removed.add(m);
        return true;
      }
      return false;
    });
    await _storage.writeIndex(list);
    for (final m in removed) {
      await _storage.deleteDetail(m.id);
      await _storage.deleteAudio(m.audioPath);
    }
    _emit();
  }

  Future<void> rename(String id, String title) async {
    final m = await getById(id);
    if (m == null) return;
    await upsert(m.copyWith(title: title));
  }

  Future<void> toggleMark(String id) async {
    final m = await getById(id);
    if (m == null) return;
    await upsert(m.copyWith(marked: !m.marked));
  }

  // ── Details ──────────────────────────────────────────────────────────────

  Future<MeetingDetail> readDetail(String id) async {
    final loaded = await _storage.readDetail(id);
    return loaded ?? MeetingDetail(meetingId: id);
  }

  Future<void> writeDetail(MeetingDetail d) => _storage.writeDetail(d);

  // ── Templates ────────────────────────────────────────────────────────────

  Future<List<MeetingTemplate>> listTemplates() async {
    final custom = await _storage.readTemplates();
    return [...kBuiltInTemplates, ...custom];
  }

  Future<void> upsertTemplate(MeetingTemplate t) async {
    if (t.builtin) return;
    final custom = await _storage.readTemplates();
    final i = custom.indexWhere((e) => e.id == t.id);
    if (i >= 0) {
      custom[i] = t;
    } else {
      custom.add(t);
    }
    await _storage.writeTemplates(custom);
  }

  Future<void> deleteTemplate(String id) async {
    final custom = await _storage.readTemplates();
    custom.removeWhere((e) => e.id == id);
    await _storage.writeTemplates(custom);
  }

  // ── Util ─────────────────────────────────────────────────────────────────

  Future<String> resolveAudioPath(String id, {String ext = 'm4a'}) =>
      _storage.resolveAudioPath(id, ext: ext);

  Future<int> audioFileSize(String path) async {
    if (path.isEmpty) return 0;
    final f = File(path);
    if (!await f.exists()) return 0;
    return f.length();
  }

  void _emit() {
    if (_cache != null) _changes.add(List.unmodifiable(_cache!));
  }

  void dispose() {
    _changes.close();
  }
}
