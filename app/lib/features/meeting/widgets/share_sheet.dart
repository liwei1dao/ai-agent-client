import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';

Future<void> showShareSheet(BuildContext context, Meeting m) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _ShareSheet(meeting: m),
  );
}

class _ShareSheet extends StatelessWidget {
  const _ShareSheet({required this.meeting});
  final Meeting meeting;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '分享会议',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.text1,
              ),
            ),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              crossAxisCount: 4,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _shareItem(context, Icons.audio_file, '分享音频', () async {
                  Navigator.pop(context);
                  if (meeting.audioPath.isEmpty ||
                      !await File(meeting.audioPath).exists()) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('音频文件不存在')),
                      );
                    }
                    return;
                  }
                  await Share.shareXFiles(
                    [XFile(meeting.audioPath)],
                    text: meeting.title,
                  );
                }),
                _shareItem(context, Icons.text_snippet, '分享纪要', () async {
                  Navigator.pop(context);
                  await Share.share('${meeting.title}\n\n${meeting.audioPath}');
                }),
                _shareItem(context, Icons.link, '复制链接', () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制（占位）')),
                  );
                }),
                _shareItem(context, Icons.qr_code_2, '二维码', () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('二维码（占位）')),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareItem(
      BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    final colors = ctx.appColors;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 12, color: colors.text2)),
        ],
      ),
    );
  }
}
