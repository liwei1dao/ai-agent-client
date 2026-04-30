import 'dart:async';
import 'dart:convert';

import 'package:agents_server/agents_server.dart';
import 'package:flutter/material.dart';
import 'package:local_db/local_db.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../shared/themes/app_theme.dart';
import '../../chat/providers/agent_screen_provider.dart' show AgentMessage;
import '../../chat/widgets/chat_screen_shared.dart'
    show statusColor, statusLabel;
import '../../chat/widgets/message_bubble.dart';
import 'test_log_panel.dart';

/// Shared STS test session panel. Reused by every STS vendor (volcengine,
/// polychat, ...). Handles its own selection UI, connection lifecycle and
/// event-stream wiring; renders chat bubbles with [MessageBubble] and a
/// collapsible debug log identical to the production chat screen.
class StsTestPanel extends StatefulWidget {
  const StsTestPanel({super.key, required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<StsTestPanel> createState() => _StsTestPanelState();
}

enum _Phase { idle, connecting, connected, error }

class _StsTestPanelState extends State<StsTestPanel> {
  // ── Selection ─────────────────────────────────────────────────────────────
  ServiceConfigDto? _selected;
  List<AgentDto> _polychatAgents = const [];
  AgentDto? _selectedAgent;
  final _db = LocalDbBridge();

  // ── Session ───────────────────────────────────────────────────────────────
  final _bridge = AgentsServerBridge();
  StreamSubscription<AgentEvent>? _eventSub;
  String? _sessionId;
  _Phase _phase = _Phase.idle;
  AgentSessionState _sessionState = AgentSessionState.idle;
  String? _errorMessage;
  Duration _connectionDuration = Duration.zero;
  Timer? _connTimer;

  // ── Transcript ────────────────────────────────────────────────────────────
  final List<AgentMessage> _messages = [];
  String _currentAssistantId = '';

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
    if (_sessionId != null) _bridge.stopAgent(_sessionId!);
    super.dispose();
  }

  // ── PolyChat agent picker ─────────────────────────────────────────────────

  Future<void> _loadPolychatAgents() async {
    final all = await _db.getAllAgents();
    final agents = all.where((a) {
      if (a.type != 'sts-chat') return false;
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

    // STS 测试默认走 self-mic 路径，必须先拿到 RECORD_AUDIO 运行时权限。
    // 没有权限的话连上后 startAudio 会被原生 AudioFlinger 拒掉。
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;
    if (!micStatus.isGranted) {
      setState(() {
        _phase = _Phase.error;
        _errorMessage = micStatus.isPermanentlyDenied
            ? '麦克风权限被永久拒绝，请前往系统设置开启'
            : '需要麦克风权限才能进行 STS 测试';
      });
      return;
    }

    final sid = 'sts_test_${DateTime.now().millisecondsSinceEpoch}';
    _connTimer?.cancel();
    _connectionDuration = Duration.zero;
    setState(() {
      _phase = _Phase.connecting;
      _sessionState = AgentSessionState.idle;
      _errorMessage = null;
      _messages.clear();
      _logs.clear();
      _currentAssistantId = '';
      _sessionId = sid;
    });
    _log('→ createAgent sid=$sid vendor=$vendor');

    _eventSub?.cancel();
    _eventSub = _bridge.eventStream.where((e) => e.sessionId == sid).listen(
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
      String stsConfigJson = svc.configJson;
      if (vendor == 'polychat') {
        final base = jsonDecode(svc.configJson) as Map<String, dynamic>;
        final agentCfg =
            jsonDecode(_selectedAgent!.configJson) as Map<String, dynamic>;
        base['agentId'] = agentCfg['agentId'];
        stsConfigJson = jsonEncode(base);
      }

      await _bridge.createAgent(
        agentId: sid,
        agentType: 'sts-chat',
        inputMode: 'text',
        stsVendor: vendor,
        stsConfigJson: stsConfigJson,
      );
      _log('→ connectService');
      await _bridge.connectService(sid);
      _log('→ setInputMode=call');
      await _bridge.setInputMode(sid, 'call');
    } catch (e) {
      _log('‼ connect exception: $e');
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _sessionId = null;
        });
      }
    }
  }

  Future<void> _hangUp() async {
    _connTimer?.cancel();
    _eventSub?.cancel();
    _eventSub = null;
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      _log('→ stopAgent');
      try {
        await _bridge.stopAgent(sid);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.idle;
      _sessionState = AgentSessionState.idle;
      _errorMessage = null;
      _messages.clear();
      _currentAssistantId = '';
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

  // ── Event → message / log ─────────────────────────────────────────────────

  void _onEvent(AgentEvent event) {
    if (!mounted) return;
    _log('← ${_summarize(event)}');
    setState(() {
      switch (event) {
        case ServiceConnectionStateEvent(
            :final connectionState,
            :final errorMessage,
          ):
          switch (connectionState) {
            case ServiceConnectionState.connected:
              if (_phase != _Phase.connected) _startConnTimer();
              _phase = _Phase.connected;
            case ServiceConnectionState.connecting:
              _phase = _Phase.connecting;
            case ServiceConnectionState.error:
              _connTimer?.cancel();
              _phase = _Phase.error;
              _errorMessage = errorMessage ?? '连接失败';
            case ServiceConnectionState.disconnected:
              _connTimer?.cancel();
              if (_phase != _Phase.error) _phase = _Phase.idle;
          }
        case SessionStateEvent(:final state):
          _sessionState = state;
          if (_phase == _Phase.connecting) {
            _startConnTimer();
            _phase = _Phase.connected;
          }
          if (state == AgentSessionState.error) {
            _phase = _Phase.error;
            _connTimer?.cancel();
          }
        case SttEvent(:final kind, :final text):
          final txt = text ?? '';
          if (kind == SttEventKind.partialResult && txt.isNotEmpty) {
            _upsertUserPartial(txt);
          } else if (kind == SttEventKind.finalResult && txt.isNotEmpty) {
            _finalizeUser(txt);
          }
        case LlmEvent(:final kind, :final textDelta, :final fullText):
          if (kind == LlmEventKind.firstToken && (textDelta ?? '').isNotEmpty) {
            _appendAssistant(textDelta!);
          } else if (kind == LlmEventKind.done) {
            final full = fullText ?? '';
            if (full.isNotEmpty) _finalizeAssistant(full);
            _currentAssistantId = '';
          } else if (kind == LlmEventKind.error) {
            _currentAssistantId = '';
          }
        case AgentErrorEvent(:final errorCode, :final message):
          _phase = _Phase.error;
          _errorMessage = '[$errorCode] $message';
        default:
          break;
      }
    });
  }

  // ── Transcript helpers ────────────────────────────────────────────────────

  void _upsertUserPartial(String text) {
    final idx = _messages.lastIndexWhere(
      (m) => m.role == 'user' && m.status == 'streaming',
    );
    if (idx == -1) {
      _messages.add(
        AgentMessage(
          id: 'u_${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: text,
          status: 'streaming',
        ),
      );
    } else {
      _messages[idx].content = text;
    }
  }

  void _finalizeUser(String text) {
    final idx = _messages.lastIndexWhere(
      (m) => m.role == 'user' && m.status == 'streaming',
    );
    if (idx != -1) {
      _messages[idx].content = text;
      _messages[idx].status = 'done';
    } else {
      _messages.add(
        AgentMessage(
          id: 'u_${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: text,
          status: 'done',
        ),
      );
    }
  }

  void _appendAssistant(String delta) {
    if (_currentAssistantId.isEmpty) {
      _currentAssistantId = 'a_${DateTime.now().microsecondsSinceEpoch}';
      _messages.add(
        AgentMessage(
          id: _currentAssistantId,
          role: 'assistant',
          content: delta,
          status: 'streaming',
        ),
      );
    } else {
      final idx = _messages.indexWhere((m) => m.id == _currentAssistantId);
      if (idx != -1) _messages[idx].content += delta;
    }
  }

  void _finalizeAssistant(String full) {
    if (_currentAssistantId.isEmpty) {
      _messages.add(
        AgentMessage(
          id: 'a_${DateTime.now().microsecondsSinceEpoch}',
          role: 'assistant',
          content: full,
          status: 'done',
        ),
      );
    } else {
      final idx = _messages.indexWhere((m) => m.id == _currentAssistantId);
      if (idx != -1) {
        _messages[idx].content = full;
        _messages[idx].status = 'done';
      }
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

  String _summarize(AgentEvent e) => switch (e) {
        ServiceConnectionStateEvent(
          :final connectionState,
          :final errorMessage,
        ) =>
          'ConnState=${connectionState.name}${errorMessage == null ? '' : ' err=$errorMessage'}',
        SessionStateEvent(:final state) => 'Session=${state.name}',
        SttEvent(:final kind, :final text) =>
          'Stt.${kind.name}${_clip(text)}',
        LlmEvent(:final kind, :final textDelta) =>
          'Llm.${kind.name}${_clip(textDelta, prefix: ' +')}',
        AgentErrorEvent(:final errorCode, :final message) =>
          'Error [$errorCode] $message',
        _ => e.runtimeType.toString(),
      };

  String _clip(String? s, {String prefix = ' '}) {
    final t = s ?? '';
    if (t.isEmpty) return '';
    final n = t.length > 40 ? 40 : t.length;
    return '$prefix"${t.substring(0, n)}"';
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
                color: const Color(0xFF4A42D9),
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
            ? statusColor(_sessionState)
            : AppTheme.warning;
    final label = isError
        ? '错误'
        : isConnected
            ? statusLabel(_sessionState)
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link, size: 13, color: Color(0xFF047857)),
          const SizedBox(width: 6),
          const Text(
            'WebRTC 已连接',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF065F46),
            ),
          ),
          const Spacer(),
          Text(
            '连接时长 ${_fmt(_connectionDuration)}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF065F46),
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
          _phase == _Phase.idle ? '点击"接通"开始语音对话' : '等待语音输入…',
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
          return MessageBubble(message: m, agentName: 'STS');
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

// ── Local UI primitives (kept private so the panel file stays self-contained)

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
