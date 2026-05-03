import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../models/meeting_detail.dart';
import '../providers/meeting_providers.dart';
import '../tabs/mind_map_tab.dart';
import '../tabs/overview_tab.dart';
import '../tabs/speech_tab.dart';
import '../tabs/summary_tab.dart';
import '../widgets/edit_title_sheet.dart';
import '../widgets/more_actions_sheet.dart';
import '../widgets/share_sheet.dart';

class MeetingDetailScreen extends ConsumerStatefulWidget {
  const MeetingDetailScreen({super.key, required this.meetingId});
  final String meetingId;

  @override
  ConsumerState<MeetingDetailScreen> createState() =>
      _MeetingDetailScreenState();
}

class _MeetingDetailScreenState extends ConsumerState<MeetingDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    });
    _posSub = _player.onPositionChanged
        .listen((p) => mounted ? setState(() => _position = p) : null);
    _durSub = _player.onDurationChanged
        .listen((d) => mounted ? setState(() => _duration = d) : null);
  }

  @override
  void dispose() {
    _tab.dispose();
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(Meeting m) async {
    if (m.audioPath.isEmpty) return;
    if (_playing) {
      await _player.pause();
    } else {
      if (_position == Duration.zero) {
        await _player.play(DeviceFileSource(m.audioPath));
      } else {
        await _player.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(meetingListProvider);
    final meeting = list.value?.firstWhere(
      (m) => m.id == widget.meetingId,
      orElse: () => Meeting(
        id: widget.meetingId,
        title: '',
        createdAt: DateTime.now(),
        durationMs: 0,
        audioType: MeetingAudioType.live,
        audioPath: '',
      ),
    );

    if (meeting == null || meeting.title.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final detailAsync = ref.watch(meetingDetailProvider(widget.meetingId));

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _editTitle(meeting),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: context.appColors.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(_playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill),
                  color: AppTheme.primary,
                  iconSize: 28,
                  onPressed: () => _togglePlay(meeting),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    meeting.title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => showShareSheet(context, meeting),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () => showMoreActionsSheet(
              context,
              ref,
              meeting,
              onRename: () => _editTitle(meeting),
              onDelete: () => _confirmDelete(meeting),
              onMark: () => ref
                  .read(meetingListProvider.notifier)
                  .toggleMark(meeting.id),
              onPlay: () => _togglePlay(meeting),
              isPlaying: _playing,
              isMarked: meeting.marked,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '速记'),
            Tab(text: '摘要'),
            Tab(text: '概览'),
            Tab(text: '思维导图'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_duration.inMilliseconds > 0) _PlayerScrubBar(
            position: _position,
            duration: _duration,
            onSeek: (d) => _player.seek(d),
          ),
          Expanded(
            child: detailAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('详情加载失败：$e')),
              data: (detail) => TabBarView(
                controller: _tab,
                children: [
                  SpeechTab(meeting: meeting, detail: detail, position: _position),
                  SummaryTab(meeting: meeting, detail: detail),
                  OverviewTab(meeting: meeting, detail: detail),
                  MindMapTab(detail: detail),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTitle(Meeting m) async {
    final next = await showEditTitleSheet(context, initial: m.title);
    if (next != null && next.trim().isNotEmpty) {
      await ref
          .read(meetingListProvider.notifier)
          .rename(m.id, next.trim());
    }
  }

  Future<void> _confirmDelete(Meeting m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除？'),
        content: Text('「${m.title}」将被永久删除，无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(meetingListProvider.notifier).delete(m.id);
    if (mounted) context.pop();
  }
}

class _PlayerScrubBar extends StatelessWidget {
  const _PlayerScrubBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: colors.surface,
      child: Row(
        children: [
          Text(
            _fmt(position),
            style: TextStyle(fontSize: 11, color: colors.text2),
          ),
          Expanded(
            child: Slider(
              min: 0,
              max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
              value: position.inMilliseconds
                  .clamp(0, duration.inMilliseconds)
                  .toDouble(),
              onChanged: (v) => onSeek(Duration(milliseconds: v.toInt())),
            ),
          ),
          Text(
            _fmt(duration),
            style: TextStyle(fontSize: 11, color: colors.text2),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

extension MeetingDateX on Meeting {
  String formattedDate() => DateFormat('yyyy-MM-dd HH:mm').format(createdAt);
}

extension MeetingDetailExt on MeetingDetail {
  bool get isEmpty =>
      summary.isEmpty &&
      overview.isEmpty &&
      mindmapHtml.isEmpty &&
      segments.isEmpty;
}
