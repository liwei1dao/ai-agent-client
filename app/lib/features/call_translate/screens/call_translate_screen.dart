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

/// 通话翻译界面（聊天气泡风格）。
///
/// 双向通话翻译两条 leg 的字幕共享一条时间线：role==user（我说→对方听）显示在
/// **右侧**紫色气泡；role==peer（对方说→我听）显示在**左侧**白色气泡。
/// 每个气泡内含原文 + 译文。开始/停止控制以浮动按钮形式悬浮在右下角。
class CallTranslateScreen extends ConsumerStatefulWidget {
  const CallTranslateScreen({super.key});

  @override
  ConsumerState<CallTranslateScreen> createState() => _CallTranslateScreenState();
}

class _CallTranslateScreenState extends ConsumerState<CallTranslateScreen> {
  CallTranslationSession? _session;
  StreamSubscription<TranslateSubtitleEvent>? _subtitleSub;
  StreamSubscription<TranslateErrorEvent>? _errorSub;
  StreamSubscription<TranslationSessionState>? _stateSub;

  final SubtitleAggregator _aggregator = SubtitleAggregator();
  final List<TranslateErrorEvent> _errors = [];
  final ScrollController _scrollController = ScrollController();
  TranslationSessionState _sessionState = TranslationSessionState.stopped;
  bool _starting = false;
  bool _configExpanded = true;

  @override
  void dispose() {
    _subtitleSub?.cancel();
    _errorSub?.cancel();
    _stateSub?.cancel();
    _scrollController.dispose();
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
        inputMode: 'external',
      ).build(),
      downlinkAgentType: downlinkAgent.type,
      downlinkConfig: AgentConfigBuilder(
        agent: downlinkAgent,
        allServices: services,
        srcLang: peerLang,
        dstLang: userLang,
        inputMode: 'external',
      ).build(),
      userLanguage: userLang,
      peerLanguage: peerLang,
    );

    setState(() => _starting = true);
    try {
      final server = ref.read(translateServerProvider);
      final session = await server.startCallTranslation(req);
      _bindSession(session);
      // 启动后自动折叠配置区，把空间让给字幕。
      setState(() => _configExpanded = false);
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
      if (mounted) {
        setState(() {});
        _scrollToBottom();
      }
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
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

    // 设备断开 → 自动结束通话翻译。
    // 通话翻译依赖耳机持续在线（双向音频通过设备走），耳机一旦掉线 session
    // 已无意义；这里在 UI 层观测 active session 变化兜底关闭。
    ref.listen<AsyncValue<DeviceSession?>>(activeDeviceSessionProvider,
        (prev, next) {
      if (_session == null) return;
      final s = next.valueOrNull;
      final ready = s != null && s.state == DeviceConnectionState.ready;
      if (!ready) {
        _stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('耳机已断开，已自动结束通话翻译')),
          );
        }
      }
    });

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
        actions: [
          // 配置区折叠/展开按钮——session 活动时默认折叠，可手动展开微调
          IconButton(
            tooltip: _configExpanded ? '收起配置' : '展开配置',
            icon: Icon(_configExpanded ? Icons.expand_less : Icons.tune,
                color: colors.text2),
            onPressed: () =>
                setState(() => _configExpanded = !_configExpanded),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildDeviceStatusBar(config, session, colors),
                if (_configExpanded)
                  _buildConfigCard(uplinkAgent, downlinkAgent, userLang,
                      peerLang, colors, isActive),
                if (_errors.isNotEmpty) _buildErrorChip(),
                Expanded(child: _buildChatList(colors, userLang, peerLang)),
              ],
            ),
            // 浮动开始/停止按钮——底部居中，电话接听 / 挂断风格
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: _buildFloatingActionButton(canStart, isActive),
              ),
            ),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.headset_mic : Icons.headset_off,
              size: 16, color: color),
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
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
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
          const SizedBox(height: 8),
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
        padding: const EdgeInsets.all(8),
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
                    fontSize: 10,
                    color: colors.text2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Text('$label:',
                style: TextStyle(fontSize: 11, color: colors.text2)),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _langLabel(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: enabled ? colors.text1 : colors.text2),
              ),
            ),
            Icon(Icons.expand_more, size: 14, color: colors.text2),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(bool canStart, bool isActive) {
    final bool busy = _starting;
    final bool enabled = isActive ? !busy : (canStart && !busy);
    final Color bg = isActive
        ? const Color(0xFFEF4444)
        : (enabled ? const Color(0xFF10B981) : const Color(0xFFCBD5E1));
    final IconData icon = isActive ? Icons.call_end : Icons.call;
    final String hint = isActive
        ? (busy ? '正在停止…' : '挂断')
        : (busy ? '正在启动…' : '接听');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? (isActive ? _stop : _start) : null,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: bg.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Transform.rotate(
                      // 挂断键习惯性旋转 135°
                      angle: isActive ? 2.356 : 0,
                      child: Icon(icon, color: Colors.white, size: 30),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: enabled ? AppTheme.text1 : AppTheme.text2,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorChip() {
    final last = _errors.last;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: Color(0xFFEF4444)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${last.code}${last.role != null ? ' [${last.role!.name}]' : ''}: ${last.message ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
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

  Widget _buildChatList(AppColors colors, String? userLang, String? peerLang) {
    final lines = _aggregator.lines;
    final userPartial = _aggregator.partialSourceFor(SubtitleRole.user);
    final peerPartial = _aggregator.partialSourceFor(SubtitleRole.peer);

    // 把 finalized lines + 两条 in-progress partial 拼成渲染序列。
    // partial 永远放最后；如果两侧都有 partial，按 user 在前 peer 在后的固定序。
    final items = <_ChatItem>[
      for (final line in lines) _ChatItem.fromLine(line),
      if ((userPartial ?? '').isNotEmpty)
        _ChatItem.partial(SubtitleRole.user, userPartial!),
      if ((peerPartial ?? '').isNotEmpty)
        _ChatItem.partial(SubtitleRole.peer, peerPartial!),
    ];

    if (items.isEmpty) {
      return Center(
        child: Text(_sessionState == TranslationSessionState.active
            ? '等待通话内容…'
            : '点击右下角按钮开始通话翻译',
            style: TextStyle(fontSize: 12, color: colors.text2)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: items.length,
      itemBuilder: (_, i) => _SubtitleBubble(
        item: items[i],
        userLangLabel: _langLabel(userLang),
        peerLangLabel: _langLabel(peerLang),
        colors: colors,
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

// ─── 字幕气泡数据模型 ────────────────────────────────────────────────────────

class _ChatItem {
  _ChatItem({
    required this.role,
    required this.source,
    required this.translated,
    required this.translatedPartial,
    required this.isInProgress,
  });

  factory _ChatItem.fromLine(SubtitleLine line) => _ChatItem(
        role: line.role,
        source: line.source,
        translated: line.translated,
        translatedPartial: line.translatedPartial,
        isInProgress: false,
      );

  factory _ChatItem.partial(SubtitleRole role, String source) => _ChatItem(
        role: role,
        source: source,
        translated: null,
        translatedPartial: false,
        isInProgress: true,
      );

  final SubtitleRole role;
  final String source;
  final String? translated;
  final bool translatedPartial;

  /// 在途的 partial 源文（还没拿到 final / requestId），UI 渲染为半透明斜体。
  final bool isInProgress;
}

class _SubtitleBubble extends StatelessWidget {
  const _SubtitleBubble({
    required this.item,
    required this.userLangLabel,
    required this.peerLangLabel,
    required this.colors,
  });
  final _ChatItem item;
  final String userLangLabel;
  final String peerLangLabel;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final isUser = item.role == SubtitleRole.user;
    final langLabel = isUser ? userLangLabel : peerLangLabel;
    final bubbleColor =
        isUser ? AppTheme.primary : Colors.white;
    final textColor =
        isUser ? Colors.white : colors.text1;
    final translatedColor =
        isUser ? Colors.white.withValues(alpha: 0.85) : colors.text2;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 角色 + 语言标签
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Text(
              '${isUser ? '我' : '对方'} · $langLabel',
              style: TextStyle(fontSize: 10, color: colors.text2),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: bubbleColor.withValues(
                    alpha: item.isInProgress ? 0.7 : 1.0),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: isUser
                    ? null
                    : Border.all(color: colors.border),
                boxShadow: isUser
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.source,
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                      height: 1.4,
                      fontStyle: item.isInProgress
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                  if ((item.translated ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.translated!,
                      style: TextStyle(
                        fontSize: 12,
                        color: translatedColor,
                        height: 1.4,
                        fontStyle: item.translatedPartial
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── pickers ─────────────────────────────────────────────────────────────────

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
