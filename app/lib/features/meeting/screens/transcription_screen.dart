import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/app_theme.dart';
import '../providers/meeting_providers.dart';

/// 转写记录列表 — 仅显示已完成转写或有转写片段的会议。
class TranscriptionScreen extends ConsumerWidget {
  const TranscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(meetingListProvider);
    final colors = context.appColors;
    return Scaffold(
      appBar: AppBar(title: const Text('转写记录')),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (all) {
          final list = all.where((m) => m.transcribed).toList();
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.subtitles_outlined,
                        size: 56,
                        color: colors.text2.withValues(alpha: 0.5)),
                    const SizedBox(height: 12),
                    Text('暂无转写记录',
                        style: TextStyle(
                            color: colors.text1,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('录音完成后，AI 会为您自动生成转写文本',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: colors.text2, fontSize: 12)),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) {
              final m = list[i];
              return InkWell(
                onTap: () => context.push('/meeting/detail/${m.id}'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.subtitles,
                            color: AppTheme.success, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: colors.text1)),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('yyyy-MM-dd HH:mm')
                                  .format(m.createdAt),
                              style: TextStyle(
                                  fontSize: 12, color: colors.text2),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.text2),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
