import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/services/locale_service.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/agent_screen_provider.dart';

/// 语言代码 → 显示名称（canonical 优先，其次 [LocaleService.toCanonical] 兜底）。
String _langLabel(String? code) {
  if (code == null || code.isEmpty) return '';
  return LocaleService.langNames[code] ??
      LocaleService.langNames[LocaleService.toCanonical(code)] ??
      code;
}

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
    this.srcLang = 'zh-CN',
    this.dstLang = 'en-US',
    this.selfLang,
  });
  final AgentMessage message;
  final String agentName;
  final bool isTranslateMode;
  final String srcLang;
  final String dstLang;

  /// "己方"语言（决定翻译卡片放右侧还是左侧）。
  /// - 三段式 translate：通常 = srcLang（己方说源语言）
  /// - ast-translate：通常 = dstLang（己方读译文）
  /// 为 null 时回退到 dstLang，保持旧 AST 行为。
  final String? selfLang;

  @override
  Widget build(BuildContext context) {
    // AST 翻译配对模式：原文+译文合为一个翻译卡片
    if (message.isTranslationPair) {
      return _TranslationPairCard(
        message: message,
        srcLang: srcLang,
        dstLang: dstLang,
        selfLang: selfLang ?? dstLang,
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
    required this.selfLang,
  });
  final AgentMessage message;
  final String srcLang;
  final String dstLang;
  final String selfLang;

  @override
  Widget build(BuildContext context) {
    final detected = LocaleService.toCanonical(message.detectedLang ?? srcLang);
    final self = LocaleService.toCanonical(selfLang);
    // 内容语言 == 己方语言 → 右侧（紫色，己方）；否则 → 左侧（白色，对方）
    final isRight = detected == self;
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
  final AgentMessage message;
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
  final AgentMessage message;
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

                // 工具调用 / thinking 等过程事件 — 仅 AI 侧渲染，置于气泡上方
                if (!isUser && message.events.isNotEmpty) ...[
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    child: _MessageEventsList(events: message.events),
                  ),
                  if (message.content.isNotEmpty ||
                      message.status == 'error' ||
                      message.status == 'cancelled')
                    const SizedBox(height: 6),
                ],

                // Bubble — 仅当有内容或处于显式 error/cancelled 时渲染。
                // streaming 阶段如果只有事件没有文本，气泡先不出现，避免空白。
                if (message.content.isNotEmpty ||
                    message.status == 'error' ||
                    message.status == 'cancelled' ||
                    (isUser) ||
                    message.events.isEmpty)
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
    for (final c in _dots) {
      c.dispose();
    }
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

// ── 工具调用 / thinking 等过程事件：Inline pill 风格 ─────────────────────────
//
// 设计：
// - 默认态 = 一行小 pill，横向 Wrap，密集、不抢戏
// - 点击 pill → 在 pill 区域下方展开一个详情卡（参数 / 结果），同时只能展开一个
// - 再点同一个 pill / 点其它 pill 切换；点空白处不收起（避免误触）

class _MessageEventsList extends StatefulWidget {
  const _MessageEventsList({required this.events});
  final List<MessageEvent> events;

  @override
  State<_MessageEventsList> createState() => _MessageEventsListState();
}

class _MessageEventsListState extends State<_MessageEventsList> {
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    MessageEvent? expanded;
    if (_expandedId != null) {
      for (final e in widget.events) {
        if (e.id == _expandedId) { expanded = e; break; }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final e in widget.events)
              _EventPill(
                event: e,
                expanded: e.id == _expandedId,
                onTap: () {
                  final hasDetails =
                      e.input.isNotEmpty || (e.output?.isNotEmpty ?? false);
                  if (!hasDetails) return;
                  setState(() {
                    _expandedId = (_expandedId == e.id) ? null : e.id;
                  });
                },
              ),
          ],
        ),
        if (expanded != null) ...[
          const SizedBox(height: 6),
          _EventDetailCard(event: expanded),
        ],
      ],
    );
  }
}

/// 单行 pill —— 状态 icon + 名称 + 用时，圆角到底。
class _EventPill extends StatelessWidget {
  const _EventPill({
    required this.event,
    required this.expanded,
    required this.onTap,
  });
  final MessageEvent event;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final running = e.status == 'running';
    final isErr = e.status == 'error';

    final accent = switch (e.kind) {
      MessageEventKind.toolCall => isErr
          ? AppTheme.danger
          : (running ? AppTheme.primary : AppTheme.success),
      MessageEventKind.thinking => const Color(0xFF8B5CF6),
      // 指令事件：橙色暖色调，区别于工具调用（绿）/ 思考（紫）。
      MessageEventKind.instruction =>
          isErr ? AppTheme.danger : const Color(0xFFEA580C),
      MessageEventKind.custom => AppTheme.text2,
    };

    final bg = isErr
        ? const Color(0xFFFEF2F2)
        : (e.kind == MessageEventKind.thinking
            ? const Color(0xFFF5F3FF)
            : (e.kind == MessageEventKind.instruction
                ? const Color(0xFFFFF7ED)
                : (running
                    ? const Color(0xFFEEF0FF)
                    : const Color(0xFFF1F5F9))));
    final borderColor = isErr
        ? const Color(0xFFFECACA)
        : (e.kind == MessageEventKind.thinking
            ? const Color(0xFFE9D5FF)
            : (e.kind == MessageEventKind.instruction
                ? const Color(0xFFFED7AA)
                : (running
                    ? const Color(0xFFC7D2FE)
                    : const Color(0xFFE2E8F0))));

    final label = switch (e.kind) {
      MessageEventKind.toolCall => e.label,
      MessageEventKind.thinking => running ? '思考中…' : '思考',
      MessageEventKind.instruction => '指令 · ${e.label}',
      MessageEventKind.custom => e.label,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StatusIcon(
                kind: e.kind,
                running: running,
                isError: isErr,
                color: accent,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                  height: 1.1,
                ),
              ),
              if (e.duration != null) ...[
                const SizedBox(width: 5),
                Text(
                  '· ${_formatDuration(e.duration!)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.text2,
                    height: 1.1,
                  ),
                ),
              ],
              const SizedBox(width: 3),
              AnimatedRotation(
                turns: expanded ? -0.25 : 0.25,
                duration: const Duration(milliseconds: 120),
                child: Icon(
                  Icons.chevron_right,
                  size: 13,
                  color: accent.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 展开的详情卡：参数 / 结果 用等宽字体显示，可复制。
class _EventDetailCard extends StatelessWidget {
  const _EventDetailCard({required this.event});
  final MessageEvent event;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final isErr = e.status == 'error';
    final borderColor =
        isErr ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isErr ? const Color(0xFFFEF2F2) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (e.input.isNotEmpty)
            _DetailBlock(
              label: (e.kind == MessageEventKind.toolCall ||
                      e.kind == MessageEventKind.instruction)
                  ? '参数'
                  : '内容',
              text: _prettyJson(e.input),
            ),
          if ((e.output ?? '').isNotEmpty) ...[
            if (e.input.isNotEmpty) const SizedBox(height: 8),
            _DetailBlock(
              label: isErr ? '错误' : '结果',
              text: e.output!,
              danger: isErr,
            ),
          ],
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds}ms';
  final s = (d.inMilliseconds / 1000).toStringAsFixed(d.inSeconds < 10 ? 1 : 0);
  return '${s}s';
}

/// 尽力把 JSON 串美化；不是 JSON 就原样回。
String _prettyJson(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return raw;
  if (!t.startsWith('{') && !t.startsWith('[')) return raw;
  try {
    final obj = const JsonDecoder().convert(t);
    return const JsonEncoder.withIndent('  ').convert(obj);
  } catch (_) {
    return raw;
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.kind,
    required this.running,
    required this.isError,
    required this.color,
  });
  final MessageEventKind kind;
  final bool running;
  final bool isError;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (running) {
      return SizedBox(
        width: 11,
        height: 11,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
      );
    }
    final icon = isError
        ? Icons.error_outline
        : switch (kind) {
            MessageEventKind.toolCall => Icons.check_circle,
            MessageEventKind.thinking => Icons.psychology_outlined,
            MessageEventKind.instruction => Icons.bolt,
            MessageEventKind.custom => Icons.bolt,
          };
    return Icon(icon, size: 12, color: color);
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.text,
    this.danger = false,
  });
  final String label;
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: danger ? AppTheme.danger : AppTheme.text2,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: SelectableText(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              height: 1.4,
              color: danger ? AppTheme.danger : AppTheme.text1,
            ),
          ),
        ),
      ],
    );
  }
}
