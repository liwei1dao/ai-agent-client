import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../providers/meeting_providers.dart';

Future<void> showMoreActionsSheet(
  BuildContext context,
  WidgetRef ref,
  Meeting m, {
  required VoidCallback onRename,
  required VoidCallback onDelete,
  required VoidCallback onMark,
  required VoidCallback onPlay,
  required bool isPlaying,
  required bool isMarked,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final uploaded = m.audioUrl.isNotEmpty;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(ctx,
                icon: isPlaying ? Icons.pause : Icons.play_arrow,
                label: isPlaying ? '暂停播放' : '播放音频', onTap: () {
              Navigator.pop(ctx);
              onPlay();
            }),
            _row(ctx,
                icon: isMarked
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: isMarked ? Colors.amber : null,
                label: isMarked ? '取消收藏' : '收藏', onTap: () {
              Navigator.pop(ctx);
              onMark();
            }),
            _row(ctx, icon: Icons.edit, label: '重命名', onTap: () {
              Navigator.pop(ctx);
              onRename();
            }),
            _row(ctx,
                icon: uploaded
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
                color: uploaded ? AppTheme.success : null,
                label: uploaded ? '已上传到云端 · 重新上传' : '上传到云端', onTap: () {
              Navigator.pop(ctx);
              ref
                  .read(meetingUploadCoordinatorProvider)
                  .retry(m.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已开始上传到云端')),
              );
            }),
            _row(ctx,
                icon: Icons.delete_outline,
                color: AppTheme.danger,
                label: '删除', onTap: () {
              Navigator.pop(ctx);
              onDelete();
            }),
            const SizedBox(height: 4),
          ],
        ),
      );
    },
  );
}

Widget _row(BuildContext ctx,
    {required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color}) {
  final colors = ctx.appColors;
  final c = color ?? colors.text1;
  return ListTile(
    leading: Icon(icon, color: c, size: 22),
    title: Text(label, style: TextStyle(fontSize: 14, color: c)),
    onTap: onTap,
  );
}
