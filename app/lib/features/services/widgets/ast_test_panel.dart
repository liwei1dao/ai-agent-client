import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:local_db/local_db.dart';
import 'package:service_manager/service_manager.dart';

import '../../../shared/themes/app_theme.dart';
import '../../chat/providers/agent_screen_provider.dart' show AgentMessage;
import '../../chat/widgets/message_bubble.dart';
import 'test_log_panel.dart';

/// AST (end-to-end translate) test session panel. Talks **directly** to the
/// vendor `NativeAstService` via [ServiceManagerBridge] — does **not** go
/// through `agents_server` / `agent_ast_translate`, because those are the
/// orchestration layer and would conflate vendor connectivity bugs with
/// agent-container scheduling bugs (see local_plugins/CLAUDE.md §1).
class AstTestPanel extends StatefulWidget {
  const AstTestPanel({super.key, required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<AstTestPanel> createState() => _AstTestPanelState();
}

enum _Phase { idle, connecting, connected, error }

const _langMap = <String, String>{
  'zh': '中文',
  'en': 'English',
  'ja': '日本語',
  'ko': '한국어',
  'fr': 'Français',
  'de': 'Deutsch',
  'es': 'Español',
  'ru': 'Русский',
  'ar': 'العربية',
  'pt': 'Português',
};

class _AstTestPanelState extends State<AstTestPanel> {
  // ── Selection ─────────────────────────────────────────────────────────────
  ServiceConfigDto? _selected;
  List<AgentDto> _polychatAgents = const [];
  AgentDto? _selectedAgent;
  final _db = LocalDbBridge();
  String _srcLang = 'zh';
  String _dstLang = 'en';

  // ── Test session ──────────────────────────────────────────────────────────
  final _bridge = ServiceManagerBridge();
  StreamSubscription<ServiceTestEvent>? _eventSub;
  String? _testId;
  _Phase _phase = _Phase.idle;
  String? _errorMessage;
  Duration _connectionDuration = Duration.zero;
  Timer? _connTimer;

  // ── Transcript ────────────────────────────────────────────────────────────
  final List<AgentMessage> _messages = [];

  // ── Logs ──────────────────────────────────────────────────────────────────
  final List<String> _logs = [];
  bool _logExpanded = true;

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
    if (_selected?.vendor == 'polychat') _loadPolychatAgents();
  }

  @override
  void dispose() {
    _connTimer?.cancel();
    _eventSub?.cancel();
    final tid = _testId;
    if (tid != null) {
      _bridge.testAstDisconnect(tid);
      _bridge.releaseTest(tid);
    }
    super.dispose();
  }

  // ── PolyChat agent picker ─────────────────────────────────────────────────

  Future<void> _loadPolychatAgents() async {
    final all = await _db.getAllAgents();
    final agents = all.where((a) {
      if (a.type != 'ast-translate') return false;
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        final tags = (cfg['tags'] as List?)?.cast<String>() ?? const [];
        final agentId = cfg['agentId'] as String?;
        return tags.contains('polychat') &&
            agentId != null &&
            agentId.isNotEmpty;
      } catch (_) {
        return false;
      }
    }).toList();
    if (!mounted) return;
    setState(() {
      _polychatAgents = agents;
      _selectedAgent = agents.isNotEmpty ? agents.first : null;
    });
  }

  void _onServiceChanged(ServiceConfigDto svc) {
    setState(() {
      _selected = svc;
      _selectedAgent = null;
      _polychatAgents = const [];
    });
    if (svc.vendor == 'polychat') _loadPolychatAgents();
  }

  // ── Connect / disconnect ──────────────────────────────────────────────────

  Future<void> _connect() async {
    final svc = _selected;
    if (svc == null) return;
    final vendor = svc.vendor;

    if (vendor == 'polychat' && _selectedAgent == null) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage =
            '请先选择一个 PolyChat Agent（到「设置 → PolyChat 平台」同步）';
      });
      return;
    }

    final tid = 'ast_test_${DateTime.now().millisecondsSinceEpoch}';
    _connTimer?.cancel();
    _connectionDuration = Duration.zero;
    setState(() {
      _phase = _Phase.connecting;
      _errorMessage = null;
      _messages.clear();
      _logs.clear();
      _testId = tid;
    });
    _log('→ testAstConnect tid=$tid vendor=$vendor $_srcLang→$_dstLang');

    _eventSub?.cancel();
    _eventSub = _bridge.eventStream.where((e) => e.testId == tid).listen(
      _onEvent,
      onError: (e) {
        _log('‼ stream error: $e');
        if (mounted) {
          setState(() {
            _phase = _Phase.error;
            _errorMessage = e.toString();
          });
        }
      },
    );

    try {
      final overrides = <String, dynamic>{
        'srcLang': _srcLang,
        'dstLang': _dstLang,
      };
      if (vendor == 'polychat') {
        final agentCfg =
            jsonDecode(_selectedAgent!.configJson) as Map<String, dynamic>;
        overrides['agentId'] = agentCfg['agentId'];
      }
      await _bridge.testAstConnect(
        testId: tid,
        serviceId: svc.id,
        extraConfigJson: jsonEncode(overrides),
      );
      // 服务测试 = 本地麦克风路径；底层 connected 事件到达后再开 startAudio。
    } catch (e) {
      _log('‼ connect exception: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _testId = null;
        });
      }
    }
  }

  Future<void> _hangUp() async {
    _connTimer?.cancel();
    _eventSub?.cancel();
    _eventSub = null;
    final tid = _testId;
    _testId = null;
    if (tid != null) {
      _log('→ testAstStopAudio + testAstDisconnect');
      try { await _bridge.testAstStopAudio(tid); } catch (_) {}
      try { await _bridge.testAstDisconnect(tid); } catch (_) {}
      try { await _bridge.releaseTest(tid); } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _errorMessage = null;
      _messages.clear();
    });
  }

  void _startConnTimer() {
    _connTimer?.cancel();
    _connTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(
          () => _connectionDuration += const Duration(seconds: 1),
        );
      }
    });
  }

  // ── Event handling ────────────────────────────────────────────────────────

  void _onEvent(ServiceTestEvent event) {
    if (!mounted) return;
    if (event is! AstTestEvent) return;
    _log('← ${_summarize(event)}');
    setState(() {
      switch (event.kind) {
        case AstTestEventKind.connected:
          if (_phase != _Phase.connected) _startConnTimer();
          _phase = _Phase.connected;
          // 服务测试默认 self-mic 路径：连上后立即开本地麦克风往火山推 PCM，
          // 否则服务端 8 秒收不到帧会主动断开。
          final tid = _testId;
          if (tid != null) {
            _log('→ testAstStartAudio');
            _bridge.testAstStartAudio(tid).catchError((e) {
              _log('‼ startAudio failed: $e');
            });
          }
        case AstTestEventKind.sourceSubtitle:
          final txt = event.text ?? '';
          if (txt.isNotEmpty) _upsertSourcePartial(txt);
        case AstTestEventKind.translatedSubtitle:
          final txt = event.text ?? '';
          if (txt.isNotEmpty) _appendTranslation(txt);
        case AstTestEventKind.disconnected:
          _connTimer?.cancel();
          if (_phase != _Phase.error) _phase = _Phase.idle;
        case AstTestEventKind.error:
          _phase = _Phase.error;
          _connTimer?.cancel();
          _errorMessage =
              '[${event.errorCode ?? 'error'}] ${event.errorMessage ?? ''}';
        case AstTestEventKind.speechStart:
        case AstTestEventKind.stateChanged:
          break;
      }
    });
  }

  // ── Transcript helpers ────────────────────────────────────────────────────

  void _upsertSourcePartial(String text) {
    final idx = _messages.lastIndexWhere(
      (m) => m.role == 'user' && m.status == 'streaming',
    );
    if (idx == -1) {
      _messages.add(
        AgentMessage(
          id: 's_${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: text,
          status: 'streaming',
          detectedLang: _srcLang,
        ),
      );
    } else {
      _messages[idx].content = text;
    }
  }

  /// AST native 端把 sourceSubtitle / translatedSubtitle 都按"累计快照"派发
  /// （见 ServiceTestRunner.buildAstTestCallback），所以这里直接整体覆盖即可。
  void _appendTranslation(String full) {
    final idx = _messages.lastIndexWhere(
      (m) => m.role == 'user' &&
          (m.status == 'streaming' ||
              m.status == 'pending' ||
              m.translatedContent != null),
    );
    if (idx == -1) {
      _messages.add(
        AgentMessage(
          id: 's_${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: '',
          status: 'streaming',
          detectedLang: _srcLang,
          translatedContent: full,
        ),
      );
    } else {
      _messages[idx].translatedContent = full;
    }
  }

  // ── Logging ───────────────────────────────────────────────────────────────

  void _log(String line) {
    if (!mounted) return;
    final ts = DateTime.now();
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    final ss = ts.second.toString().padLeft(2, '0');
    final ms = ts.millisecond.toString().padLeft(3, '0');
    setState(() {
      _logs.add('$hh:$mm:$ss.$ms  $line');
      if (_logs.length > 200) _logs.removeRange(0, _logs.length - 200);
    });
  }

  String _summarize(AstTestEvent e) {
    final t = e.text ?? '';
    final clipped = t.isEmpty
        ? ''
        : ' "${t.substring(0, t.length > 40 ? 40 : t.length)}"';
    return switch (e.kind) {
      AstTestEventKind.connected => 'connected',
      AstTestEventKind.sourceSubtitle => 'src$clipped',
      AstTestEventKind.translatedSubtitle => 'trans$clipped',
      AstTestEventKind.speechStart => 'speechStart',
      AstTestEventKind.stateChanged => 'state=${e.state ?? ''}',
      AstTestEventKind.disconnected => 'disconnected',
      AstTestEventKind.error =>
        'error [${e.errorCode ?? ''}] ${e.errorMessage ?? ''}',
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.services.isEmpty || _selected == null) {
      return const SizedBox.shrink();
    }
    final isActive = _phase != _Phase.idle;
    final isConnecting = _phase == _Phase.connecting;
    final isConnected = _phase == _Phase.connected;
    final isError = _phase == _Phase.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _langPickerRow(isActive),
        const SizedBox(height: 10),
        _header(isActive: isActive, isConnecting: isConnecting),
        if (_selected!.vendor == 'polychat') ...[
          const SizedBox(height: 8),
          _polychatAgentSection(isActive),
        ],
        if (isActive) ...[
          const SizedBox(height: 10),
          _statusBar(isConnected: isConnected, isError: isError),
        ],
        if (isConnected) ...[
          const SizedBox(height: 6),
          _metaBar(),
        ],
        const SizedBox(height: 10),
        _chatArea(),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          _errorBox(_errorMessage!),
        ],
        const SizedBox(height: 10),
        TestLogPanel(
          logs: _logs,
          expanded: _logExpanded,
          onToggle: () => setState(() => _logExpanded = !_logExpanded),
          onClear: () => setState(() => _logs.clear()),
        ),
      ],
    );
  }

  Widget _langPickerRow(bool disabled) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LangDropdown(
              label: '源语言',
              value: _srcLang,
              enabled: !disabled,
              onChanged: (v) => setState(() => _srcLang = v),
            ),
          ),
          GestureDetector(
            onTap: disabled
                ? null
                : () => setState(() {
                      final t = _srcLang;
                      _srcLang = _dstLang;
                      _dstLang = t;
                    }),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color:
                        const Color(0xFF0EA5E9).withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.swap_horiz,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
          Expanded(
            child: _LangDropdown(
              label: '目标语言',
              value: _dstLang,
              enabled: !disabled,
              onChanged: (v) => setState(() => _dstLang = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header({required bool isActive, required bool isConnecting}) {
    return Row(
      children: [
        Expanded(
          child: _Dropdown(
            value: _selected!.name,
            items: widget.services.map((s) => s.name).toList(),
            enabled: !isActive,
            onChanged: (v) => _onServiceChanged(
              widget.services.firstWhere((s) => s.name == v),
            ),
          ),
        ),
        const SizedBox(width: 8),
        isActive
            ? _PillButton(
                label: isConnecting ? '...' : '挂断',
                color: AppTheme.danger,
                onTap: isConnecting ? null : _hangUp,
              )
            : _PillButton(
                label: '接通',
                color: const Color(0xFF0EA5E9),
                onTap: _connect,
              ),
      ],
    );
  }

  Widget _polychatAgentSection(bool isActive) {
    if (_polychatAgents.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: const Row(children: [
          Icon(Icons.info_outline, size: 14, color: Color(0xFF9A3412)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '尚未同步 PolyChat Agent。请到「设置 → PolyChat 平台」填写凭证并同步。',
              style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
            ),
          ),
        ]),
      );
    }
    return Row(children: [
      const Text(
        'Agent',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppTheme.text2,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _Dropdown(
          value: _selectedAgent?.name ?? _polychatAgents.first.name,
          items: _polychatAgents.map((a) => a.name).toList(),
          enabled: !isActive,
          onChanged: (v) => setState(
            () => _selectedAgent =
                _polychatAgents.firstWhere((a) => a.name == v),
          ),
        ),
      ),
    ]);
  }

  Widget _statusBar({required bool isConnected, required bool isError}) {
    final color = isError
        ? AppTheme.danger
        : isConnected
            ? AppTheme.success
            : AppTheme.warning;
    final label = isError
        ? '错误'
        : isConnected
            ? '已连接'
            : '正在建立连接...';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaBar() {
    final translated =
        _messages.where((m) => m.translatedContent != null).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF7DD3FC)),
      ),
      child: Row(
        children: [
          const Icon(Icons.translate, size: 13, color: Color(0xFF0369A1)),
          const SizedBox(width: 6),
          Text(
            'WebRTC 已连接 · 已翻译 $translated 句',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0C4A6E),
            ),
          ),
          const Spacer(),
          Text(
            '连接时长 ${_fmt(_connectionDuration)}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF0C4A6E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatArea() {
    if (_messages.isEmpty) {
      return Container(
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Text(
          _phase == _Phase.idle ? '点击"接通"开始端到端翻译' : '等待语音输入…',
          style: const TextStyle(fontSize: 12, color: AppTheme.text2),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      constraints: const BoxConstraints(maxHeight: 360, minHeight: 160),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shrinkWrap: true,
        reverse: true,
        itemCount: _messages.length,
        itemBuilder: (_, i) {
          final m = _messages[_messages.length - 1 - i];
          return MessageBubble(
            message: m,
            agentName: 'AST',
            isTranslateMode: true,
            srcLang: _srcLang,
            dstLang: _dstLang,
          );
        },
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, size: 14, color: AppTheme.danger),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            msg,
            style: const TextStyle(fontSize: 11, color: AppTheme.danger),
          ),
        ),
      ]),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Local UI primitives ──────────────────────────────────────────────────────

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.enabled,
    required this.onChanged,
  });
  final String value;
  final List<String> items;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled ? Colors.white : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          onChanged: enabled ? (v) => v != null ? onChanged(v) : null : null,
          items: items
              .map((n) => DropdownMenuItem(
                    value: n,
                    child: Text(
                      n,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.text1,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }
}

class _LangDropdown extends StatelessWidget {
  const _LangDropdown({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final String label;
  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppTheme.text2),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 32,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              onChanged:
                  enabled ? (v) => v != null ? onChanged(v) : null : null,
              items: _langMap.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(
                          e.value,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.text1,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: disabled ? color.withValues(alpha: 0.4) : color,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
