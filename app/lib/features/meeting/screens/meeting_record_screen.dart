import 'dart:ui' as ui;

import 'package:audio_waveforms/audio_waveforms.dart' as wav;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../providers/recorder_provider.dart';

class MeetingRecordScreen extends ConsumerStatefulWidget {
  const MeetingRecordScreen({super.key});

  @override
  ConsumerState<MeetingRecordScreen> createState() =>
      _MeetingRecordScreenState();
}

class _MeetingRecordScreenState extends ConsumerState<MeetingRecordScreen> {
  late final TextEditingController _titleCtrl;
  bool _editingTitle = false;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final s = ref.read(recorderProvider);
    _titleCtrl = TextEditingController(text: s.title);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    final state = ref.read(recorderProvider);
    if (!state.hasStarted) return true;
    final action = await showDialog<_ExitAction>(
      context: context,
      builder: (ctx) => _ExitConfirmDialog(),
    );
    if (action == null || action == _ExitAction.cancel) return false;

    switch (action) {
      case _ExitAction.saveAndEnd:
        final notifier = ref.read(recorderProvider.notifier);
        notifier.setTitle(_titleCtrl.text.trim());
        final saved = await notifier.stopAndSave();
        if (saved != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已保存会议')),
          );
        }
        return true;
      case _ExitAction.discard:
        final ok = await _confirmDiscard();
        if (!ok) return false;
        await ref.read(recorderProvider.notifier).discard();
        return true;
      case _ExitAction.background:
        // 占位 — 真实后台录音需 foreground service / NSNotificationCenter
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已切换到后台继续录音（占位）')),
          );
        }
        return true;
      case _ExitAction.cancel:
        return false;
    }
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认丢弃录音？'),
        content: const Text('当前录音不会保存，丢弃后无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('丢弃', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(recorderProvider);
    final svc = ref.watch(recorderServiceProvider);
    final colors = context.appColors;

    ref.listen<RecorderState>(recorderProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
        ref.read(recorderProvider.notifier).clearError();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmExit();
        if (ok && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: () async {
              final ok = await _confirmExit();
              if (ok && context.mounted) context.pop();
            },
          ),
          title: _editingTitle
              ? TextField(
                  controller: _titleCtrl,
                  focusNode: _focus,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: '会议标题',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 17),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) {
                    ref.read(recorderProvider.notifier).setTitle(v.trim());
                    setState(() => _editingTitle = false);
                  },
                )
              : GestureDetector(
                  onTap: () {
                    setState(() => _editingTitle = true);
                    _focus.requestFocus();
                  },
                  child: Text(state.title),
                ),
          actions: [
            if (_editingTitle)
              IconButton(
                icon: const Icon(Icons.check),
                onPressed: () {
                  ref
                      .read(recorderProvider.notifier)
                      .setTitle(_titleCtrl.text.trim());
                  setState(() => _editingTitle = false);
                },
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _AudioTypeBadge(
                    type: state.audioType,
                    onChanged: state.hasStarted
                        ? null
                        : (t) => ref
                            .read(recorderProvider.notifier)
                            .setAudioType(t),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 200,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(builder: (ctx, c) {
                    return wav.AudioWaveforms(
                      size: Size(c.maxWidth, 200),
                      recorderController: svc.waveform,
                      backgroundColor: Colors.transparent,
                      waveStyle: wav.WaveStyle(
                        waveColor: colors.text1,
                        waveThickness: 1.5,
                        spacing: 3,
                        showMiddleLine: state.isRecording,
                        middleLineColor:
                            Colors.redAccent.withValues(alpha: 0.9),
                        middleLineThickness: 1,
                        showTop: true,
                        showBottom: true,
                        extendWaveform: true,
                        scaleFactor: 90,
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _formatTime(state.elapsedMs),
                style: TextStyle(
                  fontSize: 48,
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                  color: colors.text1,
                ),
              ),
              const Spacer(),
              _BottomBar(
                state: state,
                onMark: () =>
                    ref.read(recorderProvider.notifier).toggleMark(),
                onToggle: () =>
                    ref.read(recorderProvider.notifier).toggle(),
                onFinish: () => _onFinish(),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onFinish() async {
    if (!ref.read(recorderProvider).hasStarted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开始录音')),
      );
      return;
    }
    // 暂停录音再保存，避免编辑标题时丢音
    final notifier = ref.read(recorderProvider.notifier);
    if (ref.read(recorderProvider).isRecording) {
      await notifier.pause();
    }
    if (!mounted) return;
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => _SaveDialog(initial: _titleCtrl.text),
    );
    if (next == null) {
      // 用户取消 — 继续录音
      if (mounted) {
        await ref.read(recorderProvider.notifier).resume();
      }
      return;
    }
    notifier.setTitle(next);
    final m = await notifier.stopAndSave();
    if (m != null && mounted) {
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存会议')),
      );
    }
  }

  static String _formatTime(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:$mm:$ss';
    }
    return '$mm:$ss';
  }
}

class _AudioTypeBadge extends StatelessWidget {
  const _AudioTypeBadge({required this.type, this.onChanged});
  final MeetingAudioType type;
  final ValueChanged<MeetingAudioType>? onChanged;

  @override
  Widget build(BuildContext context) {
    final config = _config(type);
    final disabled = onChanged == null;
    return InkWell(
      onTap: disabled
          ? null
          : () async {
              final next = await showModalBottomSheet<MeetingAudioType>(
                context: context,
                showDragHandle: true,
                builder: (ctx) => _TypePickerSheet(current: type),
              );
              if (next != null) onChanged!(next);
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: config.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 16, color: config.color),
            const SizedBox(width: 6),
            Text(config.label,
                style: TextStyle(
                    color: config.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            if (!disabled) ...[
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, size: 14, color: config.color),
            ],
          ],
        ),
      ),
    );
  }

  static _AudioTypeConfig _config(MeetingAudioType t) => switch (t) {
        MeetingAudioType.live =>
          const _AudioTypeConfig(Icons.mic_rounded, '实时录音', Colors.red),
        MeetingAudioType.audioVideo => const _AudioTypeConfig(
            Icons.videocam_rounded, '音视频', Colors.green),
        MeetingAudioType.call => const _AudioTypeConfig(
            Icons.phone_in_talk_rounded, '通话', Colors.orange),
      };
}

class _AudioTypeConfig {
  const _AudioTypeConfig(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
}

class _TypePickerSheet extends StatelessWidget {
  const _TypePickerSheet({required this.current});
  final MeetingAudioType current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in MeetingAudioType.values)
            ListTile(
              leading: Icon(_AudioTypeBadge._config(t).icon,
                  color: _AudioTypeBadge._config(t).color),
              title: Text(_AudioTypeBadge._config(t).label),
              trailing: t == current
                  ? const Icon(Icons.check, color: AppTheme.primary)
                  : null,
              onTap: () => Navigator.pop(context, t),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.onMark,
    required this.onToggle,
    required this.onFinish,
  });
  final RecorderState state;
  final VoidCallback onMark;
  final VoidCallback onToggle;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(
            colors: colors,
            radius: 32,
            onTap: onMark,
            child: Icon(
              state.marked ? Icons.star_rounded : Icons.star_border_rounded,
              size: 30,
              color: state.marked ? Colors.orange : Colors.grey,
            ),
          ),
          _circleBtn(
            colors: colors,
            radius: 40,
            onTap: onToggle,
            child: Icon(
              state.isRecording
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 40,
              color: Colors.red,
            ),
          ),
          _circleBtn(
            colors: colors,
            radius: 32,
            onTap: onFinish,
            child:
                const Icon(Icons.check_rounded, size: 30, color: Colors.green),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn({
    required AppColors colors,
    required double radius,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Material(
      shape: const CircleBorder(),
      color: colors.surface,
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: Center(child: child),
        ),
      ),
    );
  }
}

enum _ExitAction { saveAndEnd, discard, background, cancel }

class _ExitConfirmDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppTheme.primary, size: 28),
            ),
            const SizedBox(height: 12),
            const Text('退出录音',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('请选择离开后的操作',
                style: TextStyle(
                    fontSize: 13, color: context.appColors.text2)),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () =>
                    Navigator.pop(context, _ExitAction.saveAndEnd),
                child: const Text('结束录音并保存'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.pop(context, _ExitAction.background),
                child: const Text('后台继续录音'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                onPressed: () => Navigator.pop(context, _ExitAction.discard),
                child: const Text('结束录音不保存'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, _ExitAction.cancel),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({required this.initial});
  final String initial;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('保存会议'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 50,
        decoration: const InputDecoration(
          hintText: '会议标题',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
