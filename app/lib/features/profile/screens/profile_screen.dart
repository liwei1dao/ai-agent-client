import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/themes/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/services/app_config_service.dart';
import '../widgets/profile_card.dart';

/// 取自 deepvoice_client_liwei `meeting_mine_view.dart` 的 mine 风格 — 头部
/// 个人卡 + 统计卡 + 会员卡 + 多分组列表，作为底部 tab 的"我的/设置"主页。
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final colors = context.appColors;
    final user = auth.user;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            ProfileHeader(
              name: user?.name?.trim().isNotEmpty == true
                  ? user!.name!
                  : '未登录',
              uid: user?.id,
              subtitle: _profileSubtitle(user?.phone, user?.email),
              avatarUrl: user?.avatar,
              onTap: () {},
            ),

            const ProfileStats(stats: [
              ProfileStatItem('0', '天', Colors.lime),
              ProfileStatItem('0', '文件', Colors.lightGreen),
              ProfileStatItem('0', '小时', Colors.blueGrey),
            ]),

            ProfileMemberCard(
              title: '解锁 Starter 会员',
              subtitle: '绑定设备激活会员权益',
              actionText: '立即解锁',
              onTap: () => _todo(context, '会员权益'),
            ),

            // ───────── 会议相关 ─────────
            ProfileCard(children: [
              ProfileItem(
                icon: Icons.article_outlined,
                title: '转写记录',
                onTap: () => context.push('/meeting/transcription'),
              ),
              _divider(colors),
              ProfileItem(
                icon: Icons.layers_outlined,
                title: '模板社区',
                description: '管理',
                onTap: () => context.push('/meeting/templates'),
              ),
              _divider(colors),
              ProfileItem(
                icon: Icons.cloud_upload_outlined,
                title: 'VOITRANS 私有云',
                description: '查看',
                onTap: () => context.push('/meeting/cloud'),
              ),
            ]),

            // ───────── Agent 与服务 ─────────
            ProfileCard(children: [
              ProfileItem(
                icon: Icons.smart_toy_outlined,
                title: 'Agent 管理',
                onTap: () => context.go('/agents'),
              ),
              _divider(colors),
              ProfileItem(
                icon: Icons.grid_view_outlined,
                title: '服务配置',
                onTap: () => context.go('/services'),
              ),
              _divider(colors),
              ProfileItem(
                icon: Icons.settings_remote_outlined,
                title: '我的设备',
                onTap: () => context.push('/devices'),
              ),
            ]),

            // ───────── 诊断 ─────────
            _DiagnosticsCard(),

            // ───────── 应用设置 ─────────
            ProfileCard(children: [
              ProfileItem(
                icon: Icons.tune_outlined,
                title: '高级设置',
                description: '主题/默认 Agent/平台密钥',
                onTap: () => context.push('/settings/advanced'),
              ),
              _divider(colors),
              ProfileItem(
                icon: Icons.help_outline_rounded,
                title: '帮助与反馈',
                onTap: () => _todo(context, '帮助与反馈'),
              ),
              _divider(colors),
              ProfileItem(
                icon: Icons.info_outline_rounded,
                title: '关于',
                description: 'v1.0.0',
                onTap: () => _todo(context, '关于'),
              ),
            ]),

            const SizedBox(height: 8),

            // ───────── 退出登录 ─────────
            if (auth.isAuthed)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: AppTheme.danger,
                    side: const BorderSide(color: AppTheme.danger),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => _confirmLogout(context, ref),
                  child: const Text('退出登录'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _divider(AppColors c) =>
      Divider(height: 1, indent: 50, color: c.border);

  String _profileSubtitle(String? phone, String? email) {
    if (phone != null && phone.isNotEmpty) return phone;
    if (email != null && email.isNotEmpty) return email;
    return '欢迎使用';
  }

  void _todo(BuildContext context, String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title — 待实现')),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后需要重新登录才能访问账号数据。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}

/// 诊断卡 — 显示 AppConfig 当前状态（含腾讯 COS 是否就绪），点击行可手动重新拉取。
class _DiagnosticsCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_DiagnosticsCard> createState() =>
      _DiagnosticsCardState();
}

class _DiagnosticsCardState extends ConsumerState<_DiagnosticsCard> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    final auth = ref.read(authProvider);
    if (!auth.isAuthed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    setState(() => _refreshing = true);
    try {
      await ref
          .read(appConfigServiceProvider)
          .refresh(auth.user!.token);
      if (!mounted) return;
      final cfg = ref.read(appConfigServiceProvider).current;
      final msg = cfg.hasCos
          ? '已拉取 AppConfig，COS 就绪 ✓'
          : '已拉取 AppConfig，但 COS 字段缺失';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拉取失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigServiceProvider).current;
    final colors = context.appColors;

    Widget statRow(String label, String value, bool ok) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.cancel,
              size: 16,
              color: ok ? AppTheme.success : AppTheme.danger,
            ),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(fontSize: 13, color: colors.text2)),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: colors.text1,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
    }

    String mask(String s) =>
        s.isEmpty ? '<空>' : (s.length <= 6 ? s : '${s.substring(0, 4)}…');

    return ProfileCard(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Row(
          children: [
            Icon(Icons.health_and_safety_outlined,
                size: 18, color: colors.text2),
            const SizedBox(width: 8),
            Text('诊断',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.text1)),
            const Spacer(),
            TextButton.icon(
              onPressed: _refreshing ? null : _refresh,
              icon: _refreshing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 16),
              label: const Text('重新拉取'),
            ),
          ],
        ),
      ),
      statRow('COS 就绪', cfg.hasCos ? '是' : '否', cfg.hasCos),
      statRow('COS_BUCKET_NAME', mask(cfg.cosBucket), cfg.cosBucket.isNotEmpty),
      statRow('COS_REGION', mask(cfg.cosRegion), cfg.cosRegion.isNotEmpty),
      statRow('COS_SECRET_ID', mask(cfg.cosSecretId), cfg.cosSecretId.isNotEmpty),
      statRow('COS_SECRET_KEY', mask(cfg.cosSecretKey), cfg.cosSecretKey.isNotEmpty),
      statRow('env 字段数', '${cfg.env.length}', cfg.env.isNotEmpty),
      const SizedBox(height: 6),
    ]);
  }
}
