import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/themes/app_theme.dart';
import '../providers/auth_provider.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authProvider);
    ref.listen(authProvider, (prev, next) {
      if (next.status == AuthStatus.authed) {
        context.go('/');
      } else if (next.status == AuthStatus.unauthed) {
        context.go('/login');
      }
    });

    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.headset, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 24),
            Text(
              'AI Agent',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.text1,
              ),
            ),
            const SizedBox(height: 32),
            if (state.status == AuthStatus.initializing)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}
