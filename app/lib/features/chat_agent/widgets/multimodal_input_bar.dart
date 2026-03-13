import 'package:flutter/material.dart';

/// 统一输入栏 — 短语音 / 文字 / 通话 三态
class MultimodalInputBar extends StatefulWidget {
  const MultimodalInputBar({
    super.key,
    required this.inputMode,
    required this.onModeChanged,
    required this.onTextSubmit,
    required this.onVoiceStart,
    required this.onVoiceEnd,
  });

  final String inputMode; // 'text' | 'short_voice' | 'call'
  final ValueChanged<String> onModeChanged;
  final ValueChanged<String> onTextSubmit;
  final VoidCallback onVoiceStart;
  final VoidCallback onVoiceEnd;

  @override
  State<MultimodalInputBar> createState() => _MultimodalInputBarState();
}

class _MultimodalInputBarState extends State<MultimodalInputBar> {
  final _textController = TextEditingController();
  bool _isRecording = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 模式切换按钮
            _ModeToggle(
              current: widget.inputMode,
              onChanged: widget.onModeChanged,
            ),
            const SizedBox(width: 8),
            // 输入区域
            Expanded(child: _buildInput()),
            const SizedBox(width: 8),
            // 发送 / 通话按钮
            _buildAction(),
          ],
        ),
      ),
    );
  }

  Widget _buildInput() {
    switch (widget.inputMode) {
      case 'short_voice':
        return GestureDetector(
          onLongPressStart: (_) {
            setState(() => _isRecording = true);
            widget.onVoiceStart();
          },
          onLongPressEnd: (_) {
            setState(() => _isRecording = false);
            widget.onVoiceEnd();
          },
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: _isRecording
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
            ),
            alignment: Alignment.center,
            child: Text(
              _isRecording ? '松手发送' : '按住说话',
              style: TextStyle(
                color: _isRecording
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      case 'call':
        return Container(
          height: 44,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          child: Text(
            '通话模式监听中…',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onTertiaryContainer),
          ),
        );
      default: // text
        return TextField(
          controller: _textController,
          decoration: InputDecoration(
            hintText: '发送消息…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            isDense: true,
          ),
          onSubmitted: _submit,
          textInputAction: TextInputAction.send,
        );
    }
  }

  Widget _buildAction() {
    if (widget.inputMode == 'call') {
      return IconButton.filled(
        onPressed: () => widget.onModeChanged('text'),
        icon: const Icon(Icons.call_end),
        style: IconButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
      );
    }
    if (widget.inputMode == 'text') {
      return IconButton.filled(
        onPressed: () {
          final text = _textController.text.trim();
          if (text.isNotEmpty) _submit(text);
        },
        icon: const Icon(Icons.send),
      );
    }
    return const SizedBox.shrink();
  }

  void _submit(String text) {
    if (text.isEmpty) return;
    widget.onTextSubmit(text);
    _textController.clear();
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.current, required this.onChanged});
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      icon: Icon(_modeIcon(current)),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'text', child: Text('文字模式')),
        PopupMenuItem(value: 'short_voice', child: Text('语音模式')),
        PopupMenuItem(value: 'call', child: Text('通话模式')),
      ],
    );
  }

  IconData _modeIcon(String mode) => switch (mode) {
        'short_voice' => Icons.mic_none,
        'call' => Icons.call,
        _ => Icons.keyboard_alt_outlined,
      };
}
