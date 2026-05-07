import 'dart:async';

import 'package:assistant_server/assistant_server.dart';
import 'package:device_manager/device_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';

import '../../../core/services/agent_config_builder.dart';
import '../../../core/services/assistant_service.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/services/locale_service.dart';
import '../../../shared/themes/app_theme.dart';
import '../../agents/providers/agent_list_provider.dart';

/// AI 助理界面（聊天气泡风格）。
///
/// 单 agent / 单语言场景：用户语音通过耳机麦上行 → chat agent STT/LLM/TTS →
/// AI 回复 PCM 通过 RCSP 回灌耳机扬声器。
/// user 消息显示在右侧紫色气泡，assistant 消息显示在左侧白色气泡。
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  AssistantSession? _session;
  StreamSubscription<AssistantMessageEvent>? _messageSub;
  StreamSubscription<AssistantErrorEvent>? _errorSub;
  StreamSubscription<AssistantSessionState>? _stateSub;

  final AssistantMessageAggregator _aggregator = AssistantMessageAggregator();
  final List<AssistantErrorEvent> _errors = [];
  final ScrollController _scrollController = ScrollController();
  AssistantSessionState _sessionState = AssistantSessionState.stopped;
  bool _starting = false;
  bool _configExpanded = true;

  @override
  void dispose() {
    _messageSub?.cancel();
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

    final agent = _findAgent(agents, config.defaultAssistantAgentId);
    if (agent == null) {
      _toast('请先选择 AI 助理使用的 agent（chat 或 sts-chat）');
      return;
    }
    final userLang = LocaleService.toCanonical(
        config.defaultAssistantUserLanguage ?? 'zh-CN');

    final services = await LocalDbBridge().getAllServiceConfigs();

    final req = AssistantRequest(
      agentType: agent.type,
      agentConfig: AgentConfigBuilder.forChat(
        agent: agent,
        allServices: services,
        userLanguage: userLang,
        inputMode: 'external',
      ).build(),
      userLanguage: userLang,
    );

    setState(() => _starting = true);
    try {
      final server = ref.read(assistantServerProvider);
      final session = await server.startAssistant(req);
      _bindSession(session);
      // 启动后自动折叠配置区，把空间让给对话。
      setState(() => _configExpanded = false);
    } on AssistantException catch (e) {
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

  void _bindSession(AssistantSession session) {
    _session = session;
    _aggregator.reset();
    _errors.clear();
    _messageSub = session.messages.listen((e) {
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
      if (s == AssistantSessionState.stopped ||
          s == AssistantSessionState.error) {
        _messageSub?.cancel();
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

  Future<void> _pickAgent() async {
    final agents = ref
        .read(agentListProvider)
        .where((a) => a.type == 'chat' || a.type == 'sts-chat')
        .toList();
    if (agents.isEmpty) {
      _toast('没有可用的 chat / sts-chat agent，请先在 agent 面板创建');
      return;
    }
    final picked = await showModalBottomSheet<AgentDto>(
      context: context,
      builder: (_) => _AgentPickerSheet(agents: agents),
    );
    if (picked == null) return;
    await ref
        .read(configServiceProvider.notifier)
        .setDefaultAssistantAgentId(picked.id);
  }

  Future<void> _pickLang() async {
    final candidates = LocaleService.allCodes
        .map((c) => (c, LocaleService.langNames[c] ?? c))
        .toList(growable: false);
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _LangPickerSheet(candidates: candidates),
    );
    if (picked == null) return;
    await ref
        .read(configServiceProvider.notifier)
        .setDefaultAssistantUserLanguage(picked);
  }

  // ─── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final config = ref.watch(configServiceProvider);
    final agents = ref.watch(agentListProvider);
    final session = ref.watch(activeDeviceSessionProvider).valueOrNull;

    // 设备断开 → 自动结束助理会话。
    ref.listen<AsyncValue<DeviceSession?>>(activeDeviceSessionProvider,
        (prev, next) {
      if (_session == null) return;
      final s = next.valueOrNull;
      final ready = s != null && s.state == DeviceConnectionState.ready;
      if (!ready) {
        _stop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('耳机已断开，已自动结束 AI 助理')),
          );
        }
      }
    });

    final agent = _findAgent(agents, config.defaultAssistantAgentId);
    final userLang = config.defaultAssistantUserLanguage;

    final isActive = _sessionState == AssistantSessionState.active ||
        _sessionState == AssistantSessionState.starting;
    final canStart = !isActive &&
        !_starting &&
        agent != null &&
        userLang != null &&
        session != null &&
        session.state == DeviceConnectionState.ready &&
        config.deviceVendor == 'jieli';

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('AI 助理',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
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
                  _buildConfigCard(agent, userLang, colors, isActive),
                if (_errors.isNotEmpty) _buildErrorChip(),
                Expanded(child: _buildChatList(colors, userLang)),
              ],
            ),
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
            ? 'AI 助理当前仅支持「杰理」设备'
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
    AgentDto? agent,
    String? userLang,
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
                flex: 2,
                child: _agentTile(
                  title: agent == null
                      ? 'AI 助理 (chat / sts-chat)'
                      : 'AI 助理 (${agent.type})',
                  subtitle: agent?.name ?? '未选择',
                  enabled: !isActive,
                  onTap: _pickAgent,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _langTile(
                  label: '语言',
                  value: userLang,
                  enabled: !isActive,
                  onTap: _pickLang,
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
        : (busy ? '正在启动…' : '通话');

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

  Widget _buildChatList(AppColors colors, String? userLang) {
    final lines = _aggregator.lines;
    final userPartial = _aggregator.partialUserText;

    // finalized lines + 一条 in-progress 用户 partial 拼成渲染序列。
    final items = <_ChatItem>[
      for (final line in lines) ..._splitLine(line),
      if ((userPartial ?? '').isNotEmpty)
        _ChatItem.partialUser(userPartial!),
    ];

    if (items.isEmpty) {
      return Center(
        child: Text(_sessionState == AssistantSessionState.active
            ? '说话开始与 AI 助理对话…'
            : '点击下方按钮开始通话',
            style: TextStyle(fontSize: 12, color: colors.text2)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: items.length,
      itemBuilder: (_, i) => _ChatBubble(
        item: items[i],
        userLangLabel: _langLabel(userLang),
        colors: colors,
      ),
    );
  }

  /// 把一行（user+assistant）拆成两个气泡 item 顺序渲染（先 user 再 assistant）。
  List<_ChatItem> _splitLine(AssistantConversationLine line) {
    final out = <_ChatItem>[];
    if (line.userText.isNotEmpty) {
      out.add(_ChatItem.user(line.userText));
    }
    final assistantText = line.assistantText ?? '';
    if (assistantText.isNotEmpty) {
      out.add(_ChatItem.assistant(assistantText, line.assistantPartial));
    }
    return out;
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

// ─── 对话气泡数据模型 ──────────────────────────────────────────────────────

class _ChatItem {
  _ChatItem({
    required this.role,
    required this.text,
    required this.partial,
    required this.isInProgress,
  });

  factory _ChatItem.user(String text) => _ChatItem(
        role: AssistantRole.user,
        text: text,
        partial: false,
        isInProgress: false,
      );

  factory _ChatItem.assistant(String text, bool partial) => _ChatItem(
        role: AssistantRole.assistant,
        text: text,
        partial: partial,
        isInProgress: false,
      );

  factory _ChatItem.partialUser(String text) => _ChatItem(
        role: AssistantRole.user,
        text: text,
        partial: false,
        isInProgress: true,
      );

  final AssistantRole role;
  final String text;

  /// assistant 是否为流式 partial 状态（半透明斜体）。
  final bool partial;

  /// 用户在途 STT partial（半透明斜体气泡）。
  final bool isInProgress;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.item,
    required this.userLangLabel,
    required this.colors,
  });
  final _ChatItem item;
  final String userLangLabel;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final isUser = item.role == AssistantRole.user;
    final bubbleColor = isUser ? AppTheme.primary : Colors.white;
    final textColor = isUser ? Colors.white : colors.text1;
    final softAlpha = item.isInProgress || item.partial ? 0.7 : 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Text(
              isUser ? '我 · $userLangLabel' : 'AI 助理',
              style: TextStyle(fontSize: 10, color: colors.text2),
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: bubbleColor.withValues(alpha: softAlpha),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isUser ? 14 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 14),
                ),
                border: isUser ? null : Border.all(color: colors.border),
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
              child: Text(
                item.text,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  height: 1.4,
                  fontStyle: (item.isInProgress || item.partial)
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
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
            leading: const Icon(Icons.smart_toy, color: AppTheme.primary),
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
