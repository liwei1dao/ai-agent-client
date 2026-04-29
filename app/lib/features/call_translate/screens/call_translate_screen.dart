import 'dart:async';

import 'package:device_manager/device_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import 'package:translate_server/translate_server.dart';

import '../../../core/services/agent_config_builder.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/services/translate_service.dart';
import '../../../shared/themes/app_theme.dart';
import '../../agents/providers/agent_list_provider.dart';

/// 通话翻译界面。
///
/// 核心流程：选 uplink/downlink agent + 双语 → "开始" → translate_server (native)
/// 编排两个 agent + 设备 RCSP 通话翻译模式 → 字幕双栏实时显示。
class CallTranslateScreen extends ConsumerStatefulWidget {
  const CallTranslateScreen({super.key});

  @override
  ConsumerState<CallTranslateScreen> createState() => _CallTranslateScreenState();
}

class _CallTranslateScreenState extends ConsumerState<CallTranslateScreen> {
  // 当前 active session 句柄 + 订阅
  CallTranslationSession? _session;
  StreamSubscription<TranslateSubtitleEvent>? _subtitleSub;
  StreamSubscription<TranslateErrorEvent>? _errorSub;
  StreamSubscription<TranslationSessionState>? _stateSub;

  final SubtitleAggregator _aggregator = SubtitleAggregator();
  final List<TranslateErrorEvent> _errors = [];
  TranslationSessionState _sessionState = TranslationSessionState.stopped;
  bool _starting = false;

  @override
  void dispose() {
    _subtitleSub?.cancel();
    _errorSub?.cancel();
    _stateSub?.cancel();
    // 离开界面 = 停止会话；不清前端的 stop 远程取消（best-effort）
    _session?.stop();
    super.dispose();
  }

  // ─── lifecycle ──────────────────────────────────────────────────────────

  Future<void> _start() async {
    final config = ref.read(configServiceProvider);
    final agents = ref.read(agentListProvider);

    final uplinkAgent = _findAgent(agents, config.defaultCallUplinkAgentId);
    final downlinkAgent = _findAgent(agents, config.defaultCallDownlinkAgentId);
    if (uplinkAgent == null || downlinkAgent == null) {
      _toast('请先选择两侧翻译 agent');
      return;
    }
    final userLang = LocaleService.toCanonical(
        config.defaultCallUserLanguage ?? 'zh-CN');
    final peerLang = LocaleService.toCanonical(
        config.defaultCallPeerLanguage ?? 'en-US');

    final services = await LocalDbBridge().getAllServiceConfigs();

    final req = CallTranslationRequest(
      uplinkAgentType: uplinkAgent.type,
      uplinkConfig: AgentConfigBuilder(
        agent: uplinkAgent,
        allServices: services,
        srcLang: userLang,
        dstLang: peerLang,
      ).build(),
      downlinkAgentType: downlinkAgent.type,
      downlinkConfig: AgentConfigBuilder(
        agent: downlinkAgent,
        allServices: services,
        srcLang: peerLang,
        dstLang: userLang,
      ).build(),
      userLanguage: userLang,
      peerLanguage: peerLang,
    );

    setState(() => _starting = true);
    try {
      final server = ref.read(translateServerProvider);
      final session = await server.startCallTranslation(req);
      _bindSession(session);
    } on TranslateException catch (e) {
      _toast('启动失败：${e.code}\n${e.message ?? ''}');
    } catch (e) {
      _toast('启动失败：$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    await _session?.stop();
  }

  void _bindSession(CallTranslationSession session) {
    _session = session;
    _aggregator.reset();
    _errors.clear();
    _subtitleSub = session.subtitles.listen((e) {
      _aggregator.feed(e);
      if (mounted) setState(() {});
    });
    _errorSub = session.errors.listen((e) {
      if (!mounted) return;
      setState(() => _errors.add(e));
    });
    _stateSub = session.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _sessionState = s);
      if (s == TranslationSessionState.stopped ||
          s == TranslationSessionState.error) {
        _subtitleSub?.cancel();
        _errorSub?.cancel();
        _stateSub?.cancel();
        _session = null;
      }
    });
    setState(() => _sessionState = session.state);
  }

  // ─── pickers ────────────────────────────────────────────────────────────

  Future<void> _pickAgent({required bool uplink}) async {
    final agents = ref.read(agentListProvider).where((a) {
      return a.type == 'ast-translate' || a.type == 'translate';
    }).toList();
    if (agents.isEmpty) {
      _toast('没有可用的翻译 agent，请先在 agent 面板创建');
      return;
    }
    final picked = await showModalBottomSheet<AgentDto>(
      context: context,
      builder: (_) => _AgentPickerSheet(agents: agents),
    );
    if (picked == null) return;
    final notifier = ref.read(configServiceProvider.notifier);
    if (uplink) {
      await notifier.setDefaultCallUplinkAgentId(picked.id);
    } else {
      await notifier.setDefaultCallDownlinkAgentId(picked.id);
    }
  }

  Future<void> _pickLang({required bool user}) async {
    final candidates = LocaleService.allCodes
        .map((c) => (c, LocaleService.langNames[c] ?? c))
        .toList(growable: false);
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _LangPickerSheet(candidates: candidates),
    );
    if (picked == null) return;
    final notifier = ref.read(configServiceProvider.notifier);
    if (user) {
      await notifier.setDefaultCallUserLanguage(picked);
    } else {
      await notifier.setDefaultCallPeerLanguage(picked);
    }
  }

  Future<void> _swapLangs() async {
    final cfg = ref.read(configServiceProvider);
    final user = cfg.defaultCallUserLanguage;
    final peer = cfg.defaultCallPeerLanguage;
    if (user == null || peer == null) return;
    final notifier = ref.read(configServiceProvider.notifier);
    await notifier.setDefaultCallUserLanguage(peer);
    await notifier.setDefaultCallPeerLanguage(user);
  }

  // ─── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final config = ref.watch(configServiceProvider);
    final agents = ref.watch(agentListProvider);
    final session = ref.watch(activeDeviceSessionProvider).valueOrNull;

    final uplinkAgent = _findAgent(agents, config.defaultCallUplinkAgentId);
    final downlinkAgent = _findAgent(agents, config.defaultCallDownlinkAgentId);
    final userLang = config.defaultCallUserLanguage;
    final peerLang = config.defaultCallPeerLanguage;

    final isActive = _sessionState == TranslationSessionState.active ||
        _sessionState == TranslationSessionState.starting;
    final canStart = !isActive &&
        !_starting &&
        uplinkAgent != null &&
        downlinkAgent != null &&
        userLang != null &&
        peerLang != null &&
        session != null &&
        session.state == DeviceConnectionState.ready &&
        config.deviceVendor == 'jieli';

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('通话翻译',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildDeviceStatusBar(config, session, colors),
            _buildConfigCard(uplinkAgent, downlinkAgent, userLang, peerLang,
                colors, isActive),
            const SizedBox(height: 12),
            _buildPrimaryAction(canStart, isActive),
            if (_errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildErrorChip(),
            ],
            const SizedBox(height: 12),
            const _SectionLabel('实时字幕'),
            Expanded(child: _buildSubtitlePanel(colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusBar(
      AppConfig config, DeviceSession? session, AppColors colors) {
    final vendor = config.deviceVendor;
    final ok = vendor == 'jieli' &&
        session != null &&
        session.state == DeviceConnectionState.ready;
    final hint = vendor == null
        ? '未选择设备厂商；请前往设置选择「杰理」'
        : vendor != 'jieli'
            ? '通话翻译当前仅支持「杰理」设备'
            : session == null
                ? '未连接耳机；请先到「设备」连接'
                : session.state != DeviceConnectionState.ready
                    ? '设备未就绪：${session.state.name}'
                    : '设备已就绪：${session.info.name}';
    final color = ok ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.headset_mic : Icons.headset_off,
              size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(hint,
                style: TextStyle(
                    fontSize: 12,
                    color: colors.text1,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigCard(
    AgentDto? uplink,
    AgentDto? downlink,
    String? userLang,
    String? peerLang,
    AppColors colors,
    bool isActive,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _agentTile(
                  title: '我→对方',
                  subtitle: uplink?.name ?? '未选择',
                  enabled: !isActive,
                  onTap: () => _pickAgent(uplink: true),
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _agentTile(
                  title: '对方→我',
                  subtitle: downlink?.name ?? '未选择',
                  enabled: !isActive,
                  onTap: () => _pickAgent(uplink: false),
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _langTile(
                  label: '我',
                  value: userLang,
                  enabled: !isActive,
                  onTap: () => _pickLang(user: true),
                  colors: colors,
                ),
              ),
              IconButton(
                tooltip: '互换语言',
                onPressed:
                    isActive || userLang == null || peerLang == null
                        ? null
                        : _swapLangs,
                icon: Icon(Icons.swap_horiz, color: colors.text2),
              ),
              Expanded(
                child: _langTile(
                  label: '对方',
                  value: peerLang,
                  enabled: !isActive,
                  onTap: () => _pickLang(user: false),
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _agentTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
    required AppColors colors,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: TextStyle(
                    fontSize: 11,
                    color: colors.text2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled ? colors.text1 : colors.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _langTile({
    required String label,
    required String? value,
    required bool enabled,
    required VoidCallback onTap,
    required AppColors colors,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Text('$label:',
                style: TextStyle(fontSize: 12, color: colors.text2)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _langLabel(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: enabled ? colors.text1 : colors.text2),
              ),
            ),
            Icon(Icons.expand_more, size: 16, color: colors.text2),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(bool canStart, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        height: 44,
        child: isActive
            ? FilledButton(
                onPressed: _stop,
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444)),
                child: Text(_starting ? '正在启动…' : '停止通话翻译'),
              )
            : FilledButton(
                onPressed: canStart ? _start : null,
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary),
                child: Text(_starting ? '正在启动…' : '开始通话翻译'),
              ),
      ),
    );
  }

  Widget _buildErrorChip() {
    final last = _errors.last;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${last.code}${last.role != null ? ' [${last.role!.name}]' : ''}: ${last.message ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, color: Color(0xFFEF4444)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            color: const Color(0xFFEF4444),
            onPressed: () => setState(_errors.clear),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitlePanel(AppColors colors) {
    final user = _aggregator.viewOf(SubtitleRole.user);
    final peer = _aggregator.viewOf(SubtitleRole.peer);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _subtitleColumn('我', user, colors, AppTheme.primary)),
          const SizedBox(width: 8),
          Expanded(
              child: _subtitleColumn(
                  '对方', peer, colors, AppTheme.translateAccent)),
        ],
      ),
    );
  }

  Widget _subtitleColumn(
      String title, SubtitleView view, AppColors colors, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent)),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              reverse: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < view.committedSource.length; i++)
                    _subtitleLine(
                      source: view.committedSource[i],
                      translated: i < view.committedTranslated.length
                          ? view.committedTranslated[i]
                          : null,
                      colors: colors,
                      partial: false,
                    ),
                  if ((view.currentSource ?? '').isNotEmpty ||
                      (view.currentTranslated ?? '').isNotEmpty)
                    _subtitleLine(
                      source: view.currentSource ?? '',
                      translated: view.currentTranslated,
                      colors: colors,
                      partial: true,
                    ),
                  if (view.isEmpty)
                    Text('等待输入…',
                        style: TextStyle(
                            fontSize: 12, color: colors.text2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtitleLine({
    required String source,
    required String? translated,
    required AppColors colors,
    required bool partial,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source,
            style: TextStyle(
                fontSize: 13,
                color: colors.text1,
                fontWeight: partial ? FontWeight.w500 : FontWeight.w600,
                fontStyle: partial ? FontStyle.italic : FontStyle.normal),
          ),
          if (translated != null && translated.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              translated,
              style: TextStyle(
                  fontSize: 12,
                  color: colors.text2,
                  fontStyle: partial ? FontStyle.italic : FontStyle.normal),
            ),
          ],
        ],
      ),
    );
  }

  // ─── helpers ────────────────────────────────────────────────────────────

  AgentDto? _findAgent(List<AgentDto> agents, String? id) {
    if (id == null) return null;
    for (final a in agents) {
      if (a.id == id) return a;
    }
    return null;
  }

  String _langLabel(String? code) {
    if (code == null) return '未选择';
    final canon = LocaleService.toCanonical(code);
    return LocaleService.langNames[canon] ?? code;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.appColors.text2)),
      ),
    );
  }
}

class _AgentPickerSheet extends StatelessWidget {
  const _AgentPickerSheet({required this.agents});
  final List<AgentDto> agents;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: agents.length,
        itemBuilder: (_, i) {
          final a = agents[i];
          return ListTile(
            leading: Icon(
              a.type == 'ast-translate'
                  ? Icons.bolt
                  : Icons.translate,
              color: AppTheme.primary,
            ),
            title: Text(a.name,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: colors.text1)),
            subtitle: Text(a.type, style: TextStyle(color: colors.text2)),
            onTap: () => Navigator.pop(context, a),
          );
        },
      ),
    );
  }
}

class _LangPickerSheet extends StatelessWidget {
  const _LangPickerSheet({required this.candidates});
  final List<(String, String)> candidates;
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final (code, name) in candidates)
            ListTile(
              title: Text(name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: colors.text1)),
              subtitle: Text(code, style: TextStyle(color: colors.text2)),
              onTap: () => Navigator.pop(context, code),
            ),
        ],
      ),
    );
  }
}
