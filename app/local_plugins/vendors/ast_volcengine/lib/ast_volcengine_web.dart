import 'package:flutter_web_plugins/flutter_web_plugins.dart';

// web 专属导出：barrel 的 default 分支已改为桌面纯 Dart 文件（AstVolcengineDesktop），
// 故 web 侧工厂（web_service_factory / service_manager_bridge_web）改从这里取
// `AstVolcenginePluginWeb`，避免经 barrel 在非 web 解析时拿不到该类。
export 'src/ast_volcengine_plugin_web.dart';

/// Flutter web plugin registrar. The AST Volcengine plugin doesn't use
/// platform channels on web — the Dart class `AstVolcenginePluginWeb` is
/// instantiated directly by the service manager. We keep this class so the
/// `flutter: plugin: platforms: web:` declaration in `pubspec.yaml` resolves.
class AstVolcengineWeb {
  static void registerWith(Registrar registrar) {}
}
