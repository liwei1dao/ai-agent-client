// 批量把 local_plugins/** 下 25 个 SDK 包改造成可发布形态：
// 1) publish_to: none -> publish_to: http://localhost:4000
// 2) 内部 `path: ../...` 依赖 -> 版本号引用（默认 ^0.1.0）
// 3) 缺失的 LICENSE / README.md / CHANGELOG.md 补齐
//
// 不影响日常开发——melos bootstrap 会写 pubspec_overrides.yaml
// 用 path: 把这些版本号引用本地化。
//
// 用法：dart run tool/sdk_publish_prepare.dart [--dry-run]
//
// 仅作用于 local_plugins/** 下的子包，不会改 app/ 自己。

import 'dart:io';

const sdkRoot = 'app/local_plugins';
const publishUrl = 'http://localhost:4000';
const defaultVersion = '0.1.0';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final pubspecs = Directory(sdkRoot)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('/pubspec.yaml') &&
          !f.path.contains('/build/') &&
          !f.path.contains('/.dart_tool/') &&
          !f.path.contains('/example/') &&
          !f.path.contains('/test/'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  print('found ${pubspecs.length} pubspec.yaml files\n');

  // 收集所有 SDK 包名，用于判断哪些 path: 是内部包
  final sdkNames = <String>{};
  for (final p in pubspecs) {
    final name = _readScalar(p.readAsStringSync(), 'name');
    if (name != null) sdkNames.add(name);
  }
  print('sdk packages: ${sdkNames.length}');

  for (final p in pubspecs) {
    _process(p, sdkNames, dryRun: dryRun);
  }

  print('\n${dryRun ? "DRY-RUN " : ""}done.');
}

void _process(File pubspec, Set<String> sdkNames, {required bool dryRun}) {
  final pkgDir = pubspec.parent;
  final original = pubspec.readAsStringSync();
  var modified = original;

  // 1) publish_to: none -> 本地 unpub URL
  modified = modified.replaceAllMapped(
    RegExp(r'^publish_to:\s*none\s*$', multiLine: true),
    (_) => 'publish_to: $publishUrl',
  );

  // 1.5) 给声明了 flutter.plugin.platforms 的包补上 flutter SDK 约束
  // 否则 dart pub publish 会按 1.9.x 旧版校验，拒绝带 plugin.platforms 的 pubspec
  if (modified.contains(RegExp(r'^\s+plugin:', multiLine: true)) &&
      !modified.contains(RegExp('flutter:\\s*[\'"\\>]', multiLine: true))) {
    modified = modified.replaceFirstMapped(
      RegExp(r'^(\s+sdk:\s*[^\n]+)\n', multiLine: true),
      (m) => '${m[1]}\n  flutter: ">=3.3.0"\n',
    );
  }

  // 2) path 依赖 -> 版本号引用
  // 匹配形如:
  //   ai_plugin_interface:
  //     path: ../../core/ai_plugin_interface
  // 替换为:
  //   ai_plugin_interface: ^0.1.0
  final pathDepRe = RegExp(
    r'^(\s{2,4})([a-z_][a-z0-9_]*):\s*\n\s+path:\s*([^\n]+)\n',
    multiLine: true,
  );
  modified = modified.replaceAllMapped(pathDepRe, (m) {
    final indent = m[1]!;
    final depName = m[2]!;
    if (sdkNames.contains(depName)) {
      return '$indent$depName: ^$defaultVersion\n';
    }
    return m[0]!; // 非 SDK 内部包（不应该出现，但保险）
  });

  // 写回
  if (modified != original) {
    print('  pubspec  ${pubspec.path}');
    if (!dryRun) pubspec.writeAsStringSync(modified);
  }

  // 3) 补缺失的 LICENSE / README.md / CHANGELOG.md
  final pkgName = _readScalar(modified, 'name') ?? pkgDir.uri.pathSegments.last;
  _ensure(File('${pkgDir.path}/LICENSE'), _licenseText, dryRun: dryRun);
  _ensure(
    File('${pkgDir.path}/README.md'),
    '# $pkgName\n\nPart of the AI Agent SDK. See `local_plugins/CLAUDE.md` for architecture and constraints.\n',
    dryRun: dryRun,
  );
  _ensure(
    File('${pkgDir.path}/CHANGELOG.md'),
    '## $defaultVersion\n\n- Initial private release.\n',
    dryRun: dryRun,
  );
}

void _ensure(File f, String content, {required bool dryRun}) {
  if (f.existsSync()) return;
  print('  create   ${f.path}');
  if (!dryRun) f.writeAsStringSync(content);
}

String? _readScalar(String yaml, String key) {
  final m = RegExp('^$key:\\s*(.+?)\\s*\$', multiLine: true).firstMatch(yaml);
  return m?.group(1);
}

const _licenseText = '''
Copyright (c) 2026 liwei1dao. All rights reserved.

This source code is proprietary and confidential. Unauthorized copying,
distribution, modification, or use of this code, in whole or in part,
is strictly prohibited without prior written consent of the copyright
holder.
''';
