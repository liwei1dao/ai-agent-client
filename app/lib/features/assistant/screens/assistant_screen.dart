import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';

import '../../../core/services/config_service.dart';
import '../../../core/services/locale_service.dart';
import '../../../shared/themes/app_theme.dart';
import '../../agents/providers/agent_list_provider.dart';
import '../../desktop_assistant/overlay/overlay_sync.dart';
import '../../desktop_assistant/overlay_bus.dart';
import '../providers/assistant_chat_provider.dart';

/// AI 助理界面（聊天气泡风格）。
///
/// 单 agent / 单语言场景：用户语音通过**系统麦克风**上行（Android 上经经典蓝牙
/// HFP/SCO 自动路由到已连接的蓝牙耳机）→ chat / sts-chat agent 做 STT/LLM/TTS →
/// AI 回复通过系统扬声器播放。不再依赖 BLE 设备连接。
/// user 消息显示在右侧紫色气泡，assistant 消息显示在左侧白色气泡。
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  late final AssistantChatController _controller;
  final ScrollController _scrollController = ScrollController();
  bool _configExpanded = true;

  /// 悬浮窗桌宠侧的会话状态（经 shareData 同步而来）；用于让本界面的「连接/挂断」
  /// 与桌宠保持一致：桌宠在通话时本界面也显示「挂断」，且能直接挂断它。
  OverlaySessionState _remotePet = OverlaySessionState.idle;
  OverlaySessionState _lastBroadcast = OverlaySessionState.idle;
  StreamSubscription? _overlaySub;

  bool get _overlayCapable =>
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _controller = AssistantChatController();
    _controller.addListener(_onControllerChanged);
    if (_overlayCapable) {
      // 经 OverlayBus 订阅（底层 overlayListener 是单订阅流，app.dart 已占用，
      // 必须共用广播总线，否则二次 listen 会抛异常）。
      _overlaySub = OverlayBus.instance.stream.listen(_onPetMessage);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 打开即加载该 agent 的历史对话（含桌宠刚聊的内容）。
      _loadHistory();
      // 请求桌宠回播当前状态（桌宠可能正在通话）。
      if (_overlayCapable) {
        try {
          FlutterOverlayWindow.shareData(OverlaySyncMsg.syncRequest);
        } catch (_) {}
      }
    });
  }

  Future<void> _loadHistory() async {
    final id = ref.read(configServiceProvider).defaultAssistantAgentId;
    if (id != null) await _controller.loadHistory(id);
  }

  @override
  void dispose() {
    // 离开界面前告知桌宠本界面已不再持有会话（本界面会话随 controller.dispose
    // 一并 stopAgent，状态需同步给桌宠以免它一直显示「通话中」）。
    if (_overlayCapable) {
      try {
        FlutterOverlayWindow.shareData(
            OverlaySyncMsg.state(OverlaySessionState.idle));
      } catch (_) {}
    }
    _overlaySub?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
    _broadcastState();
    // 自身会话状态变化后重新评估是否该被动镜像桌宠（如自己挂断后桌宠仍在通话）。
    _syncPassiveMirror();
  }

  /// 桌宠持有会话、本界面自己未通话 → 被动镜像桌宠会话，让聊天内容面板也实时同步
  /// （不只是连接状态）；否则退出镜像（自己接管会话 / 桌宠已挂断）。幂等，可重复调。
  void _syncPassiveMirror() {
    if (!_overlayCapable) return;
    final petBusy = _remotePet == OverlaySessionState.active ||
        _remotePet == OverlaySessionState.starting;
    final selfBusy = _controller.isActive || _controller.isStarting;
    if (petBusy && !selfBusy) {
      final id = ref.read(configServiceProvider).defaultAssistantAgentId;
      if (id != null) _controller.startPassive(id);
    } else {
      _controller.stopPassive();
    }
  }

  /// 本界面会话的粗粒度状态。
  OverlaySessionState get _ownState => _controller.isActive
      ? OverlaySessionState.active
      : (_controller.isStarting
          ? OverlaySessionState.starting
          : OverlaySessionState.idle);

  /// 状态变化时广播给桌宠（默认仅在变化时发，避免流式 notify 刷屏；[force] 用于
  /// 响应桌宠的 sync 请求）。
  void _broadcastState({bool force = false}) {
    if (!_overlayCapable) return;
    final s = _ownState;
    if (!force && s == _lastBroadcast) return;
    _lastBroadcast = s;
    try {
      FlutterOverlayWindow.shareData(OverlaySyncMsg.state(s));
    } catch (_) {}
  }

  /// 收到桌宠的消息：状态同步 / 要求本界面挂断 / 请求回播状态。
  void _onPetMessage(dynamic event) {
    if (event is! String || event.isEmpty || !mounted) return;
    final st = OverlaySyncMsg.parseState(event);
    if (st != null) {
      if (_remotePet != st) setState(() => _remotePet = st);
      // 桌宠开始/结束通话 → 进入/退出被动镜像，让聊天内容实时同步。
      _syncPassiveMirror();
      return;
    }
    if (event == OverlaySyncMsg.hangup) {
      if (_controller.isActive || _controller.isStarting) _controller.stop();
    } else if (event == OverlaySyncMsg.syncRequest) {
      // 桌宠（刚启动）请求本界面状态 → 强制回播一次。
      _broadcastState(force: true);
    }
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

    await _controller.start(
      agent: agent,
      userLanguage: userLang,
      services: services,
    );

    if (!mounted) return;
    if (_controller.isActive) {
      // 启动后自动折叠配置区，把空间让给对话。
      setState(() => _configExpanded = false);
    } else if (_controller.lastError != null) {
      _toast('启动失败：${_controller.lastError}');
    }
  }

  /// 挂断：本界面持有会话则停自己；否则（桌宠持有）请求桌宠挂断。
  Future<void> _hangup() async {
    if (_controller.isActive || _controller.isStarting) {
      await _controller.stop();
    } else if (_remotePet != OverlaySessionState.idle) {
      if (_overlayCapable) {
        try {
          FlutterOverlayWindow.shareData(OverlaySyncMsg.hangup);
        } catch (_) {}
      }
      setState(() => _remotePet = OverlaySessionState.idle);
    }
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

    final agent = _findAgent(agents, config.defaultAssistantAgentId);
    final userLang = config.defaultAssistantUserLanguage;

    // 有效状态 = 本界面会话 或 桌宠会话（任一在通话 → 统一显示「通话中/挂断」）。
    final localBusy = _controller.isStarting;
    final remoteActive = _remotePet == OverlaySessionState.active;
    final remoteBusy = _remotePet == OverlaySessionState.starting;
    final isActive = _controller.isActive || remoteActive;
    final isBusy = localBusy || remoteBusy;
    final canStart = !isActive &&
        !isBusy &&
        agent != null &&
        userLang != null;

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
                _buildStatusBar(agent, colors),
                if (_configExpanded)
                  _buildConfigCard(agent, userLang, colors, isActive),
                if (_controller.lastError != null) _buildErrorChip(),
                Expanded(child: _buildChatList(colors, userLang)),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: _buildFloatingActionButton(canStart, isActive, isBusy),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(AgentDto? agent, AppColors colors) {
    final ok = agent != null;
    final hint = agent == null
        ? '请先选择 AI 助理使用的 agent（chat / sts-chat）'
        : '系统麦克风对话；连接蓝牙耳机后自动经耳机收音/播放';
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
          Icon(ok ? Icons.mic_none : Icons.mic_off, size: 16, color: color),
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

  Widget _buildFloatingActionButton(
      bool canStart, bool isActive, bool busy) {
    // active 时永远可挂断；非 active 时连接中(busy)不可点，仅就绪可发起。
    final bool enabled = isActive ? true : (canStart && !busy);
    final Color bg = isActive
        ? const Color(0xFFEF4444)
        : (enabled ? const Color(0xFF10B981) : const Color(0xFFCBD5E1));
    final IconData icon = isActive ? Icons.call_end : Icons.call;
    final bool spinner = busy && !isActive;
    final String hint = isActive
        ? '挂断'
        : (busy ? '正在连接…' : '通话');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? (isActive ? _hangup : _start) : null,
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
              child: spinner
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
    final last = _controller.lastError ?? '';
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
              last,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            color: const Color(0xFFEF4444),
            onPressed: _controller.clearError,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildChatList(AppColors colors, String? userLang) {
    final bubbles = _controller.bubbles;

    if (bubbles.isEmpty) {
      return Center(
        child: Text(_controller.isActive ? '说话开始与 AI 助理对话…' : '点击下方按钮开始通话',
            style: TextStyle(fontSize: 12, color: colors.text2)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: bubbles.length,
      itemBuilder: (_, i) => _ChatBubble(
        bubble: bubbles[i],
        userLangLabel: _langLabel(userLang),
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

// ─── 对话气泡 ───────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.bubble,
    required this.userLangLabel,
    required this.colors,
  });
  final AssistantBubble bubble;
  final String userLangLabel;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final isUser = bubble.isUser;
    final bubbleColor = isUser ? AppTheme.primary : Colors.white;
    final textColor = isUser ? Colors.white : colors.text1;
    final softAlpha = bubble.streaming ? 0.7 : 1.0;

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
                bubble.text,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                  height: 1.4,
                  fontStyle:
                      bubble.streaming ? FontStyle.italic : FontStyle.normal,
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
