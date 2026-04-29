import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:agents_server/agents_server.dart';
import 'package:tts_azure/tts_azure.dart';

import 'core/services/config_service.dart';
import 'core/services/device_service.dart';
import 'features/agents/screens/agent_panel_screen.dart';
import 'features/call_translate/screens/call_translate_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/chat/screens/translate_screen.dart';
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
              ),
              GoRoute(
                path: 'call-translate',
                builder: (_, __) => const CallTranslateScreen(),
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

class _AppState extends ConsumerState<App> {
  bool _audioModeSynced = false;

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
    // 触发 DeviceManager 初始化（注册厂商 + 跟随配置切换 vendor）。
    ref.watch(deviceManagerProvider);
    // 自动重连守护：监听远端断开 → 退避重连 lastDeviceId。
    ref.watch(deviceAutoReconnectProvider);

    return MaterialApp.router(
      title: 'AI Agents',
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
