/// md 文库（真源）：一条笔记 = frontmatter + markdown 正文。
library;

/// 一条 md 笔记。
class VaultNote {
  final String id;
  final Map<String, String> frontmatter;
  final String body;
  const VaultNote({
    required this.id,
    required this.frontmatter,
    required this.body,
  });
}

/// md 文库端口（真源）。默认内存实现；文件系统实现见 file_system_vault.dart。
abstract interface class NoteVault {
  Future<void> put(VaultNote note);
  Future<VaultNote?> read(String id);
  Future<List<String>> listIds();
  Future<bool> exists(String id);
  Future<void> delete(String id);
}

/// 极简 frontmatter 序列化：`---\nkey: value\n---\n<body>`（值为单行字符串）。
String serializeNote(VaultNote note) {
  final b = StringBuffer();
  b.writeln('---');
  note.frontmatter.forEach((k, v) {
    b.writeln('$k: ${v.replaceAll('\n', ' ')}');
  });
  b.writeln('---');
  b.write(note.body);
  return b.toString();
}

VaultNote parseNote(String id, String raw) {
  final fm = <String, String>{};
  var body = raw;
  if (raw.startsWith('---')) {
    final end = raw.indexOf('\n---', 3);
    if (end != -1) {
      for (final line in raw.substring(3, end).trim().split('\n')) {
        final i = line.indexOf(':');
        if (i > 0) {
          fm[line.substring(0, i).trim()] = line.substring(i + 1).trim();
        }
      }
      final nl = raw.indexOf('\n', end + 1);
      body = nl == -1 ? '' : raw.substring(nl + 1);
    }
  }
  return VaultNote(id: id, frontmatter: fm, body: body);
}

/// 内存 md 文库（测试/回退/web）。
class InMemoryVault implements NoteVault {
  final Map<String, String> _files = {};

  @override
  Future<void> put(VaultNote note) async => _files[note.id] = serializeNote(note);

  @override
  Future<VaultNote?> read(String id) async {
    final raw = _files[id];
    return raw == null ? null : parseNote(id, raw);
  }

  @override
  Future<List<String>> listIds() async => _files.keys.toList()..sort();

  @override
  Future<bool> exists(String id) async => _files.containsKey(id);

  @override
  Future<void> delete(String id) async => _files.remove(id);
}
