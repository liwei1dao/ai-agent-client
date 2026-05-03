import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../models/meeting_detail.dart';
import '../models/speech_segment.dart';
import '../providers/meeting_providers.dart';
import '../widgets/edit_title_sheet.dart';

class SpeechTab extends ConsumerWidget {
  const SpeechTab({
    super.key,
    required this.meeting,
    required this.detail,
    required this.position,
  });
  final Meeting meeting;
  final MeetingDetail detail;
  final Duration position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    if (detail.segments.isEmpty) {
      return _empty(colors, '暂无转写记录', '请录音结束后启动转写，或在更多菜单中手动转写');
    }
    final activeIdx = _activeIndex(detail.segments, position);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      itemCount: detail.segments.length,
      itemBuilder: (ctx, i) {
        final seg = detail.segments[i];
        final active = i == activeIdx;
        return _SegmentTile(
          seg: seg,
          active: active,
          onEditSpeaker: () => _editSpeaker(context, ref, seg),
          onEditText: () => _editText(context, ref, seg),
        );
      },
    );
  }

  int _activeIndex(List<SpeechSegment> segments, Duration position) {
    final ms = position.inMilliseconds;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (ms >= s.startMs && ms <= s.endMs) return i;
    }
    return -1;
  }

  Future<void> _editSpeaker(
      BuildContext context, WidgetRef ref, SpeechSegment seg) async {
    final next = await showEditTitleSheet(
      context,
      title: '修改说话人',
      hint: '说话人',
      initial: seg.speaker,
    );
    if (next == null || next.trim().isEmpty) return;
    final updated = detail.segments
        .map((s) =>
            s.id == seg.id ? s.copyWith(speaker: next.trim()) : s)
        .toList();
    final repo = ref.read(meetingRepositoryProvider);
    await repo.writeDetail(detail.copyWith(segments: updated));
    ref.invalidate(meetingDetailProvider(meeting.id));
  }

  Future<void> _editText(
      BuildContext context, WidgetRef ref, SpeechSegment seg) async {
    final next = await showEditTitleSheet(
      context,
      title: '修改文本',
      hint: '请输入文本',
      initial: seg.text,
    );
    if (next == null || next.trim().isEmpty) return;
    final updated = detail.segments
        .map((s) =>
            s.id == seg.id ? s.copyWith(text: next.trim()) : s)
        .toList();
    final repo = ref.read(meetingRepositoryProvider);
    await repo.writeDetail(detail.copyWith(segments: updated));
    ref.invalidate(meetingDetailProvider(meeting.id));
  }

  Widget _empty(AppColors colors, String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.subtitles_off_outlined,
                size: 56, color: colors.text2.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.text1)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.text2)),
          ],
        ),
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    required this.seg,
    required this.active,
    required this.onEditSpeaker,
    required this.onEditText,
  });
  final SpeechSegment seg;
  final bool active;
  final VoidCallback onEditSpeaker;
  final VoidCallback onEditText;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final accent =
        active ? AppTheme.primary : (seg.speaker.isEmpty ? colors.text2 : Colors.amber);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (seg.speaker.isNotEmpty) ...[
                GestureDetector(
                  onTap: onEditSpeaker,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: accent, width: 2),
                        ),
                      ),
                      Text(
                        seg.speaker,
                        style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                _formatTime(seg.startMs),
                style: TextStyle(color: colors.text2, fontSize: 12),
              ),
              const Spacer(),
              if (active)
                const Icon(Icons.equalizer,
                    color: AppTheme.primary, size: 14),
            ],
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: onEditText,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? AppTheme.primary.withValues(alpha: 0.06)
                    : colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                seg.text,
                style: TextStyle(
                    color: colors.text1, fontSize: 14, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(int ms) {
    final h = ms ~/ 3600000;
    final m = (ms % 3600000) ~/ 60000;
    final s = (ms % 60000) ~/ 1000;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
