import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart' as getx;
import 'package:go_router/go_router.dart';
import 'package:agents_server/agents_server.dart';
import 'package:tts_azure/tts_azure.dart';

import 'core/services/config_service.dart';
import 'core/services/device_service.dart';
import 'core/translations/app_translations.dart';
import 'features/agents/screens/agent_panel_screen.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/splash_screen.dart';
import 'features/call_translate/screens/call_translate_screen.dart';
import 'features/chat/screens/chat_screen.dart';
import 'features/chat/screens/translate_screen.dart';
import 'features/devices/screens/device_screen.dart';
import 'features/home/screens/home_screen.dart';
import 'features/profile/screens/profile_screen.dart';
import 'features/services/screens/services_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'modules/meeting/bindings/meeting_binding.dart';
import 'modules/meeting/views/meeting_view.dart';
import 'shared/themes/app_theme.dart';

/// GoRouter 与 GetX 共用的 root navigator key —— 让 `Get.bottomSheet` /
/// `Get.dialog` / `Get.toNamed` 在 routerDelegate 模式下也能拿到 navigator。
final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter _buildRouter({
  required Listenable refresh,
  required ValueGetter<AuthState> readAuth,
}) {
  return GoRouter(
    initialLocation: '/splash',
    navigatorKey: rootNavigatorKey,
    refreshListenable: refresh,
    redirect: (ctx, state) {
      final auth = readAuth();
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/splash';

      switch (auth.status) {
        case AuthStatus.initializing:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthed:
          return isAuthRoute ? (loc == '/login' ? null : '/login') : '/login';
        case AuthStatus.authed:
          return isAuthRoute ? '/' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
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
                GoRoute(
                  path: 'meeting',
                  builder: (_, __) {
                    // 使用 GetX Bindings 注册控制器，再展示移植自 deepvoice_client_liwei
                    // 的 MeetingView。
                    MeetingBinding().dependencies();
                    return const MeetingView();
                  },
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
              builder: (_, __) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'advanced',
                  builder: (_, __) => const SettingsScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AuthRefresh extends ChangeNotifier {
  void bump() => notifyListeners();
}

class _AppState extends ConsumerState<App> {
  bool _audioModeSynced = false;
  GoRouter? _router;
  final _authRefresh = _AuthRefresh();

  void _syncAudioOutputMode(AudioOutputMode mode) {
    if (_audioModeSynced) return;
    _audioModeSynced = true;
    final modeStr = mode.name;
    AgentsServerBridge().setAudioOutputMode(modeStr);
    TtsAzurePluginDart.setAudioOutputMode(modeStr);
  }

  @override
  void dispose() {
    _authRefresh.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = ref.watch(configServiceProvider);
    _syncAudioOutputMode(appConfig.audioOutputMode);
    // 触发 DeviceManager 初始化（注册厂商 + 跟随配置切换 vendor）。
    ref.watch(deviceManagerProvider);
    // 自动重连守护：监听远端断开 → 退避重连 lastDeviceId。
    ref.watch(deviceAutoReconnectProvider);

    // 把 authProvider 状态变化转成 Listenable 通知 GoRouter 重做 redirect。
    ref.listen<AuthState>(authProvider, (_, __) => _authRefresh.bump());

    _router ??= _buildRouter(
      refresh: _authRefresh,
      readAuth: () => ref.read(authProvider),
    );

    // 让 GetX 用我们 GoRouter 的 root navigator key —— 解决
    // `Get.bottomSheet` / `Get.dialog` 在 routerDelegate 模式下 Get.key 为空的
    // null check 报错。
    getx.Get.addKey(rootNavigatorKey);

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      builder: (context, _) => getx.GetMaterialApp.router(
        title: '云衍测试平台',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: appConfig.themeMode,
        // 全应用强制简体中文，所有 `.tr` 调用走 zhCN 翻译表。
        translations: AppTranslations(),
        locale: const Locale('zh', 'CN'),
        fallbackLocale: const Locale('zh', 'CN'),
        routerDelegate: _router!.routerDelegate,
        routeInformationParser: _router!.routeInformationParser,
        routeInformationProvider: _router!.routeInformationProvider,
        backButtonDispatcher: _router!.backButtonDispatcher,
        builder: EasyLoading.init(),
      ),
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
    (Icons.person_outline, Icons.person),
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
