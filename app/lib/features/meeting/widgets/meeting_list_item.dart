import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../providers/meeting_providers.dart';

/// 完整复用 deepvoice_client_liwei 的 [meeting_home_view._item](
/// /Users/liwei/work/flutter/deepvoice_client_liwei/lib/modules/meeting/views/meeting_home_view.dart) 的 UI：
///
/// 圆角 12 卡 + 阴影 → 标题 18 → 日历/时长行 → 类型 chip + 上传状态 + 任务状态
/// 选中态红色 1.5 边框；上传中时图标位置叠环形进度条。
class MeetingListItem extends ConsumerWidget {
  const MeetingListItem({
    super.key,
    required this.meeting,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final coord = ref.watch(meetingUploadCoordinatorProvider);

    return GestureDetector(
      onTap: onTap,
      onLongPress: selectionMode ? null : onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: selectionMode && selected
              ? Border.all(color: AppTheme.danger, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected ? AppTheme.danger : colors.text2,
                  size: 22,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 标题
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          meeting.title.isEmpty ? '未命名会议' : meeting.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            color: colors.text1,
                          ),
                        ),
                      ),
                      if (meeting.marked) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded,
                            color: Colors.amber, size: 18),
                      ],
                    ],
                  ),
                  // 2. 日期 + 时长
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month,
                            size: 14, color: colors.text2),
                        const SizedBox(width: 2),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm')
                              .format(meeting.createdAt),
                          style: TextStyle(
                              fontSize: 12, color: colors.text2),
                        ),
                        const SizedBox(width: 20),
                        Icon(Icons.access_time,
                            size: 14, color: colors.text2),
                        const SizedBox(width: 2),
                        Text(
                          _formatSeconds(meeting.durationMs ~/ 1000),
                          style: TextStyle(
                              fontSize: 12, color: colors.text2),
                        ),
                      ],
                    ),
                  ),
                  // 3. 类型 chip + 上传状态 + 任务状态
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _typeLabel(meeting.audioType),
                          style:
                              TextStyle(color: colors.text2, fontSize: 10),
                        ),
                      ),
                      const Spacer(),
                      _UploadIndicator(meeting: meeting, coord: coord),
                      if (meeting.transcribed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 2),
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.translateAccent
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '总结完成',
                            style: TextStyle(
                                color: AppTheme.translateAccent,
                                fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _typeLabel(MeetingAudioType t) => switch (t) {
        MeetingAudioType.live => '实时录音',
        MeetingAudioType.audioVideo => '音视频',
        MeetingAudioType.call => '通话',
      };

  static String _formatSeconds(int total) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _UploadIndicator extends StatefulWidget {
  const _UploadIndicator({required this.meeting, required this.coord});
  final Meeting meeting;
  final dynamic coord; // MeetingUploadCoordinator (避免循环导入用 dynamic)

  @override
  State<_UploadIndicator> createState() => _UploadIndicatorState();
}

class _UploadIndicatorState extends State<_UploadIndicator> {
  late final Stream<dynamic> _stream;

  @override
  void initState() {
    super.initState();
    _stream = (widget.coord as dynamic).changes as Stream<dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _stream,
      builder: (ctx, _) {
        final progress =
            (widget.coord as dynamic).progressFor(widget.meeting.id) as double;
        final uploaded = widget.meeting.audioUrl.isNotEmpty;
        final uploading = progress > 0 && progress < 1;

        if (uploading) {
          return Container(
            margin: const EdgeInsets.only(top: 5),
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 1.5,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '上传中 ${(progress * 100).toInt()}%',
                  style:
                      const TextStyle(color: Colors.blue, fontSize: 10),
                ),
              ],
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(top: 5),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (uploaded ? AppTheme.success : Colors.orange)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                uploaded ? Icons.cloud_done : Icons.cloud_off,
                color: uploaded ? AppTheme.success : Colors.orange,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                uploaded ? '已上传' : '未上传',
                style: TextStyle(
                  color: uploaded ? AppTheme.success : Colors.orange,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
