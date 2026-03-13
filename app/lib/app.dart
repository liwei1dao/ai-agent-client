import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/agents/screens/agent_panel_screen.dart';
import 'features/chat_agent/screens/chat_agent_screen.dart';
import 'features/translate_agent/screens/translate_agent_screen.dart';
import 'features/services/screens/services_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'features/settings/providers/settings_provider.dart';
import 'shared/themes/app_theme.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider).themeMode;
    return MaterialApp.router(
      title: 'AI Agent',
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
        // Tab 0: Agents
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
              GoRoute(
                path: 'agent/:id/translate',
                builder: (_, state) =>
                    TranslateAgentScreen(agentId: state.pathParameters['id']!),
              ),
            ],
          ),
        ]),
        // Tab 1: Services
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/services',
            builder: (_, __) => const ServicesScreen(),
          ),
        ]),
        // Tab 2: Settings
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

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), label: 'Agents'),
          NavigationDestination(icon: Icon(Icons.hub_outlined), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
