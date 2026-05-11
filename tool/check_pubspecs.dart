import 'dart:io';
import 'package:pubspec_parse/pubspec_parse.dart';

void main() {
  final files = Directory('app/local_plugins')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('/pubspec.yaml') &&
          !f.path.contains('/build/') &&
          !f.path.contains('/.dart_tool/') &&
          !f.path.contains('/example/'))
      .toList();
  for (final f in files) {
    try {
      Pubspec.parse(f.readAsStringSync(), sourceUrl: f.uri);
    } catch (e) {
      print('FAIL: ${f.path}');
      print('  ${e.toString().split("\n").take(6).join("\n  ")}');
      print('');
    }
  }
}
