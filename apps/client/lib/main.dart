import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/log_service.dart';
import 'features/desktop_assistant/overlay/desktop_assistant_overlay.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.init();
  await dotenv.load(fileName: '.env', mergeWith: {}, isOptional: true);
  runApp(const ProviderScope(child: App()));
}

/// 桌面悬浮助理的 overlay isolate 入口（`flutter_overlay_window` 启动它）。
/// 跑在与主 app 独立的 FlutterEngine 上，只渲染悬浮形象。
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DesktopAssistantOverlay());
}
