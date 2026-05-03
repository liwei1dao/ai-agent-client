import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/meeting.dart';
import '../models/meeting_detail.dart';
import '../models/template.dart';

/// Filesystem-backed storage for meeting metadata, details and templates.
///
/// Layout under `<appDocs>/meetings/`:
/// ```
/// meetings_index.json         # List<Meeting> light summaries
/// detail_<id>.json            # MeetingDetail (transcript / summary / mindmap)
/// audio_<id>.<ext>            # raw recording
/// templates.json              # custom MeetingTemplate list
/// ```
class MeetingStorage {
  static const _indexFileName = 'meetings_index.json';
  static const _templatesFileName = 'templates.json';

  Directory? _root;

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/meetings');
    if (!await root.exists()) await root.create(recursive: true);
    _root = root;
    return root;
  }

  Future<String> resolveAudioPath(String meetingId, {String ext = 'm4a'}) async {
    final root = await _ensureRoot();
    return '${root.path}/audio_$meetingId.$ext';
  }

  // ── Index ────────────────────────────────────────────────────────────────

  Future<List<Meeting>> readIndex() async {
    final root = await _ensureRoot();
    final f = File('${root.path}/$_indexFileName');
    if (!await f.exists()) return [];
    try {
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<dynamic, dynamic>>()
          .map((m) => Meeting.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeIndex(List<Meeting> meetings) async {
    final root = await _ensureRoot();
    final f = File('${root.path}/$_indexFileName');
    final json = meetings.map((m) => m.toJson()).toList();
    await f.writeAsString(jsonEncode(json));
  }

  // ── Detail ───────────────────────────────────────────────────────────────

  Future<MeetingDetail?> readDetail(String meetingId) async {
    final root = await _ensureRoot();
    final f = File('${root.path}/detail_$meetingId.json');
    if (!await f.exists()) return null;
    try {
      final raw = await f.readAsString();
      return MeetingDetail.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeDetail(MeetingDetail detail) async {
    final root = await _ensureRoot();
    final f = File('${root.path}/detail_${detail.meetingId}.json');
    await f.writeAsString(jsonEncode(detail.toJson()));
  }

  Future<void> deleteDetail(String meetingId) async {
    final root = await _ensureRoot();
    final f = File('${root.path}/detail_$meetingId.json');
    if (await f.exists()) await f.delete();
  }

  Future<void> deleteAudio(String audioPath) async {
    if (audioPath.isEmpty) return;
    final f = File(audioPath);
    if (await f.exists()) await f.delete();
  }

  // ── Templates ────────────────────────────────────────────────────────────

  Future<List<MeetingTemplate>> readTemplates() async {
    final root = await _ensureRoot();
    final f = File('${root.path}/$_templatesFileName');
    if (!await f.exists()) return [];
    try {
      final raw = await f.readAsString();
      final list = jsonDecode(raw) as List;
      return list
          .cast<Map<dynamic, dynamic>>()
          .map((m) => MeetingTemplate.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> writeTemplates(List<MeetingTemplate> tpls) async {
    final root = await _ensureRoot();
    final f = File('${root.path}/$_templatesFileName');
    await f.writeAsString(
        jsonEncode(tpls.map((t) => t.toJson()).toList()));
  }
}
