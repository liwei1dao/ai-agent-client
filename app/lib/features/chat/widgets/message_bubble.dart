import 'package:flutter/material.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/chat_provider.dart';

/// 语言代码 → 显示名称
String _langLabel(String? code) => switch (code) {
      'zh' => '中文',
      'en' => 'English',
      'ja' => '日本語',
      'ko' => '한국어',
      'fr' => 'Français',
      'de' => 'Deutsch',
      'es' => 'Español',
      'ru' => 'Русский',
      'ar' => 'العربية',
      'pt' => 'Português',
      _ => code ?? '',
    };

/// Renders a single chat message bubble.
///
/// In translate mode (AST), when [message.isTranslationPair] is true,
/// renders a translation card with source text in bubble and translation below.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.agentName = 'AI',
    this.isTranslateMode = false,
    this.srcLang = 'zh',
    this.dstLang = 'en',
  });
  final ChatMessage message;
  final String agentName;
  final bool isTranslateMode;
  final String srcLang;
  final String dstLang;

  @override
  Widget build(BuildContext context) {
    // AST 翻译配对模式：原文+译文合为一个翻译卡片
    if (message.isTranslationPair) {
      return _TranslationPairCard(
        message: message,
        srcLang: srcLang,
        dstLang: dstLang,
      );
    }

    // AST 翻译模式 streaming：翻译正在进行中（原文尚未到达）
    if (isTranslateMode && message.role == 'assistant' &&
        (message.status == 'streaming' || message.status == 'pending')) {
      return _TranslationStreamingCard(
        message: message,
        dstLang: dstLang,
      );
    }

    // 普通聊天气泡
    return _ChatBubble(message: message, agentName: agentName);
  }
}

// ── 翻译配对卡片：双语气泡（原文 + 译文），按语言左右分布 ─────────────────────

class _TranslationPairCard extends StatelessWidget {
  const _TranslationPairCard({
    required this.message,
    required this.srcLang,
    required this.dstLang,
  });
  final ChatMessage message;
  final String srcLang;
  final String dstLang;

  @override
  Widget build(BuildContext context) {
    final detected = message.detectedLang ?? srcLang;
    // 源语言 → 右侧（紫色，类似"我"）；目标语言 → 左侧（白色，类似"对方"）
    final isRight = detected == srcLang;
    final langName = _langLabel(detected);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            isRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // 语言 + 时间标签
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Text(
              '$langName · ${_formatTime(message.createdAt)}',
              style: const TextStyle(fontSize: 10, color: AppTheme.text2),
            ),
          ),

          // 原文气泡（普通聊天气泡样式）
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: isRight ? AppTheme.primary : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isRight ? 16 : 4),
                bottomRight: Radius.circular(isRight ? 4 : 16),
              ),
              boxShadow: isRight
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
              border: isRight ? null : Border.all(color: AppTheme.borderColor),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                fontSize: 14,
                color: isRight ? Colors.white : AppTheme.text1,
                height: 1.5,
              ),
            ),
          ),

          // 译文：气泡下方小号灰色文字（与气泡同侧对齐）
          if (message.translatedContent != null &&
              message.translatedContent!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                top: 4,
                left: isRight ? 0 : 6,
                right: isRight ? 6 : 0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                child: Text(
                  message.translatedContent!,
                  textAlign: isRight ? TextAlign.right : TextAlign.left,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.text2,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── 翻译 streaming 卡片（译文正在进行，原文尚未到达）─────────────────────────

class _TranslationStreamingCard extends StatelessWidget {
  const _TranslationStreamingCard({
    required this.message,
    required this.dstLang,
  });
  final ChatMessage message;
  final String dstLang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 40),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 正在翻译标签
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, left: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFF97316).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '正在翻译 → ${_langLabel(dstLang)}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 翻译内容（streaming）
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72,
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: _StreamingContent(
                      content: message.content, isUser: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 普通聊天气泡 ─────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.agentName});
  final ChatMessage message;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI avatar
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppTheme.primary, Color(0xFF818CF8)]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy_outlined,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Sender label for AI messages
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 2),
                    child: Text(
                      agentName,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.text2,
                          fontWeight: FontWeight.w600),
                    ),
                  ),

                // Bubble
                Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.68,
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    color: isUser ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 16 : 4),
                      topRight: Radius.circular(isUser ? 4 : 16),
                      bottomLeft: const Radius.circular(16),
                      bottomRight: const Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: isUser
                        ? null
                        : Border.all(color: AppTheme.borderColor),
                  ),
                  child: _buildContent(isUser),
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 2, right: 2),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: const TextStyle(fontSize: 10, color: AppTheme.text2),
                  ),
                ),
              ],
            ),
          ),

          // User avatar (right side)
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0xFFE0E7FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: AppTheme.primary, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(bool isUser) {
    final textColor = isUser ? Colors.white : AppTheme.text1;

    switch (message.status) {
      case 'recording':
        return _RecordingContent(content: message.content);
      case 'streaming':
        return _StreamingContent(content: message.content, isUser: isUser);
      case 'cancelled':
        return Opacity(
          opacity: 0.6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.content.isEmpty ? '（已取消）' : message.content,
                style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    height: 1.5,
                    fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.block, size: 11, color: AppTheme.text2),
                  const SizedBox(width: 3),
                  Text(
                    '已打断',
                    style: TextStyle(
                        fontSize: 10,
                        color: isUser ? Colors.white70 : AppTheme.text2),
                  ),
                ],
              ),
            ],
          ),
        );
      case 'error':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isNotEmpty)
              Text(
                message.content,
                style: TextStyle(
                    fontSize: 12,
                    color: isUser ? Colors.white70 : AppTheme.text2,
                    height: 1.4),
              ),
            if (message.content.isNotEmpty) const SizedBox(height: 4),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 11, color: AppTheme.danger),
                SizedBox(width: 3),
                Text('发送失败',
                    style: TextStyle(fontSize: 10, color: AppTheme.danger)),
              ],
            ),
          ],
        );
      default:
        return Text(
          message.content,
          style: TextStyle(fontSize: 14, color: textColor, height: 1.5),
        );
    }
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ── Recording widget: mic dots animation + partial text ──────────────────────

class _RecordingContent extends StatefulWidget {
  const _RecordingContent({required this.content});
  final String content;

  @override
  State<_RecordingContent> createState() => _RecordingContentState();
}

class _RecordingContentState extends State<_RecordingContent>
    with TickerProviderStateMixin {
  late final List<AnimationController> _dots;

  @override
  void initState() {
    super.initState();
    _dots = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 500),
        value: i / 3.0,
      )..repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    for (final c in _dots) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.content.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              widget.content,
              style: const TextStyle(
                  fontSize: 14, color: Colors.white, height: 1.5),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.mic, size: 12, color: Colors.white70),
        ],
      );
    }
    // Empty: show animated dots
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.mic, size: 13, color: Colors.white70),
        const SizedBox(width: 4),
        for (int i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _dots[i],
            builder: (_, __) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.4 + _dots[i].value * 0.6),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Streaming widget with animated blinking cursor ───────────────────────────

class _StreamingContent extends StatefulWidget {
  const _StreamingContent(
      {required this.content, required this.isUser});
  final String content;
  final bool isUser;

  @override
  State<_StreamingContent> createState() => _StreamingContentState();
}

class _StreamingContentState extends State<_StreamingContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursor;

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
    final textColor =
        widget.isUser ? Colors.white : AppTheme.text1;
    return AnimatedBuilder(
      animation: _cursor,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              widget.content,
              style: TextStyle(
                  fontSize: 14, color: textColor, height: 1.5),
            ),
          ),
          const SizedBox(width: 4),
          // Blinking cursor bar
          AnimatedOpacity(
            opacity: _cursor.value > 0.5 ? 1.0 : 0.0,
            duration: Duration.zero,
            child: Container(
              width: 2,
              height: 14,
              margin: const EdgeInsets.only(bottom: 2),
              decoration: BoxDecoration(
                color: widget.isUser
                    ? Colors.white
                    : AppTheme.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
