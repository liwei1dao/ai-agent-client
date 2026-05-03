import 'package:flutter/material.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting_detail.dart';

/// 思维导图 Tab — 简化版：解析 newline / 缩进格式渲染成树状视图。
///
/// 源项目用 WebView + 自定义 HTML/JS 实现可交互的思维导图。这里先实现"占位
/// 友好版"：把 mindmapHtml 当成结构化文本，通过缩进判断层级。后续 Round 5
/// 接入后端时可以保留同步存到 mindmapHtml 字段，再切换为 WebView 实现。
class MindMapTab extends StatelessWidget {
  const MindMapTab({super.key, required this.detail});
  final MeetingDetail detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final nodes = _parse(detail.mindmapHtml);
    if (nodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.account_tree_outlined,
                  size: 56, color: colors.text2.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text('暂无思维导图',
                  style: TextStyle(
                      color: colors.text1,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('AI 会在转写完成后生成会议结构化思维导图',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.text2, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: nodes.map((n) => _node(context, n)).toList(),
      ),
    );
  }

  Widget _node(BuildContext context, _MindNode n) {
    final colors = context.appColors;
    return Padding(
      padding: EdgeInsets.only(left: 16.0 * n.depth, top: 6, bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary
              .withValues(alpha: 0.08 + (3 - n.depth.clamp(0, 3)) * 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        ),
        child: Text(
          n.text,
          style: TextStyle(
            color: colors.text1,
            fontSize: 14 - (n.depth.clamp(0, 3)).toDouble(),
            fontWeight: n.depth == 0 ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// "  - 子项"  → depth=1; "    - 孙项" → depth=2.
  List<_MindNode> _parse(String src) {
    if (src.trim().isEmpty) return const [];
    final lines = src.split('\n');
    final out = <_MindNode>[];
    for (final raw in lines) {
      if (raw.trim().isEmpty) continue;
      var leading = 0;
      for (final c in raw.runes) {
        if (c == 0x20) {
          leading++;
        } else if (c == 0x09) {
          leading += 2;
        } else {
          break;
        }
      }
      final depth = leading ~/ 2;
      final text = raw.trim().replaceFirst(RegExp(r'^[-*•]\s*'), '');
      out.add(_MindNode(depth, text));
    }
    return out;
  }
}

class _MindNode {
  const _MindNode(this.depth, this.text);
  final int depth;
  final String text;
}
