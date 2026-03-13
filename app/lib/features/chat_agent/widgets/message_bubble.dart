import 'package:flutter/material.dart';
import '../providers/chat_agent_provider.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final isCancelled = message.status == 'cancelled';
    final isError = message.status == 'error';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? colorScheme.primaryContainer
              : isCancelled
                  ? colorScheme.surfaceContainerHighest
                  : isError
                      ? colorScheme.errorContainer
                      : colorScheme.secondaryContainer,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.status == 'streaming')
              _StreamingText(content: message.content)
            else
              Text(
                message.content.isEmpty && isCancelled
                    ? '（已取消）'
                    : message.content,
                style: TextStyle(
                  color: isCancelled
                      ? colorScheme.onSurfaceVariant
                      : isError
                          ? colorScheme.onErrorContainer
                          : isUser
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSecondaryContainer,
                  fontStyle: isCancelled ? FontStyle.italic : FontStyle.normal,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StreamingText extends StatefulWidget {
  const _StreamingText({required this.content});
  final String content;

  @override
  State<_StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<_StreamingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursor;

  @override
  void initState() {
    super.initState();
    _cursor = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _cursor,
      builder: (_, __) => Text(
        '${widget.content}${_cursor.value > 0.5 ? '▋' : ' '}',
        style: TextStyle(color: Theme.of(context).colorScheme.onSecondaryContainer),
      ),
    );
  }
}
