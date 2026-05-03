import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../models/meeting_detail.dart';

class OverviewTab extends ConsumerWidget {
  const OverviewTab({
    super.key,
    required this.meeting,
    required this.detail,
  });
  final Meeting meeting;
  final MeetingDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final items = detail.overview.isEmpty
        ? <String>[]
        : detail.overview
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        Text(
          DateFormat('yyyy-MM-dd HH:mm').format(meeting.createdAt),
          style: TextStyle(fontSize: 12, color: colors.text2),
        ),
        const SizedBox(height: 6),
        Text(
          meeting.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.text1,
          ),
        ),
        const SizedBox(height: 12),
        Divider(color: colors.border, height: 1),
        const SizedBox(height: 12),
        if (items.isEmpty)
          _empty(colors)
        else ...[
          Text(
            '提取出 ${items.length} 个关键事件',
            style: TextStyle(fontSize: 12, color: colors.text2),
          ),
          const SizedBox(height: 12),
          ...List.generate(items.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 10),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      items[i].trim(),
                      style: TextStyle(
                        color: colors.text1,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AI 提取关键事件 — Round 5 接入后端')),
            );
          },
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('AI 提取概览'),
        ),
      ],
    );
  }

  Widget _empty(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.timeline,
              size: 48, color: colors.text2.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text('暂无概览', style: TextStyle(color: colors.text1)),
          const SizedBox(height: 4),
          Text('录音转写后，AI 会在此提取关键事件',
              style: TextStyle(color: colors.text2, fontSize: 12)),
        ],
      ),
    );
  }
}
