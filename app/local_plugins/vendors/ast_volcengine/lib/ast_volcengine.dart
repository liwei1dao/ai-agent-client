// AST Volcengine plugin —— 三平台分支：
// - **web**（`dart.library.js_interop`）：`AstVolcenginePluginWeb`（package:web + WebAudio）。
// - **桌面 / 移动（default = `dart.library.io`）**：`AstVolcengineDesktop`（纯 Dart 协议 +
//   record 采集 + flutter_pcm_sound 播放）。移动端原生侧另走 platform channel，
//   不消费此 Dart 类；但 default 分支必须是纯 Dart 文件，否则桌面/移动编译会拉进
//   含 `package:web` 的 web 文件而失败。
export 'src/ast_volcengine_plugin_desktop.dart'
    if (dart.library.js_interop) 'src/ast_volcengine_plugin_web.dart';
