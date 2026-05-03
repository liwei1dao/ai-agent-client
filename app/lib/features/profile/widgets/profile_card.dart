import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/app_theme.dart';

/// 通用卡片容器 — 背景 + 圆角 + 阴影，对应源项目 `_box(...)`
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.children, this.padding});
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding ?? const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

/// 列表项 — icon + 标题 + 可选副文本 + 箭头，对应源项目 `_item(...)`
class ProfileItem extends StatelessWidget {
  const ProfileItem({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? colors.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 15, color: colors.text1),
              ),
            ),
            if (description != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  description!,
                  style: TextStyle(fontSize: 13, color: colors.text2),
                ),
              ),
            if (trailing != null)
              trailing!
            else
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: colors.text2),
          ],
        ),
      ),
    );
  }
}

/// 个人信息头部 — 对应源项目 `_head()`
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.name,
    required this.subtitle,
    this.uid,
    this.avatarUrl,
    this.onTap,
  });

  final String name;
  final String subtitle;
  final String? uid;
  final String? avatarUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: avatarUrl != null && avatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _initialText(initial),
                      ),
                    )
                  : _initialText(initial),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.text1,
                    ),
                  ),
                  if (uid != null && uid!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'ID: $uid',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.text2,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: uid!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制 ID')),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.copy_outlined,
                                size: 14, color: colors.text2),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.text2),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: colors.text2),
          ],
        ),
      ),
    );
  }

  Widget _initialText(String initial) => Text(
        initial,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      );
}

/// 统计三列卡片 — 对应源项目 `_statistics()` 的横向数字栏
class ProfileStats extends StatelessWidget {
  const ProfileStats({super.key, required this.stats});
  final List<ProfileStatItem> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            Expanded(
              child: Container(
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: stats[i].color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      stats[i].value,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.text1,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        stats[i].label,
                        style: TextStyle(fontSize: 11, color: colors.text2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ProfileStatItem {
  const ProfileStatItem(this.value, this.label, this.color);
  final String value;
  final String label;
  final Color color;
}

/// 横幅会员卡 — 对应源项目 `_member()` 的 Starter 会员卡
class ProfileMemberCard extends StatelessWidget {
  const ProfileMemberCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actionText,
    this.onTap,
    this.icon = Icons.auto_awesome,
  });

  final String title;
  final String subtitle;
  final String actionText;
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1E2E), Color(0xFF2D2D44)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.amberAccent, size: 22),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.blue, Colors.pink],
                    ),
                  ),
                  child: Text(
                    actionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
