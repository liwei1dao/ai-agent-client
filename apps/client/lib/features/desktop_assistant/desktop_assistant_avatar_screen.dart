import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:rive/rive.dart' show RiveAnimation;

import '../../core/services/config_service.dart';
import '../../shared/themes/app_theme.dart';
import 'desktop_assistant_avatars.dart';

/// 桌面悬浮助理「形象选择」设置界面。每个形象用 Lottie 实时预览，点选即生效
/// （已开启悬浮窗时主 app 会把新形象 push 给 overlay）。
class DesktopAssistantAvatarScreen extends ConsumerWidget {
  const DesktopAssistantAvatarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(
        configServiceProvider.select((c) => c.desktopAssistantAvatar));
    return Scaffold(
      appBar: AppBar(title: const Text('助理形象')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.92,
        children: [
          for (final a in kDesktopAssistantAvatars)
            _AvatarCard(
              avatar: a,
              selected: a.key == current,
              onTap: () => ref
                  .read(configServiceProvider.notifier)
                  .setDesktopAssistantAvatar(a.key),
            ),
        ],
      ),
    );
  }
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({
    required this.avatar,
    required this.selected,
    required this.onTap,
  });

  final DesktopAssistantAvatar avatar;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : colors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: avatar.isRive
                    ? RiveAnimation.asset(avatar.asset, fit: BoxFit.contain)
                    : Lottie.asset(avatar.asset,
                        fit: BoxFit.contain, repeat: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.check_circle,
                          color: AppTheme.primary, size: 16),
                    ),
                  Text(avatar.label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color:
                              selected ? AppTheme.primary : colors.text1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
