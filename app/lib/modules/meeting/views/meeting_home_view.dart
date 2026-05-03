import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:haptic_feedback/haptic_feedback.dart';

import '../../../core/services/log_service.dart';
import '../../../core/theme/app_colors.dart';
import '../bindings/meeting_connect_binding.dart';
import '../bindings/meeting_details_binding.dart';
import 'meeting_connect_view.dart';
import 'meeting_details_view.dart';
import '../controllers/meeting_home_controller.dart';
import '../model/meeting_model.dart';
import '../utils/meeting_ui_utils.dart';
import 'bottomSheet/edit_title_bottom_sheet.dart';
import '../../../../data/models/user_Info.dart';

///会议主页面，提供会议列表、会议详情、会议设置
class MeetingHomeView extends StatefulWidget {
  const MeetingHomeView({super.key});

  @override
  State<MeetingHomeView> createState() => _MeetingHomeViewState();
}

class _MeetingHomeViewState extends State<MeetingHomeView>
    with AutomaticKeepAliveClientMixin {
  final _controller = Get.put(MeetingHomeController());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_controller.isSelectionMode.value,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _controller.isSelectionMode.value) {
          _controller.exitSelectionMode();
          return;
        }
        _controller.onPopInvokedWithResult(didPop, result);
      },
      child: Scaffold(
        backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
        appBar: _buildAppBar(context, isDarkMode),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Obx(
              () => _controller.isSelectionMode.value
                  ? _buildSelectionBar(isDarkMode)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildFiltrate(isDarkMode),
                        if (_controller.meetingController.type == 0)
                          _buildConnect(isDarkMode),
                      ],
                    ),
            ),
            Expanded(
              child: _buildBody(context, isDarkMode),
            ),
          ],
        ),
      ),
    );
  }

  // 多选模式操作栏：取消 / 全选 / 删除
  Widget _buildSelectionBar(bool isDarkMode) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.w),
      child: Row(
        children: [
          GestureDetector(
            onTap: _controller.exitSelectionMode,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.w),
              child: Text(
                'cancel'.tr,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 15.sp,
                ),
              ),
            ),
          ),
          12.horizontalSpace,
          Expanded(
            child: Obx(
              () => Text(
                '已选 ${_controller.selectedIds.length} 项',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: _controller.toggleSelectAll,
            behavior: HitTestBehavior.opaque,
            child: Obx(
              () => Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.w),
                child: Text(
                  _controller.isAllSelected ? '取消全选' : '全选',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 15.sp,
                  ),
                ),
              ),
            ),
          ),
          Obx(
            () => GestureDetector(
              onTap: _controller.selectedIds.isEmpty
                  ? null
                  : () => _confirmDeleteSelected(isDarkMode),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.w),
                decoration: BoxDecoration(
                  color: _controller.selectedIds.isEmpty
                      ? Colors.red.withValues(alpha: 0.3)
                      : Colors.red,
                  borderRadius: BorderRadius.circular(50.w),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline,
                        color: Colors.white, size: 16.sp),
                    4.horizontalSpace,
                    Text(
                      'delete'.tr,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSelected(bool isDarkMode) {
    Get.dialog(
      AlertDialog(
        backgroundColor: isDarkMode ? AppColors.cardBackground : Colors.white,
        title: Text(
          'delete'.tr,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
            fontSize: 16.sp,
          ),
        ),
        content: Text(
          '确定要删除选中的 ${_controller.selectedIds.length} 项会议记录吗？',
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black87,
            fontSize: 14.sp,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              _controller.deleteSelectedMeetings();
            },
            child: Text(
              'delete'.tr,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltrate(bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        _controller.meetingController.scaffoldKey.currentState?.openDrawer();
      },
      behavior: HitTestBehavior.translucent,
      child: Row(
        children: [
          12.horizontalSpace,
          Container(
            width: 32.w,
            height: 32.w,
            margin: EdgeInsets.symmetric(
              vertical: 10.w,
            ),
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
          5.horizontalSpace,
          Obx(
            () => Text(
              '${_controller.filtrateType.value.isNotEmpty ? _controller.filtrateType : 'allFiles'.tr}(${_controller.dataList.length})', // 对应中文：全部文件
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnect(bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        Get.to(
          () => const MeetingConnectView(),
          binding: MeetingConnectBinding(),
        );
      },
      child: Container(
        padding: EdgeInsets.all(5.w),
        margin: EdgeInsets.symmetric(
          horizontal: 12.w,
          vertical: 10.w,
        ),
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
              child: Icon(
                Icons.add,
                color: Colors.white,
                size: 20.sp,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 5.w),
              child: Text(
                'connect'.tr, // 对应中文：连接
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 14.sp,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // 构建应用栏
  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDarkMode) {
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
        // GoRouter shell branch 模式下 Get.back() 弹的是 root navigator，
        // 拿不到我们这个子分支的栈；用 Navigator.of(context).maybePop()
        // 让 Flutter 走最近的 navigator（即 shell branch），能正常返回。
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'conferenceAssistant'.tr, // 商务会议助手
        style: TextStyle(
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(28.w),
        child: Obx(() {
          final _ = User.refreshTick.value;
          final remain = User.isLoggedIn() ? User.instance.meetintegral : 0;
          final total = User.isLoggedIn() ? User.instance.meettotalintegral : 0;
          final double fraction =
              total > 0 ? (remain / total).clamp(0.0, 1.0).toDouble() : 0.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: EdgeInsets.only(right: 12.w, bottom: 4.w),
                alignment: Alignment.centerRight,
                child: Text(
                  _formatHms(remain),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.maxWidth * fraction;
                  return Stack(
                    children: [
                      Container(
                        height: 2.w,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(2.w),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: barWidth,
                          height: 2.w,
                          decoration: BoxDecoration(
                            color: MeetingUIUtils.getButtonColor(isDarkMode),
                            borderRadius: BorderRadius.circular(2.w),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          );
        }),
      ),
    );
  }

  // 构建主体内容
  Widget _buildBody(BuildContext context, bool isDarkMode) {
    return Obx(
      () => ListView.builder(
        itemCount: _controller.dataList.length,
        padding: EdgeInsets.fromLTRB(12.w, 5.w, 12.w, 90.w),
        itemBuilder: (BuildContext context, int index) {
          MeetingModel data =
              MeetingModel.fromJson(_controller.dataList[index]);
          return _item(context, isDarkMode, data);
        },
      ),
    );
  }

  Widget _item(BuildContext context, bool isDarkMode, MeetingModel data) {
    String tasktypeText = '';
    switch (data.tasktype) {
      case 0:
        tasktypeText = '';
        break;
      case 1:
        tasktypeText = 'transcribing'.tr; // 对应中文：正在转写...
        break;
      case 2:
        tasktypeText = 'transcribing'.tr; // 对应中文：正在转写...
        break;
      case 3:
        tasktypeText = 'summarizing'.tr; // 对应中文：正在总结...
        break;
      case 4:
        tasktypeText = 'summarizing'.tr; // 对应中文：正在总结...
        break;
      case 5:
        tasktypeText = 'summaryComplete'.tr; // 对应中文：总结完成
        break;
      case 10001:
        tasktypeText = 'summaryFailedShort'.tr; // 总结失败
        break;
      case 10002:
        tasktypeText = 'transcriptionFailedShort'.tr; // 转写失败
        break;
      default:
        tasktypeText = '';
    }

    return Obx(() {
      final bool selectionMode = _controller.isSelectionMode.value;
      final bool selected = _controller.selectedIds.contains(data.id);
      return GestureDetector(
        onTap: () {
          if (selectionMode) {
            _controller.toggleSelection(data.id);
          } else {
            LogService.instance.talker.info(
                '[MeetingHomeView] tap meeting id=${data.id} '
                'title=${data.title} tasktype=${data.tasktype} '
                'audiourl=${data.audiourl}');
            Get.to(
              () => const MeetingDetailsView(),
              binding: MeetingDetailsBinding(id: data.id),
              arguments: {'id': data.id},
            );
          }
        },
        onLongPressStart: (LongPressStartDetails details) {
          if (selectionMode) return;
          Haptics.vibrate(HapticsType.success);
          _controller.enterSelectionMode(data.id);
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
                    size: 22.w,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
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
                  Icon(
                    Icons.calendar_month,
                    size: 14.w,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                  ),
                  2.horizontalSpace,
                  Text(
                    DateUtil.formatDateMs(
                      data.creationtime,
                      format: DateFormats.y_mo_d_h_m,
                    ),
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                      fontSize: 12.sp,
                    ),
                  ),
                  20.horizontalSpace,
                  Icon(
                    Icons.access_time,
                    size: 14.w,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                  ),
                  2.horizontalSpace,
                  Text(
                    _formatDateSeconds(data.seconds),
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.w),
                  margin: EdgeInsets.only(top: 5.w),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(4.w),
                  ),
                  child: Text(
                    data.type,
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 10.sp,
                    ),
                  ),
                ),
                const Spacer(),
                Obx(() {
                  Map uploadData =
                      _controller.meetingUploadService.uploadList.firstWhere(
                    (element) => element['id'] == data.id,
                    orElse: () => {},
                  );
                  return uploadData.isNotEmpty
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            if (uploadData['id'] ==
                                _controller
                                    .meetingUploadService.meetingId.value)
                              Obx(
                                () => SizedBox(
                                  width: 20.w,
                                  height: 20.w,
                                  child: CircularProgressIndicator(
                                    value: _controller.meetingUploadService
                                        .uploadProgress.value,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                            Colors.red),
                                    strokeWidth: 1.w,
                                  ),
                                ),
                              ),
                            SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: Icon(
                                uploadData['audiourl'].isNotEmpty
                                    ? Icons.cloud_done
                                    : Icons.cloud_upload,
                                color:
                                    isDarkMode ? Colors.lightBlue : Colors.blue,
                                size: 16.w,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox();
                }),
                Padding(
                  padding: EdgeInsets.only(top: 5.w),
                  child: Text(
                    tasktypeText,
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 10.sp,
                    ),
                  ),
                ),
              ],
            ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ignore: unused_element
  void _onLongPressItem(BuildContext context, bool isDarkMode,
      LongPressStartDetails details, MeetingModel data) {
    Haptics.vibrate(HapticsType.success);
    RenderBox? renderBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx + 110, // 菜单显示位置X轴坐标
        details.globalPosition.dy - 40, // 菜单显示位置Y轴坐标
      ),
      Offset.zero & renderBox.size,
    );

    showMenu(
      context: context,
      position: position,
      color: isDarkMode ? AppColors.cardBackground : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
      ),
      items: [
        _popupMenuEntry(
          Icon(
            Icons.edit_calendar,
            size: 20.w,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          'edit'.tr, // 编辑
          isDarkMode ? Colors.white : Colors.black87,
          () {
            final dotIndex = data.title.lastIndexOf('.');
            _controller.titleController.text =
                dotIndex != -1 ? data.title.substring(0, dotIndex) : data.title;
            _controller.titleCSuffix =
                data.title.substring(dotIndex, data.title.length);
            Get.bottomSheet(
              EditTitleBottomSheet(data.id),
              isScrollControlled: true,
              backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(12.r),
                ),
              ),
            );
          },
        ),
        _popupMenuEntry(
          Icon(
            Icons.delete_outline,
            size: 20.w,
            color: isDarkMode ? Colors.red[700] : Colors.red,
          ),
          'delete'.tr, // 删除
          isDarkMode ? Colors.red[700]! : Colors.red,
          () {
            _controller.deleteMeeting(data.id, data.filepath);
          },
        ),
      ],
    );
  }

  PopupMenuEntry _popupMenuEntry(
    Icon icon,
    String title,
    Color color,
    Function() onTap,
  ) {
    return PopupMenuItem(
      onTap: onTap,
      child: SizedBox(
        width: 140.w,
        child: Row(
          children: [
            icon,
            8.horizontalSpace,
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 14.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateSeconds(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      int minutes = seconds ~/ 60;
      int remainingSeconds = seconds % 60;
      return '${minutes}m ${remainingSeconds}s';
    } else {
      int hours = seconds ~/ 3600;
      int remainingMinutes = (seconds % 3600) ~/ 60;
      int remainingSeconds = seconds % 60;
      return '${hours}h ${remainingMinutes}m ${remainingSeconds}s';
    }
  }

  String _formatHms(int seconds) {
    final sec = seconds < 0 ? 0 : seconds; // 确保秒数非负
    final d = Duration(seconds: sec);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(h)}:${twoDigits(m)}:${twoDigits(s)}';
  }
}
