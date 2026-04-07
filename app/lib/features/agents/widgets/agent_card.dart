import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:local_db/local_db.dart';
import '../../../shared/themes/app_theme.dart';

class AgentCard extends StatefulWidget {
  const AgentCard({
    super.key,
    required this.agent,
    required this.onTap,
    this.onDelete,
    this.services = const [],
    this.isRemote = false,
  });
  final AgentDto agent;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final List<ServiceConfigDto> services;
  final bool isRemote;

  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  bool _isOpen = false;

  static const double _deleteWidth = 80;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-_deleteWidth, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    _controller.forward();
    _isOpen = true;
  }

  void _close() {
    _controller.reverse();
    _isOpen = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final newValue = (_controller.value - delta / _deleteWidth).clamp(0.0, 1.0);
    _controller.value = newValue;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      _open();
    } else if (velocity > 300) {
      _close();
    } else {
      if (_controller.value > 0.4) { _open(); } else { _close(); }
    }
  }

  String _svcName(String? id) {
    if (id == null) return '';
    try {
      return widget.services.firstWhere((s) => s.id == id).name;
    } catch (_) {
      return '';
    }
  }

  /// Build service chips from agent config
  List<_ChipData> _buildServiceChips() {
    final cfg = jsonDecode(widget.agent.configJson) as Map<String, dynamic>;
    final chips = <_ChipData>[];

    // LLM / Translation / STS / AST — main service
    final llmName = _svcName(cfg['llmServiceId'] as String?);
    final transName = _svcName(cfg['translationServiceId'] as String?);
    final stsName = _svcName(cfg['stsServiceId'] as String?);
    final astName = _svcName(cfg['astServiceId'] as String?);

    if (stsName.isNotEmpty) {
      chips.add(_ChipData(stsName, const Color(0xFF9A3412), const Color(0xFFFFF7ED)));
    } else if (astName.isNotEmpty) {
      chips.add(_ChipData(astName, const Color(0xFF065F46), const Color(0xFFECFDF5)));
    } else {
      if (llmName.isNotEmpty) {
        chips.add(_ChipData(llmName, const Color(0xFF7C3AED), const Color(0xFFF5F3FF)));
      }
      if (transName.isNotEmpty) {
        chips.add(_ChipData(transName, const Color(0xFF1D4ED8), const Color(0xFFEFF6FF)));
      }
    }

    // STT
    final sttName = _svcName(cfg['sttServiceId'] as String?);
    if (sttName.isNotEmpty) {
      chips.add(_ChipData(sttName, const Color(0xFF92400E), const Color(0xFFFEF3C7)));
    }

    // TTS + voice
    final ttsName = _svcName(cfg['ttsServiceId'] as String?);
    if (ttsName.isNotEmpty) {
      final voice = cfg['voiceName'] as String?;
      final label = voice != null ? '$ttsName $voice' : ttsName;
      chips.add(_ChipData(label, const Color(0xFF065F46), const Color(0xFFECFDF5)));
    }

    return chips;
  }

  String _relativeTime(int ms) {
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${diff.inDays ~/ 30} 个月前';
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final (Color typeBorderColor, Color typeBadgeBg, Color typeBadgeColor, String typeBadgeLabel, String typeEmoji) =
        switch (agent.type) {
      'chat'      => (AppTheme.primary,              AppTheme.primaryLight,      AppTheme.primaryDark,       '聊天',  '💬'),
      'translate' => (AppTheme.translateAccent,      const Color(0xFFE0F2FE),    const Color(0xFF0369A1),    '翻译',  '🌐'),
      'sts'       => (const Color(0xFFF97316),       const Color(0xFFFFF7ED),    const Color(0xFF9A3412),    'STS 聊天', '🗣️'),
      _           => (const Color(0xFF10B981),       const Color(0xFFECFDF5),    const Color(0xFF065F46),    'AST 翻译', '🔄'),
    };

    // 远程 Agent 使用云端色调
    final Color borderColor = widget.isRemote ? const Color(0xFF0891B2) : typeBorderColor;
    final String emoji = widget.isRemote ? '☁️' : typeEmoji;

    final chips = _buildServiceChips();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          // Delete button behind
          Positioned.fill(
            child: Row(
              children: [
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    _close();
                    _confirmDelete(context);
                  },
                  child: Container(
                    width: _deleteWidth,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline, color: Colors.white, size: 22),
                        SizedBox(height: 4),
                        Text('删除', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Swipeable card on top
          AnimatedBuilder(
            animation: _slideAnimation,
            builder: (context, child) => Transform.translate(
              offset: _slideAnimation.value,
              child: child,
            ),
            child: GestureDetector(
              onHorizontalDragUpdate: (!widget.isRemote && widget.onDelete != null) ? _onHorizontalDragUpdate : null,
              onHorizontalDragEnd: (!widget.isRemote && widget.onDelete != null) ? _onHorizontalDragEnd : null,
              onTap: () {
                if (_isOpen) { _close(); } else { widget.onTap(); }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border(left: BorderSide(color: borderColor, width: 4)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 2))],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top: name + badge
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$emoji ${agent.name}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.text1)),
                                const SizedBox(height: 2),
                                Text('创建于 ${_relativeTime(agent.createdAt)}',
                                    style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: widget.isRemote ? const Color(0xFFE0F7FA) : typeBadgeBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isRemote) ...[
                                  Icon(Icons.cloud_outlined, size: 10, color: const Color(0xFF0891B2)),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  widget.isRemote ? '云端 · $typeBadgeLabel' : typeBadgeLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: widget.isRemote ? const Color(0xFF0891B2) : typeBadgeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // Service chips
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: chips.map((c) =>
                            _ServiceChip(label: c.label, color: c.color, bg: c.bg),
                          ).toList(),
                        ),
                      ],

                      // Bottom: time + token badge + open button
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 12, color: AppTheme.text2),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _relativeTime(agent.updatedAt),
                              style: const TextStyle(fontSize: 11, color: AppTheme.text2),
                            ),
                          ),
                          Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(color: borderColor, borderRadius: BorderRadius.circular(14)),
                            alignment: Alignment.center,
                            child: const Text('打开 →', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除 Agent'),
        content: Text('确定要删除「${widget.agent.name}」吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: AppTheme.text2)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDelete?.call();
            },
            child: const Text('删除', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ChipData {
  const _ChipData(this.label, this.color, this.bg);
  final String label;
  final Color color;
  final Color bg;
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({required this.label, required this.color, required this.bg});
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
