import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:agents_server/agents_server.dart';
import 'package:tts_azure/tts_azure.dart';

import 'core/services/config_service.dart';
import 'core/services/device_service.dart';
import 'features/agents/screens/agent_panel_screen.dart';
import 'features/assistant/screens/assistant_screen.dart';
import 'features/call_translate/screens/call_translate_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/chat/screens/translate_screen.dart';
import 'features/devices/screens/device_ota_screen.dart';
import 'features/desktop_assistant/desktop_assistant_avatars.dart';
import 'features/desktop_assistant/desktop_assistant_controller.dart';
import 'features/devices/screens/device_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/services/screens/services_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'shared/themes/app_theme.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _ShellScaffold(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const HomeScreen(),
            routes: [
              GoRoute(
                path: 'agent/:id/chat',
                builder: (_, state) =>
                    ChatScreen(agentId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'agent/:id/translate',
                builder: (_, state) =>
                    TranslateScreen(agentId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'devices',
                builder: (_, __) => const DeviceScreen(),
                routes: [
                  GoRoute(
                    path: 'ota',
                    builder: (_, __) => const DeviceOtaScreen(),
                  ),
                ],
              ),
              GoRoute(
                path: 'call-translate',
                builder: (_, __) => const CallTranslateScreen(),
              ),
              GoRoute(
                path: 'ai-assistant',
                builder: (_, __) => const AssistantScreen(),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/agents',
            builder: (_, __) => const AgentPanelScreen(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
              path: '/services', builder: (_, __) => const ServicesScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ]),
      ],
    ),
  ],
);

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool _audioModeSynced = false;

  static const _navChannel = MethodChannel('desktop_assistant/nav');
  static const _desktopAssistant = DesktopAssistantController();
  bool? _lastDesktopAssistantEnabled;
  String _currentAvatarKey = kDefaultDesktopAssistantAvatar;
  StreamSubscription<dynamic>? _overlaySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 冷启动若由悬浮窗点击拉起，消费待导航路由。
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingRoute());
    // overlay 启动后发 'ready'（它读不到 config）→ 主 app 回推当前形象 key。
    if (defaultTargetPlatform == TargetPlatform.android) {
      _overlaySub = FlutterOverlayWindow.overlayListener.listen((event) {
        if (event == 'ready') {
          FlutterOverlayWindow.shareData(_currentAvatarKey);
        }
      });
    }
  }

  @override
  void dispose() {
    _overlaySub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 悬浮窗点击把 app 拉回前台时消费待导航路由。
    if (state == AppLifecycleState.resumed) _consumePendingRoute();
  }

  Future<void> _consumePendingRoute() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final route =
          await _navChannel.invokeMethod<String>('consumePendingRoute');
      if (route != null && route.isNotEmpty) _router.go(route);
    } catch (_) {
      // channel 未就绪 / 非 Android：忽略。
    }
  }

  /// 跟随配置开关/形象，显示·隐藏·切换桌面悬浮助理（初始值 + 后续变化都触发）。
  void _syncDesktopAssistant(bool enabled, String avatarKey) {
    final avatarChanged = _currentAvatarKey != avatarKey;
    _currentAvatarKey = avatarKey;
    if (_lastDesktopAssistantEnabled != enabled) {
      // 首次 sync 且 enabled=false 是 config 加载完成前的默认值（AppConfig() 默认 false，
      // 随后 _load() 异步把持久化的 true 补上）。此时浮窗本就没显示，绝不能调 disable——
      // 否则它的 releaseRuntime 会和紧接着 enable() 的 acquireRuntime 并发竞态，
      // 因 await 链长短不同导致 release 后到、把保活引用干掉（划掉 app 浮窗即消失）。
      final firstSync = _lastDesktopAssistantEnabled == null;
      _lastDesktopAssistantEnabled = enabled;
      if (enabled) {
        // enable 后 overlay 会发 'ready'，届时回推 _currentAvatarKey。
        _desktopAssistant.enable();
      } else if (!firstSync) {
        _desktopAssistant.disable();
      }
    } else if (enabled &&
        avatarChanged &&
        defaultTargetPlatform == TargetPlatform.android) {
      // 已显示状态下切换形象 → 立即推送给 overlay。
      FlutterOverlayWindow.shareData(avatarKey);
    }
  }

  void _syncAudioOutputMode(AudioOutputMode mode) {
    if (_audioModeSynced) return;
    _audioModeSynced = true;
    final modeStr = mode.name;
    AgentsServerBridge().setAudioOutputMode(modeStr);
    TtsAzurePluginDart.setAudioOutputMode(modeStr);
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = ref.watch(configServiceProvider);
    _syncAudioOutputMode(appConfig.audioOutputMode);
    _syncDesktopAssistant(
        appConfig.desktopAssistantEnabled, appConfig.desktopAssistantAvatar);
    // 触发 DeviceManager 初始化（注册厂商 + 跟随配置切换 vendor）。
    ref.watch(deviceManagerProvider);
    // 自动重连守护：监听远端断开 → 退避重连 lastDeviceId。
    ref.watch(deviceAutoReconnectProvider);

    return MaterialApp.router(
      title: 'Unihelper',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: appConfig.themeMode,
      routerConfig: _router,
    );
  }
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home),
    (Icons.smart_toy_outlined, Icons.smart_toy),
    (Icons.grid_view_outlined, Icons.grid_view),
    (Icons.tune_outlined, Icons.tune),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        height: 56 + MediaQuery.paddingOf(context).bottom,
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.border)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: Row(
          children: List.generate(_items.length, (i) {
            final active = shell.currentIndex == i;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => shell.goBranch(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      active ? _items[i].$2 : _items[i].$1,
                      size: 24,
                      color: active ? AppTheme.primary : colors.text2,
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: active ? 4 : 0,
                      height: active ? 4 : 0,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
