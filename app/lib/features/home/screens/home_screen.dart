import 'package:device_manager/device_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_db/local_db.dart';

import '../../../core/services/config_service.dart';
import '../../../core/services/device_service.dart';
import '../../../shared/themes/app_theme.dart';
import '../../agents/providers/agent_list_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final config = ref.watch(configServiceProvider);
    final agents = ref.watch(agentListProvider);
    final sessionAsync = ref.watch(activeDeviceSessionProvider);

    final defaultChat = _findAgent(agents, config.defaultChatAgentId);
    final defaultTranslate =
        _findAgent(agents, config.defaultTranslateAgentId);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '首页',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const _SectionLabel('当前设备'),
          _DeviceCard(
            vendor: config.deviceVendor,
            session: sessionAsync.valueOrNull,
            onTap: () => context.push('/devices'),
          ),
          const _SectionLabel('快捷入口'),
          _QuickEntryCard(
            icon: Icons.chat_bubble_outline,
            iconColor: AppTheme.primary,
            label: '默认聊天',
            agent: defaultChat,
            emptyHint: '请在设置中选择默认聊天 Agent',
            onTap: defaultChat == null
                ? null
                : () => context.push('/agent/${defaultChat.id}/chat'),
          ),
          const SizedBox(height: 8),
          _QuickEntryCard(
            icon: Icons.translate_outlined,
            iconColor: const Color(0xFF10B981),
            label: '默认翻译',
            agent: defaultTranslate,
            emptyHint: '请在设置中选择默认翻译 Agent',
            onTap: defaultTranslate == null
                ? null
                : () => context.push('/agent/${defaultTranslate.id}/translate'),
          ),
          const SizedBox(height: 8),
          _CallTranslateEntry(onTap: () => context.push('/call-translate')),
          const SizedBox(height: 8),
          _MeetingEntry(onTap: () => context.push('/meeting')),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '提示：耳机端唤醒后会自动启动「默认聊天」；'
              '若耳机支持翻译键，则启动「默认翻译」。',
              style: TextStyle(fontSize: 12, color: colors.text2),
            ),
          ),
        ],
      ),
    );
  }

  AgentDto? _findAgent(List<AgentDto> list, String? id) {
    if (id == null) return null;
    for (final a in list) {
      if (a.id == id) return a;
    }
    return null;
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.vendor,
    required this.session,
    required this.onTap,
  });

  final String? vendor;
  final DeviceSession? session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final connected = session != null &&
        session!.state == DeviceConnectionState.ready;

    final vendorLabel = _vendorLabel(vendor);
    final stateLabel = vendor == null
        ? '未选择厂商'
        : (session == null ? '未连接' : _stateLabel(session!.state));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (connected ? AppTheme.primary : colors.text2)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.headset_mic_outlined,
                  color: connected ? AppTheme.primary : colors.text2,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session?.info.name.isNotEmpty == true
                          ? session!.info.name
                          : (vendorLabel ?? '未连接设备'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.text1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: connected
                                ? const Color(0xFF10B981)
                                : colors.text2,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          [
                            if (vendorLabel != null) vendorLabel,
                            stateLabel,
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.text2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.text2),
            ],
          ),
        ),
      ),
    );
  }

  static String? _vendorLabel(String? key) {
    if (key == null) return null;
    for (final opt in kDeviceVendorOptions) {
      if (opt.key == key) return opt.label;
    }
    return key;
  }

  static String _stateLabel(DeviceConnectionState s) => switch (s) {
        DeviceConnectionState.disconnected => '未连接',
        DeviceConnectionState.connecting => '连接中…',
        DeviceConnectionState.linkConnected => '握手中…',
        DeviceConnectionState.ready => '已连接',
        DeviceConnectionState.disconnecting => '断开中…',
      };
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.agent,
    required this.emptyHint,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final AgentDto? agent;
  final String emptyHint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasAgent = agent != null;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.text2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasAgent ? agent!.name : emptyHint,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: hasAgent ? colors.text1 : colors.text2,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                hasAgent ? Icons.play_circle_outline : Icons.tune,
                color: hasAgent ? iconColor : colors.text2,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallTranslateEntry extends StatelessWidget {
  const _CallTranslateEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const accent = Color(0xFF38BDF8);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_in_talk_outlined,
                    color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '通话翻译',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.text2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '双向同传 · 耳机端实时听译',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.text1,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.play_circle_outline,
                  color: accent, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeetingEntry extends StatelessWidget {
  const _MeetingEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    const accent = Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.mic_none_rounded,
                    color: accent, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '会议记录',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.text2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '录音 · 转写 · 摘要 · 思维导图',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.text1,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: accent, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.appColors.text2,
        ),
      ),
    );
  }
}
