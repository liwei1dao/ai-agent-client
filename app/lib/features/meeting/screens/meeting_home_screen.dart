import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../providers/meeting_providers.dart';
import '../widgets/meeting_list_item.dart';
import '../widgets/record_mode_sheet.dart';

/// 会议模块入口 — 列表 + 右下角 `+` FAB（点击弹模式选择 sheet）。
class MeetingHomeScreen extends ConsumerWidget {
  const MeetingHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: const _MeetingFilesTab(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showRecordModeSheet(context, ref),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }
}

/// 顶部筛选条 — 复用源项目 [meeting_home_view._buildFiltrate](
/// /Users/liwei/work/flutter/deepvoice_client_liwei/lib/modules/meeting/views/meeting_home_view.dart) 风格：
/// 左：圆角图标方块 + "全部文件 (N)" 加粗
/// 右：圆角胶囊 "+ 连接" 跳到设备页
class _FiltrateBar extends StatelessWidget {
  const _FiltrateBar({
    required this.total,
    required this.filter,
    required this.onConnect,
    required this.onClearMarkedFilter,
  });

  final int total;
  final MeetingListFilter filter;
  final VoidCallback onConnect;
  final VoidCallback onClearMarkedFilter;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final label = filter.markedOnly
        ? '收藏 ($total)'
        : '全部文件 ($total)';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: filter.markedOnly ? onClearMarkedFilter : null,
            behavior: HitTestBehavior.translucent,
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.format_list_bulleted,
                    color: colors.text1,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: colors.text1,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onConnect,
            child: Container(
              padding: const EdgeInsets.all(5),
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 18),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('连接',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MeetingFilesTab extends ConsumerWidget {
  const _MeetingFilesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredMeetingListProvider);
    final selection = ref.watch(meetingSelectionProvider);
    final filter = ref.watch(meetingListFilterProvider);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: selection.active
          ? _selectionAppBar(context, ref, filtered.value ?? const [])
          : AppBar(
              centerTitle: true,
              title: const Text(
                '商务会议助手',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              elevation: 0.5,
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _showSearchSheet(context, ref),
                ),
                IconButton(
                  icon: Icon(filter.markedOnly
                      ? Icons.star_rounded
                      : Icons.star_border_rounded),
                  color: filter.markedOnly ? Colors.amber : null,
                  onPressed: () {
                    ref.read(meetingListFilterProvider.notifier).update(
                        (f) => f.copyWith(markedOnly: !f.markedOnly));
                  },
                ),
              ],
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!selection.active)
            _FiltrateBar(
              total: filtered.value?.length ?? 0,
              filter: filter,
              onConnect: () => context.push('/devices'),
              onClearMarkedFilter: () {
                ref.read(meetingListFilterProvider.notifier).update(
                    (f) => f.copyWith(markedOnly: false));
              },
            ),
          Expanded(
            child: filtered.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (list) {
                if (list.isEmpty) {
                  return _empty(colors, filter);
                }
                return RefreshIndicator(
                  onRefresh: () =>
                      ref.read(meetingListProvider.notifier).refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(top: 5, bottom: 100),
                    itemCount: list.length,
                    itemBuilder: (ctx, i) {
                      final m = list[i];
                      final selected = selection.ids.contains(m.id);
                      return MeetingListItem(
                        meeting: m,
                        selected: selected,
                        selectionMode: selection.active,
                        onTap: () {
                          if (selection.active) {
                            ref
                                .read(meetingSelectionProvider.notifier)
                                .toggle(m.id);
                          } else {
                            context.push('/meeting/detail/${m.id}');
                          }
                        },
                        onLongPress: () {
                          ref
                              .read(meetingSelectionProvider.notifier)
                              .enter(m.id);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(AppColors colors, MeetingListFilter filter) {
    final isFiltered =
        filter.query.isNotEmpty || filter.markedOnly || filter.audioType != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFiltered ? Icons.filter_alt_off : Icons.mic_none_outlined,
              size: 56,
              color: colors.text2.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              isFiltered ? '没有符合条件的会议' : '还没有会议记录',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.text1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isFiltered ? '尝试调整搜索或筛选条件' : '点击下方按钮开始第一次录音',
              style: TextStyle(fontSize: 12, color: colors.text2),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _selectionAppBar(
      BuildContext context, WidgetRef ref, List<Meeting> visible) {
    final selection = ref.watch(meetingSelectionProvider);
    final allIds = visible.map((m) => m.id).toSet();
    final allSelected =
        allIds.isNotEmpty && selection.ids.containsAll(allIds);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () =>
            ref.read(meetingSelectionProvider.notifier).exit(),
      ),
      title: Text('已选 ${selection.ids.length} 项'),
      actions: [
        TextButton(
          onPressed: () {
            final notifier = ref.read(meetingSelectionProvider.notifier);
            if (allSelected) {
              notifier.exit();
            } else {
              notifier.selectAll(allIds);
            }
          },
          child: Text(allSelected ? '取消全选' : '全选'),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          color: AppTheme.danger,
          onPressed: selection.ids.isEmpty
              ? null
              : () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final selection = ref.read(meetingSelectionProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除？'),
        content: Text('已选 ${selection.ids.length} 个会议，删除后无法恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
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

  void _showSearchSheet(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController(
        text: ref.read(meetingListFilterProvider).query);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final padding = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('搜索会议',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '会议标题关键字',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => ref
                    .read(meetingListFilterProvider.notifier)
                    .update((f) => f.copyWith(query: v)),
                onSubmitted: (_) => Navigator.pop(ctx),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    ctrl.clear();
                    ref
                        .read(meetingListFilterProvider.notifier)
                        .update((f) => f.copyWith(query: ''));
                  },
                  child: const Text('清空'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

