import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Flutter web plugin registrar. The AST Volcengine plugin doesn't use
/// platform channels on web — the Dart class `AstVolcenginePluginWeb` is
/// instantiated directly by the service manager. We keep this class so the
/// `flutter: plugin: platforms: web:` declaration in `pubspec.yaml` resolves.
class AstVolcengineWeb {
  static void registerWith(Registrar registrar) {}
}
