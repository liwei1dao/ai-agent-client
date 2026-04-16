// AST Volcengine plugin — native-only on mobile (no Dart class) and a
// full Dart WebSocket implementation on web. The barrel therefore
// unconditionally exports the web file; mobile builds don't consume this
// barrel because the Android side is wired via platform channels.
export 'src/ast_volcengine_plugin_web.dart'
    if (dart.library.js_interop) 'src/ast_volcengine_plugin_web.dart';
