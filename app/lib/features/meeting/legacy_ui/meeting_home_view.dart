// 1:1 移植自 deepvoice_client_liwei
// lib/modules/meeting/views/meeting_home_view.dart
//
// 调整：把所有 GetX (Get.put / Obx / RxList / .obs) 改为 Riverpod，把
// Get.toNamed/Get.bottomSheet/Get.dialog 改为 go_router 和 Material 等价
// API；UI 布局、尺寸、配色保持原样。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/meeting.dart';
import '../providers/meeting_providers.dart';
import '../providers/recorder_provider.dart';
import 'meeting_ui_utils.dart';

class LegacyMeetingHomeView extends ConsumerStatefulWidget {
  const LegacyMeetingHomeView({super.key});

  @override
  ConsumerState<LegacyMeetingHomeView> createState() =>
      _LegacyMeetingHomeViewState();
}

class _LegacyMeetingHomeViewState
    extends ConsumerState<LegacyMeetingHomeView> {
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final selection = ref.watch(meetingSelectionProvider);

    return PopScope(
      canPop: !selection.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selection.active) {
          ref.read(meetingSelectionProvider.notifier).exit();
        }
      },
      child: Scaffold(
        backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
        appBar: _buildAppBar(isDarkMode),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            selection.active
                ? _buildSelectionBar(isDarkMode)
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildFiltrate(isDarkMode),
                      _buildConnect(isDarkMode),
                    ],
                  ),
            Expanded(child: _buildBody(context, isDarkMode)),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showAddMenu(context, isDarkMode),
          backgroundColor: const Color(0xFF0066CC),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          child: Icon(Icons.add, size: 28.sp),
        ),
      ),
    );
  }

  // ──────────────────────── AppBar ────────────────────────

  PreferredSizeWidget _buildAppBar(bool isDarkMode) {
    return AppBar(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: isDarkMode ? Colors.white : Colors.black,
          size: 20.sp,
        ),
        onPressed: () {
          if (context.canPop()) context.pop();
        },
      ),
      title: Text(
        '商务会议助手',
        style: TextStyle(
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      centerTitle: true,
    );
  }

  // ──────────────────────── 多选模式 ────────────────────────

  Widget _buildSelectionBar(bool isDarkMode) {
    final selection = ref.watch(meetingSelectionProvider);
    final visible =
        ref.watch(filteredMeetingListProvider).value ?? const <Meeting>[];
    final allIds = visible.map((m) => m.id).toSet();
    final allSelected =
        allIds.isNotEmpty && selection.ids.containsAll(allIds);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.w),
      child: Row(
        children: [
          GestureDetector(
            onTap: () =>
                ref.read(meetingSelectionProvider.notifier).exit(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.w),
              child: Text(
                '取消',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 15.sp,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              '已选 ${selection.ids.length} 项',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 15.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              final n = ref.read(meetingSelectionProvider.notifier);
              if (allSelected) {
                n.exit();
              } else {
                n.selectAll(allIds);
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.w),
              child: Text(
                allSelected ? '取消全选' : '全选',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 15.sp,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: selection.ids.isEmpty
                ? null
                : () => _confirmDeleteSelected(isDarkMode),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: EdgeInsets.symmetric(
                  horizontal: 12.w, vertical: 6.w),
              decoration: BoxDecoration(
                color: selection.ids.isEmpty
                    ? Colors.red.withValues(alpha: 0.3)
                    : Colors.red,
                borderRadius: BorderRadius.circular(50.w),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline,
                      color: Colors.white, size: 16.sp),
                  SizedBox(width: 4.w),
                  Text(
                    '删除',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSelected(bool isDarkMode) async {
    final selection = ref.read(meetingSelectionProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor:
            isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
        title: Text(
          '删除',
          style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontSize: 16.sp),
        ),
        content: Text(
          '确定要删除选中的 ${selection.ids.length} 项会议记录吗？',
          style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
              fontSize: 14.sp),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(meetingListProvider.notifier)
        .deleteMany(selection.ids.toList());
    ref.read(meetingSelectionProvider.notifier).exit();
  }

  // ──────────────────────── 筛选 / 连接 ────────────────────────

  Widget _buildFiltrate(bool isDarkMode) {
    final filter = ref.watch(meetingListFilterProvider);
    final list = ref.watch(filteredMeetingListProvider).value ?? const [];
    final label = filter.markedOnly
        ? '收藏文件 (${list.length})'
        : '全部文件 (${list.length})';
    return GestureDetector(
      onTap: () {
        ref.read(meetingListFilterProvider.notifier).update(
            (f) => f.copyWith(markedOnly: !f.markedOnly));
      },
      behavior: HitTestBehavior.translucent,
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Container(
            width: 32.w,
            height: 32.w,
            margin: EdgeInsets.symmetric(vertical: 10.w),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? MeetingUIUtils.getTranslucentWhite(0.05)
                  : MeetingUIUtils.getCardColor(isDarkMode),
              borderRadius: BorderRadius.circular(12.w),
              boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
            ),
            child: Icon(
              Icons.format_list_bulleted,
              color: isDarkMode ? Colors.white : Colors.black87,
              size: 20.sp,
            ),
          ),
          SizedBox(width: 5.w),
          Text(
            label,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnect(bool isDarkMode) {
    return GestureDetector(
      onTap: () => context.push('/devices'),
      child: Container(
        padding: EdgeInsets.all(5.w),
        margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
        decoration: BoxDecoration(
          color: isDarkMode
              ? MeetingUIUtils.getTranslucentWhite(0.05)
              : MeetingUIUtils.getCardColor(isDarkMode),
          borderRadius: BorderRadius.circular(50.w),
          boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32.w,
              height: 32.w,
              decoration: BoxDecoration(
                color: MeetingUIUtils.getButtonColor(isDarkMode),
                borderRadius: BorderRadius.circular(50.w),
              ),
              child: Icon(Icons.add, color: Colors.white, size: 20.sp),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 5.w),
              child: Text(
                '连接',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 14.sp,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── 列表 ────────────────────────

  Widget _buildBody(BuildContext context, bool isDarkMode) {
    final filtered = ref.watch(filteredMeetingListProvider);
    return filtered.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败：$e')),
      data: (list) {
        if (list.isEmpty) return _empty(isDarkMode);
        return RefreshIndicator(
          onRefresh: () =>
              ref.read(meetingListProvider.notifier).refresh(),
          child: ListView.builder(
            itemCount: list.length,
            padding: EdgeInsets.fromLTRB(12.w, 5.w, 12.w, 90.w),
            itemBuilder: (ctx, i) => _item(ctx, isDarkMode, list[i]),
          ),
        );
      },
    );
  }

  Widget _empty(bool isDarkMode) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mic_none_outlined,
                  size: 56.sp,
                  color: MeetingUIUtils.getSecondaryTextColor(isDarkMode)),
              SizedBox(height: 12.h),
              Text(
                '还没有会议记录',
                style: TextStyle(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  color: MeetingUIUtils.getTextColor(isDarkMode),
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                '点击右下角 + 开始第一次录音',
                style: TextStyle(
                    fontSize: 12.sp,
                    color: MeetingUIUtils.getSecondaryTextColor(isDarkMode)),
              ),
            ],
          ),
        ),
      );

  Widget _item(BuildContext context, bool isDarkMode, Meeting data) {
    final selection = ref.watch(meetingSelectionProvider);
    final selectionMode = selection.active;
    final selected = selection.ids.contains(data.id);
    final coord = ref.watch(meetingUploadCoordinatorProvider);

    return GestureDetector(
      onTap: () {
        if (selectionMode) {
          ref.read(meetingSelectionProvider.notifier).toggle(data.id);
        } else {
          context.push('/meeting/detail/${data.id}');
        }
      },
      onLongPressStart: (_) {
        if (selectionMode) return;
        Haptics.vibrate(HapticsType.success);
        ref.read(meetingSelectionProvider.notifier).enter(data.id);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 10.w),
        margin: EdgeInsets.symmetric(vertical: 5.w),
        decoration: BoxDecoration(
          color: isDarkMode
              ? MeetingUIUtils.getTranslucentWhite(0.05)
              : MeetingUIUtils.getCardColor(isDarkMode),
          borderRadius: BorderRadius.circular(12.w),
          boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
          border: selectionMode && selected
              ? Border.all(color: Colors.red, width: 1.5)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (selectionMode)
              Padding(
                padding: EdgeInsets.only(right: 10.w),
                child: Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? Colors.red
                      : (isDarkMode ? Colors.grey[400] : Colors.grey),
                  size: 22.sp,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title.isEmpty ? '未命名会议' : data.title,
                    style: TextStyle(
                      color: MeetingUIUtils.getTextColor(isDarkMode),
                      fontSize: 18.sp,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 5.w),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month,
                            size: 14.sp,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[500]),
                        SizedBox(width: 2.w),
                        Text(
                          DateFormat('yyyy-MM-dd HH:mm')
                              .format(data.createdAt),
                          style: TextStyle(
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[500],
                            fontSize: 12.sp,
                          ),
                        ),
                        SizedBox(width: 20.w),
                        Icon(Icons.access_time,
                            size: 14.sp,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[500]),
                        SizedBox(width: 2.w),
                        Text(
                          _formatDuration(data.durationMs ~/ 1000),
                          style: TextStyle(
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[500],
                            fontSize: 12.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 5.w, vertical: 2.w),
                        margin: EdgeInsets.only(top: 5.w),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.grey[900]
                              : Colors.grey[100],
                          borderRadius: BorderRadius.circular(4.w),
                        ),
                        child: Text(
                          _typeLabel(data.audioType),
                          style: TextStyle(
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                            fontSize: 10.sp,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _UploadIndicator(
                          meeting: data, coord: coord, isDark: isDarkMode),
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

  // ──────────────────────── 录音模式选择 ────────────────────────

  Future<void> _showAddMenu(BuildContext context, bool isDarkMode) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AddMenu(),
    );
  }

  static String _typeLabel(MeetingAudioType t) => switch (t) {
        MeetingAudioType.live => '现场录音',
        MeetingAudioType.audioVideo => '音、视频录音',
        MeetingAudioType.call => '通话录音',
      };

  static String _formatDuration(int total) {
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

// ──────────────────────── 上传状态指示 ────────────────────────

class _UploadIndicator extends StatefulWidget {
  const _UploadIndicator({
    required this.meeting,
    required this.coord,
    required this.isDark,
  });
  final Meeting meeting;
  final dynamic coord;
  final bool isDark;

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
        return Padding(
          padding: EdgeInsets.only(top: 5.w),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (uploading)
                SizedBox(
                  width: 22.sp,
                  height: 22.sp,
                  child: CircularProgressIndicator(
                    value: progress,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.red),
                    strokeWidth: 1,
                  ),
                ),
              SizedBox(
                width: 22.sp,
                height: 22.sp,
                child: Icon(
                  uploaded ? Icons.cloud_done : Icons.cloud_upload,
                  color: widget.isDark ? Colors.lightBlue : Colors.blue,
                  size: 16.sp,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ──────────────────────── 添加菜单（NavigationBarBottomSheet） ────────────────────────

class _AddMenu extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    void start(MeetingAudioType type) {
      Navigator.pop(context);
      ref.read(recorderProvider.notifier).setAudioType(type);
      context.push('/meeting/record');
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill(context, isDark, '现场录音', Icons.mic_rounded, Colors.red,
              onTap: () => start(MeetingAudioType.live)),
          _pill(context, isDark, '音、视频录音', Icons.videocam, Colors.green,
              onTap: () => start(MeetingAudioType.audioVideo)),
          _pill(context, isDark, '通话录音', Icons.phone, Colors.orange,
              onTap: () => start(MeetingAudioType.call)),
          _pill(context, isDark, '导入音频', Icons.file_upload_outlined,
              Colors.deepPurple, onTap: () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            navigator.pop();
            await _importAudio(ref, messenger);
          }),
          SizedBox(height: 24.h),
          GestureDetector(
            onTap: () => Navigator.pop(context),
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
          const SizedBox(height: 19),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, bool isDark, String title, IconData icon,
      Color color,
      {VoidCallback? onTap}) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220.w,
        height: 60.w,
        padding: EdgeInsets.all(5.w),
        margin: EdgeInsets.only(top: 15.w),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.grey[800]!.withValues(alpha: disabled ? 0.5 : 1)
              : Colors.white.withValues(alpha: disabled ? 0.5 : 1),
          borderRadius: BorderRadius.circular(60.w),
        ),
        child: Row(
          children: [
            Container(
              width: 46.w,
              height: 46.w,
              margin: EdgeInsets.only(right: 5.w),
              decoration: BoxDecoration(
                color: color.withValues(alpha: disabled ? 0.2 : 0.3),
                borderRadius: BorderRadius.circular(60.w),
              ),
              child: Icon(icon,
                  color: color.withValues(alpha: disabled ? 0.5 : 1)),
            ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: isDark
                      ? Colors.white
                          .withValues(alpha: disabled ? 0.5 : 1)
                      : Colors.black87
                          .withValues(alpha: disabled ? 0.5 : 1),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                size: 16.sp,
                color: Colors.grey
                    .withValues(alpha: disabled ? 0.5 : 1)),
            SizedBox(width: 5.w),
          ],
        ),
      ),
    );
  }
}

/// 系统 file picker 选音频 → 复制到 app docs → 写本地索引 → 异步触发 COS 上传。
Future<void> _importAudio(
    WidgetRef ref, ScaffoldMessengerState messenger) async {
  final picker = await FilePicker.platform
      .pickFiles(type: FileType.audio, allowMultiple: false);
  if (picker == null || picker.files.isEmpty) return;
  final picked = picker.files.single;
  final srcPath = picked.path;
  if (srcPath == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('无法读取选中的音频文件')),
    );
    return;
  }

  final id = const Uuid().v4();
  final docs = await getApplicationDocumentsDirectory();
  final ext = picked.extension ?? 'm4a';
  final destPath = '${docs.path}/meetings/audio_$id.$ext';
  await File(destPath).parent.create(recursive: true);
  await File(srcPath).copy(destPath);

  final m = Meeting(
    id: id,
    title: picked.name,
    createdAt: DateTime.now(),
    durationMs: 0,
    audioType: MeetingAudioType.audioVideo,
    audioPath: destPath,
  );
  await ref.read(meetingListProvider.notifier).add(m);
  ref
      .read(meetingUploadCoordinatorProvider)
      .uploadInBackground(id);

  messenger.showSnackBar(
    SnackBar(content: Text('已导入「${picked.name}」并开始上传')),
  );
}
