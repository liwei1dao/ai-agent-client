import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/meeting.dart';
import '../providers/meeting_providers.dart';
import '../providers/recorder_provider.dart';

/// 录音模式选择 — 复刻 [navigation_bar_bottom_sheet](
/// /Users/liwei/work/flutter/deepvoice_client_liwei/lib/modules/meeting/views/bottomSheet/navigation_bar_bottom_sheet.dart)
/// 的胶囊样式：现场录音 / 音视频录音 / 通话录音 / 导入音频。
Future<void> showRecordModeSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillItem(
            title: '现场录音',
            icon: Icons.mic_rounded,
            color: Colors.red,
            onTap: () {
              Navigator.pop(ctx);
              ref
                  .read(recorderProvider.notifier)
                  .setAudioType(MeetingAudioType.live);
              context.push('/meeting/record');
            },
          ),
          _PillItem(
            title: '音视频录音',
            icon: Icons.videocam,
            color: Colors.green,
            onTap: () {
              Navigator.pop(ctx);
              ref
                  .read(recorderProvider.notifier)
                  .setAudioType(MeetingAudioType.audioVideo);
              context.push('/meeting/record');
            },
          ),
          _PillItem(
            title: '通话录音',
            icon: Icons.phone,
            color: Colors.orange,
            onTap: () {
              Navigator.pop(ctx);
              ref
                  .read(recorderProvider.notifier)
                  .setAudioType(MeetingAudioType.call);
              context.push('/meeting/record');
            },
          ),
          _PillItem(
            title: '导入音频',
            icon: Icons.file_upload_outlined,
            color: Colors.deepPurple,
            onTap: () {
              Navigator.pop(ctx);
              _importAudio(context, ref);
            },
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

Future<void> _importAudio(BuildContext context, WidgetRef ref) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.audio,
    allowMultiple: false,
  );
  if (result == null || result.files.isEmpty) return;
  final picked = result.files.single;
  final srcPath = picked.path;
  if (srcPath == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取选中的音频文件')),
      );
    }
    return;
  }

  final id = const Uuid().v4();
  final docs = await getApplicationDocumentsDirectory();
  final ext = picked.extension ?? 'm4a';
  final destPath = '${docs.path}/meetings/audio_$id.$ext';
  await File(destPath).parent.create(recursive: true);
  await File(srcPath).copy(destPath);
  final lengthMs = await _probeDurationMs(destPath);

  final m = Meeting(
    id: id,
    title: picked.name,
    createdAt: DateTime.now(),
    durationMs: lengthMs,
    audioType: MeetingAudioType.audioVideo,
    audioPath: destPath,
  );
  await ref.read(meetingListProvider.notifier).add(m);
  // 触发上传到 COS
  ref
      .read(meetingUploadCoordinatorProvider)
      .uploadInBackground(id);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入「${picked.name}」并开始上传')),
    );
  }
}

Future<int> _probeDurationMs(String path) async {
  try {
    final stat = await File(path).stat();
    // file size 仅作为兜底，无法直接换算时长；这里返回 0，后续播放器会读真实时长。
    return stat.size > 0 ? 0 : 0;
  } catch (_) {
    return 0;
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.title,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = onTap == null;
    final bg = isDark
        ? Colors.grey[800]!.withValues(alpha: disabled ? 0.5 : 1)
        : Colors.white.withValues(alpha: disabled ? 0.5 : 1);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 240,
        height: 60,
        padding: const EdgeInsets.all(5),
        margin: const EdgeInsets.only(top: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(60),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: disabled ? 0.2 : 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color:
                      color.withValues(alpha: disabled ? 0.5 : 1)),
            ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? Colors.white.withValues(
                          alpha: disabled ? 0.5 : 1)
                      : Colors.black87.withValues(
                          alpha: disabled ? 0.5 : 1),
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 16,
                color: Colors.grey.withValues(alpha: disabled ? 0.5 : 1)),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
