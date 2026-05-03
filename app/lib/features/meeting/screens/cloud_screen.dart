import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/themes/app_theme.dart';

/// VOITRANS 私有云 — 简化版，仅展示开关 + 容量 + 入口。
/// 真正的同步逻辑在 Round 5 接通后端时落地。
class CloudScreen extends ConsumerStatefulWidget {
  const CloudScreen({super.key});

  @override
  ConsumerState<CloudScreen> createState() => _CloudScreenState();
}

class _CloudScreenState extends ConsumerState<CloudScreen> {
  bool _enabled = false;
  bool _autoUpload = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('VOITRANS 私有云')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.cloud_outlined, color: Colors.white),
                    SizedBox(width: 8),
                    Text('VOITRANS 私有云',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: 0,
                  backgroundColor: Colors.white.withValues(alpha: 0.3),
                  valueColor:
                      const AlwaysStoppedAnimation(Colors.white),
                ),
                const SizedBox(height: 8),
                Text('已用 0 MB / 共 0 MB',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Tile(
            title: '启用云端同步',
            subtitle: '将本地会议自动同步到云端',
            trailing: Switch(
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ),
          _Tile(
            title: '仅 Wi-Fi 上传',
            subtitle: '关闭后将使用流量同步',
            trailing: Switch(
              value: _autoUpload,
              onChanged: _enabled
                  ? (v) => setState(() => _autoUpload = v)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          Text('提示',
              style: TextStyle(
                  color: colors.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '私有云同步需要服务器配置，请在「设置 → 云端」中填入服务地址。',
            style: TextStyle(color: colors.text2, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.text1)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(fontSize: 12, color: colors.text2)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
