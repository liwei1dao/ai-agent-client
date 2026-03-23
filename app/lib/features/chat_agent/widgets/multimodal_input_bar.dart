import 'dart:async';
import 'package:flutter/material.dart';
import 'package:agent_runtime/agent_runtime.dart';
import '../../../shared/themes/app_theme.dart';

class MultimodalInputBar extends StatefulWidget {
  const MultimodalInputBar({
    super.key,
    required this.inputMode,
    required this.onModeChanged,
    required this.onTextSubmit,
    required this.onVoiceStart,
    required this.onVoiceEnd,
    this.onVoiceCancel,
    this.onCallToggle,
    this.partialText = '',
    this.lockCallMode = false,
    this.sessionState = AgentSessionState.idle,
  });

  /// 'text' | 'short_voice' | 'call'
  final String inputMode;
  final bool lockCallMode; // STS agent: 锁定通话模式，隐藏模式切换按钮
  final AgentSessionState sessionState;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onTextSubmit;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;
  final VoidCallback? onVoiceCancel;
  final VoidCallback? onCallToggle;
  final String partialText;

  @override
  State<MultimodalInputBar> createState() => _MultimodalInputBarState();
}

class _MultimodalInputBarState extends State<MultimodalInputBar> {
  final _textCtrl = TextEditingController();
  bool _recording = false;
  bool _cancelZone = false; // 上滑进入取消区域

  // ── 通话计时器 ──
  Timer? _callTimer;
  int _callSeconds = 0;

  @override
  void didUpdateWidget(covariant MultimodalInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 进入通话模式时启动计时器
    if (widget.inputMode == 'call' && oldWidget.inputMode != 'call') {
      _startCallTimer();
    }
    // 退出通话模式时停止计时器
    if (widget.inputMode != 'call' && oldWidget.inputMode == 'call') {
      _stopCallTimer();
    }
  }

  void _startCallTimer() {
    _callSeconds = 0;
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    _callSeconds = 0;
  }

  String get _callDuration {
    final m = (_callSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_callSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, thickness: 1, color: AppTheme.borderColor),
          switch (widget.inputMode) {
            'short_voice' => _buildVoiceBar(),
            'call' => _buildCallBar(),
            // STS agent 在 text 模式下显示"连接"按钮，普通 agent 显示文本输入
            _ => widget.lockCallMode ? _buildStsConnectBar() : _buildTextBar(),
          },
          SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      ),
    );
  }

  // ── Text mode ──────────────────────────────────────────────────────────────

  Widget _buildTextBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(
        children: [
          _SideBtn(
            onTap: () => widget.onModeChanged('short_voice'),
            child: const Icon(Icons.mic_none, color: AppTheme.text2, size: 20),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      decoration: const InputDecoration(
                        hintText: '继续提问...',
                        hintStyle: TextStyle(color: AppTheme.text2, fontSize: 13),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 13, color: AppTheme.text1),
                      onSubmitted: _submit,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: GestureDetector(
                      onTap: () => _submit(_textCtrl.text),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_upward,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 7),
          _SideBtn(
            onTap: () => widget.onModeChanged('call'),
            child:
                const Icon(Icons.phone_outlined, color: AppTheme.text2, size: 20),
          ),
        ],
      ),
    );
  }

  // ── STS connect mode (lockCallMode + text) ──────────────────────────────────

  Widget _buildStsConnectBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: GestureDetector(
        onTap: () => widget.onModeChanged('call'),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primary, Color(0xFF818CF8)],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.phone_outlined, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text(
                '点击连接语音服务',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Short-voice mode ────────────────────────────────────────────────────────

  Widget _buildVoiceBar() {
    final partial = widget.partialText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_recording && partial.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              partial,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.text1, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              _SideBtn(
                onTap: () => widget.onModeChanged('text'),
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppTheme.text2,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: GestureDetector(
                  onLongPressStart: (_) {
                    setState(() { _recording = true; _cancelZone = false; });
                    widget.onVoiceStart();
                  },
                  onLongPressMoveUpdate: (d) {
                    final entering = d.offsetFromOrigin.dy < -60;
                    if (entering != _cancelZone) {
                      setState(() => _cancelZone = entering);
                    }
                  },
                  onLongPressEnd: (_) {
                    final wasCancelled = _cancelZone;
                    setState(() { _recording = false; _cancelZone = false; });
                    if (wasCancelled) {
                      widget.onVoiceCancel?.call();
                    } else {
                      widget.onVoiceEnd();
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _cancelZone
                            ? [const Color(0xFFEF4444), const Color(0xFFDC2626)]
                            : _recording
                                ? [const Color(0xFFF59E0B), const Color(0xFFEF4444)]
                                : [AppTheme.primary, const Color(0xFF818CF8)],
                      ),
                      borderRadius: BorderRadius.circular(21),
                      boxShadow: [
                        BoxShadow(
                          color: (_cancelZone
                                  ? AppTheme.danger
                                  : _recording
                                      ? AppTheme.warning
                                      : AppTheme.primary)
                              .withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: _recording
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_cancelZone) _WaveBar(),
                              if (!_cancelZone) const SizedBox(width: 8),
                              if (_cancelZone)
                                const Icon(Icons.close, color: Colors.white, size: 16),
                              if (_cancelZone) const SizedBox(width: 6),
                              Text(
                                _cancelZone ? '松开取消' : '松开发送 · 上滑取消',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.mic, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                '按住说话',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              _SideBtn(
                onTap: () => widget.onModeChanged('call'),
                child: const Icon(Icons.phone_outlined,
                    color: AppTheme.text2, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Call mode ───────────────────────────────────────────────────────────────

  Widget _buildCallBar() {
    final isListening = widget.sessionState == AgentSessionState.listening;
    final isPlaying = widget.sessionState == AgentSessionState.playing ||
        widget.sessionState == AgentSessionState.tts;
    final isThinking = widget.sessionState == AgentSessionState.llm ||
        widget.sessionState == AgentSessionState.stt;
    final isError = widget.sessionState == AgentSessionState.error;

    // 状态文本和颜色
    final String statusText;
    final Color statusColor;
    if (isError) {
      statusText = '连接失败';
      statusColor = AppTheme.danger;
    } else if (isPlaying) {
      statusText = 'AI 回复中';
      statusColor = AppTheme.primary;
    } else if (isThinking) {
      statusText = '处理中';
      statusColor = AppTheme.warning;
    } else if (isListening) {
      statusText = '监听中';
      statusColor = AppTheme.success;
    } else {
      statusText = '通话中';
      statusColor = AppTheme.success;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      child: Row(
        children: [
          // 状态指示点（带脉冲动画）
          _PulsingDot(color: statusColor, active: isListening),
          const SizedBox(width: 8),
          // 状态 + 计时器
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusText,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
                Text(_callDuration,
                    style:
                        const TextStyle(fontSize: 10, color: AppTheme.text2)),
              ],
            ),
          ),
          // 麦克风指示器（带音量动画）
          _MicIndicator(active: isListening),
          const SizedBox(width: 10),
          // Hang up
          GestureDetector(
              onTap: () => widget.onModeChanged('text'),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.danger.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.call_end, color: Colors.white, size: 22),
              ),
            ),
        ],
      ),
    );
  }

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    widget.onTextSubmit(text.trim());
    _textCtrl.clear();
  }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

class _SideBtn extends StatelessWidget {
  const _SideBtn({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.bgColor,
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.borderColor),
          ),
          alignment: Alignment.center,
          child: child,
        ),
      );
}

/// 脉冲呼吸动画圆点
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, this.active = false});
  final Color color;
  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.active) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.4 + _ctrl.value * 0.6),
          shape: BoxShape.circle,
          boxShadow: widget.active
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.3 * _ctrl.value),
                    blurRadius: 6,
                    spreadRadius: 2 * _ctrl.value,
                  )
                ]
              : null,
        ),
      ),
    );
  }
}

/// 麦克风指示器 — 监听时显示波形动画，否则显示静态图标
class _MicIndicator extends StatelessWidget {
  const _MicIndicator({this.active = false});
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: active ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
        shape: BoxShape.circle,
        border: active ? Border.all(color: AppTheme.success.withValues(alpha: 0.4)) : null,
      ),
      child: active
          ? Center(child: _MicWaveBar())
          : const Icon(Icons.mic_off_outlined, color: AppTheme.text2, size: 20),
    );
  }
}

/// 麦克风波形动画（模拟音量检测）
class _MicWaveBar extends StatefulWidget {
  @override
  State<_MicWaveBar> createState() => _MicWaveBarState();
}

class _MicWaveBarState extends State<_MicWaveBar>
    with TickerProviderStateMixin {
  static const _barCount = 4;
  static const _baseHeights = [6.0, 12.0, 8.0, 14.0];
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_barCount, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 250 + i * 80),
        value: i / _barCount,
      )..repeat(reverse: true);
    });
    _anims = List.generate(_barCount, (i) => Tween<double>(
      begin: 3.0,
      end: _baseHeights[i],
    ).animate(CurvedAnimation(parent: _controllers[i], curve: Curves.easeInOut)));
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_barCount, (i) => AnimatedBuilder(
        animation: _anims[i],
        builder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 2.5,
          height: _anims[i].value,
          decoration: BoxDecoration(
            color: AppTheme.success,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    );
  }
}

class _WaveBar extends StatefulWidget {
  @override
  State<_WaveBar> createState() => _WaveBarState();
}

class _WaveBarState extends State<_WaveBar> with TickerProviderStateMixin {
  static const _baseHeights = [8.0, 14.0, 10.0, 16.0, 8.0];
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(5, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 300 + i * 60),
        value: i / 5.0, // stagger start position
      )..repeat(reverse: true);
    });
    _anims = List.generate(5, (i) => Tween<double>(
      begin: _baseHeights[i] * 0.3,
      end: _baseHeights[i],
    ).animate(CurvedAnimation(parent: _controllers[i], curve: Curves.easeInOut)));
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (i) => AnimatedBuilder(
        animation: _anims[i],
        builder: (_, __) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 3,
          height: _anims[i].value,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(2)),
        ),
      )),
    );
  }
}
