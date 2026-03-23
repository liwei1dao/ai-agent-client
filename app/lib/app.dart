import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/agents/screens/agent_panel_screen.dart';
import 'features/chat_agent/screens/chat_agent_screen.dart';
import 'features/services/screens/services_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/settings/screens/mcp_servers_screen.dart';
import 'features/settings/screens/add_mcp_screen.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/themes/app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider).themeMode;
    return MaterialApp.router(
      title: 'AI Agents',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _ShellScaffold(shell: shell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const AgentPanelScreen(),
            routes: [
              GoRoute(
                path: 'agent/:id/chat',
                builder: (_, state) =>
                    ChatAgentScreen(agentId: state.pathParameters['id']!),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/services', builder: (_, __) => const ServicesScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'mcp',
                builder: (_, __) => const McpServersScreen(),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (_, __) => const AddMcpScreen(),
                  ),
                ],
              ),
            ],
          ),
        ]),
      ],
    ),
  ],
);

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.shell});
  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.smart_toy_outlined, Icons.smart_toy),
    (Icons.grid_view_outlined, Icons.grid_view),
    (Icons.tune_outlined, Icons.tune),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        height: 56 + MediaQuery.paddingOf(context).bottom,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.borderColor)),
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
                      color: active ? AppTheme.primary : AppTheme.text2,
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
