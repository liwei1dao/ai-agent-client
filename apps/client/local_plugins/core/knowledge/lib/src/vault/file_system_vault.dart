/// 文件系统 md 文库：每条笔记一份 `<id>.md`，真源落盘（移动/桌面端）。
library;

import 'dart:io';

import 'note_vault.dart';

class FileSystemVault implements NoteVault {
  final Directory root;
  FileSystemVault(String path) : root = Directory(path);

  Future<void> _ensure() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
  }

  File _file(String id) => File('${root.path}${Platform.pathSeparator}$id.md');

  @override
  Future<void> put(VaultNote note) async {
    await _ensure();
    await _file(note.id).writeAsString(serializeNote(note));
  }

  @override
  Future<VaultNote?> read(String id) async {
    final f = _file(id);
    if (!await f.exists()) return null;
    return parseNote(id, await f.readAsString());
  }

  @override
  Future<List<String>> listIds() async {
    await _ensure();
    final ids = <String>[];
    await for (final e in root.list()) {
      if (e is File && e.path.endsWith('.md')) {
        final name = e.uri.pathSegments.last;
        ids.add(name.substring(0, name.length - 3));
      }
    }
    ids.sort();
    return ids;
  }

  @override
  Future<bool> exists(String id) => _file(id).exists();

  @override
  Future<void> delete(String id) async {
    final f = _file(id);
    if (await f.exists()) await f.delete();
  }
}
