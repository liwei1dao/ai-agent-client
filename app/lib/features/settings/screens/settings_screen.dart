import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/settings_provider.dart';
import '../../../shared/themes/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _streaming = true;
  bool _vad = true;
  int _historyCount = 20;
  int _silenceTimeout = 3;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ── 外观 ──────────────────────────────────────────────────
          _SectionLabel('外观'),
          _SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '主题模式',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.text1,
                        ),
                      ),
                    ),
                    _ThemePill(
                      current: settings.themeMode,
                      onChanged: (mode) =>
                          ref.read(settingsProvider.notifier).setThemeMode(mode),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 对话通用 ──────────────────────────────────────────────
          _SectionLabel('对话通用'),
          _SectionCard(
            children: [
              SwitchListTile(
                title: const Text('流式输出',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                subtitle: const Text('逐字显示模型回复',
                    style: TextStyle(fontSize: 12, color: AppTheme.text2)),
                value: _streaming,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _streaming = v),
              ),
              const Divider(height: 1, color: AppTheme.borderColor),
              ListTile(
                title: const Text('历史消息数',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                subtitle: Slider(
                  value: _historyCount.toDouble(),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  activeColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _historyCount = v.round()),
                ),
                trailing: Text(
                  '$_historyCount 条',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),

          // ── 语音通用 ──────────────────────────────────────────────
          _SectionLabel('语音通用'),
          _SectionCard(
            children: [
              SwitchListTile(
                title: const Text('语音活动检测 (VAD)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                subtitle: const Text('自动检测说话开始与结束',
                    style: TextStyle(fontSize: 12, color: AppTheme.text2)),
                value: _vad,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _vad = v),
              ),
              const Divider(height: 1, color: AppTheme.borderColor),
              ListTile(
                title: const Text('静音超时',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                subtitle: Slider(
                  value: _silenceTimeout.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: AppTheme.primary,
                  onChanged: (v) => setState(() => _silenceTimeout = v.round()),
                ),
                trailing: Text(
                  '$_silenceTimeout 秒',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),

          // ── MCP 服务器 ────────────────────────────────────────────
          _SectionLabel('MCP 服务器'),
          _SectionCard(
            children: [
              ListTile(
                title: const Text('MCP 服务器管理',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                subtitle: const Text('3 个服务器已配置',
                    style: TextStyle(fontSize: 12, color: AppTheme.text2)),
                trailing: const Icon(Icons.chevron_right, color: AppTheme.text2),
                onTap: () => context.push('/settings/mcp'),
              ),
            ],
          ),

          // ── 关于 ──────────────────────────────────────────────────
          _SectionLabel('关于'),
          _SectionCard(
            children: [
              const ListTile(
                leading: Icon(Icons.smart_toy_outlined, color: AppTheme.primary),
                title: Text('AI Agent Client',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                subtitle: Text('v1.0.0',
                    style: TextStyle(fontSize: 12, color: AppTheme.text2)),
              ),
              const Divider(height: 1, color: AppTheme.borderColor),
              ListTile(
                leading: const Icon(Icons.code_outlined, color: AppTheme.primary),
                title: const Text('开源地址',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                trailing: const Icon(Icons.open_in_new, size: 18, color: AppTheme.text2),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Section label ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.text2,
        ),
      ),
    );
  }
}

// ── Section card ───────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

// ── Theme mode segmented button ────────────────────────────────────────────

class _ThemePill extends StatelessWidget {
  const _ThemePill({required this.current, required this.onChanged});
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode_outlined),
          tooltip: '浅色',
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode_outlined),
          tooltip: '深色',
        ),
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.auto_mode_outlined),
          tooltip: '跟随系统',
        ),
      ],
      selected: {current},
      onSelectionChanged: (v) => onChanged(v.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
