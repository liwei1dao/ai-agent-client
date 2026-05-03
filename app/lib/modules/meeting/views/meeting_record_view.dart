import 'dart:ui' as ui;
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../controllers/meeting_record_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/meeting/meeting_task_service.dart';

/// 会议录音退出操作
enum _MeetingRecordExitAction {
  saveAndEnd,
  endWithoutSave,
  continueInBackground,
  cancel,
}

/// 会议录音页面
class MeetingRecordView extends GetView<MeetingRecordController> {
  const MeetingRecordView({super.key});

  void _notifyMeetingLocalImport() {
    if (!Get.isRegistered<MeetingTaskService>()) return;
    Get.find<MeetingTaskService>().requestLocalImport();
  }

  void _deleteControllerAfterPop() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (Get.isRegistered<MeetingRecordController>()) {
        Get.delete<MeetingRecordController>(force: true);
      }
    });
  }

  /// 显示退出确认弹窗
  Future<_MeetingRecordExitAction?> _showExitConfirmDialog(bool isDarkMode) {
    return Get.dialog<_MeetingRecordExitAction>(
      Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        backgroundColor: isDarkMode ? AppColors.cardBackground : Colors.white,
        child: Container(
          width: 320.w,
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: isDarkMode ? AppColors.cardBackground : Colors.white,
            borderRadius: BorderRadius.circular(16.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  color: (isDarkMode ? Colors.white : Colors.blue)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(28.r),
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 28.sp,
                  color: isDarkMode ? Colors.white : Colors.blue,
                ),
              ),
              SizedBox(height: 14.h),
              Text(
                'meetingRecordExitTitle'.tr, // 退出录音
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'meetingRecordExitMessage'.tr, // 请选择离开后的操作
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  height: 1.4,
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),
              SizedBox(height: 18.h),
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: () => Get.back(
                        result: _MeetingRecordExitAction.saveAndEnd,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            isDarkMode ? AppColors.primary : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'meetingRecordEndAndSave'.tr, // 结束录音并保存
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    OutlinedButton(
                      onPressed: () => Get.back(
                        result: _MeetingRecordExitAction.continueInBackground,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isDarkMode ? Colors.white70 : Colors.grey[800],
                        side: BorderSide(
                          color:
                              isDarkMode ? Colors.white30 : Colors.grey[400]!,
                        ),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(
                        'meetingRecordContinueInBackground'.tr, // 后台继续录音
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    OutlinedButton(
                      onPressed: () => Get.back(
                        result: _MeetingRecordExitAction.endWithoutSave,
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            isDarkMode ? Colors.red[300] : Colors.red[600],
                        side: BorderSide(
                          color:
                              isDarkMode ? Colors.red[300]! : Colors.red[300]!,
                        ),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: Text(
                        'meetingRecordEndWithoutSave'.tr, // 结束录音不保存
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: 10.h),
                    TextButton(
                      onPressed: () =>
                          Get.back(result: _MeetingRecordExitAction.cancel),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                          side: BorderSide(
                            color:
                                isDarkMode ? Colors.white24 : Colors.grey[300]!,
                          ),
                        ),
                      ),
                      child: Text(
                        'cancel'.tr, // 取消
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    controller.applyRouteArgumentsIfIdle();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (!controller.isRecording.value) {
          Get.back();
          _deleteControllerAfterPop();
          return;
        }

        final action = await _showExitConfirmDialog(isDarkMode);
        if (action == null || action == _MeetingRecordExitAction.cancel) {
          return;
        }

        switch (action) {
          case _MeetingRecordExitAction.saveAndEnd:
            await controller.saveTitleChange();
            final saved = await controller.saveRecording();
            if (saved) {
              _notifyMeetingLocalImport();
              Get.back(result: 'meeting_record_saved');
              _deleteControllerAfterPop();
            }
            return;
          case _MeetingRecordExitAction.endWithoutSave:
            final discarded = await controller.discardRecording();
            if (discarded) {
              Get.back(result: 'meeting_record_discarded');
              _deleteControllerAfterPop();
            }
            return;
          case _MeetingRecordExitAction.continueInBackground:
            await controller.saveTitleChange();
            await controller.showBackgroundRecordingIndicator();
            Get.back(result: 'meeting_record_background');
            return;
          case _MeetingRecordExitAction.cancel:
            return;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              color: isDarkMode ? Colors.white : Colors.black,
              size: 20.sp,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Obx(() {
            if (controller.isEditingTitle.value) {
              return SizedBox(
                height: 40,
                child: TextField(
                  controller: controller.titleEditingController,
                  focusNode: controller.titleFocusNode,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 18,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'enterFileName'.tr,
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) {
                    controller.saveTitleChange();
                  },
                ),
              );
            } else {
              return GestureDetector(
                onTap: () {
                  controller.startTitleEditing();
                },
                child: Text(
                  controller.newName.value,
                  style: const TextStyle(fontSize: 18),
                ),
              );
            }
          }),
          elevation: 0,
          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
          actions: [
            Obx(() {
              if (controller.isEditingTitle.value) {
                return IconButton(
                  icon: const Icon(Icons.check),
                  onPressed: controller.saveTitleChange,
                );
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              // 简化为单一音频界面，移除不必要的TabBar
              Expanded(
                child: _buildAudioTab(context, isDarkMode),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建音频标签页
  Widget _buildAudioTab(BuildContext context, bool isDarkMode) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用LayoutBuilder获取准确的屏幕宽度
        final screenWidth = constraints.maxWidth;

        return Column(
          children: [
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildRecordTypeBadge(isDarkMode),
              ),
            ),
            SizedBox(height: 12.h),
            // 实时流动波形显示区域
            Container(
              height: 200.h,
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDarkMode
                      ? [
                          const Color(0xFF1A1A1A),
                          const Color(0xFF2A2A2A),
                          const Color(0xFF1A1A1A),
                        ]
                      : [
                          const Color(0xFFF8F9FA),
                          const Color(0xFFFFFFFF),
                          const Color(0xFFF8F9FA),
                        ],
                ),
                //borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDarkMode
                        ? Colors.black.withValues(alpha: 0.3)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: Stack(
                  children: [
                    Obx(() {
                      final size = Size(screenWidth, 200.h);
                      final waveColor =
                          isDarkMode ? Colors.white : Colors.black87;

                      return Center(
                        child: AudioWaveforms(
                          size: size,
                          recorderController: controller.waveformController,
                          backgroundColor: Colors.transparent,
                          waveStyle: WaveStyle(
                            waveThickness: 1.w,
                            spacing: 2.w,
                            waveCap: StrokeCap.round,
                            showMiddleLine: true,
                            middleLineColor: Colors.redAccent.withValues(
                              alpha: controller.timerStatus.value ==
                                      TimerStatus.running
                                  ? 0.9
                                  : 0.0,
                            ),
                            middleLineThickness: 1.w,
                            showTop: true,
                            showBottom: true,
                            extendWaveform: true,
                            waveColor: waveColor,
                            scaleFactor: 90,
                          ),
                        ),
                      );
                    }),

                    // 录音状态指示器
                    Obx(() {
                      if (controller.timerStatus.value == TimerStatus.running) {
                        return Positioned(
                          top: 8.h,
                          right: 8.w,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6.w,
                              vertical: 2.h,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8.r),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 4.w,
                                  height: 4.h,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 3.w),
                                Text(
                                  'REC',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24.h),
            // 时间显示 - 只包装需要响应式更新的Text widget
            Obx(() => Text(
                  controller.formatTime(controller.milliseconds.value),
                  style: TextStyle(
                    fontSize: 48.sp,
                    fontWeight: FontWeight.normal,
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontFeatures: const [
                      ui.FontFeature.tabularFigures()
                    ], // 使用等宽数字，避免跳动
                  ),
                )),
            const Spacer(),
            _buildBottomBar(context, isDarkMode),
            SizedBox(height: 42.h),
          ],
        );
      },
    );
  }

  // 底部操作栏
  Widget _buildBottomBar(BuildContext context, bool isDarkMode) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 收藏按钮
          _buildActionButton(
            onTap: controller.toggleMarked,
            child: Obx(() => Icon(
                  controller.isMarked.value
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 36.sp,
                  color:
                      controller.isMarked.value ? Colors.orange : Colors.grey,
                )),
            radius: 32.w,
            tooltip: controller.isMarked.value
                ? 'unmarkFavorite'.tr
                : 'markFavorite'.tr,
            isDarkMode: isDarkMode,
          ),
          // 录音按钮
          _buildActionButton(
            onTap: controller.toggleRecording,
            child: Obx(() => Icon(
                  controller.timerStatus.value == TimerStatus.running
                      ? Icons.pause
                      : Icons.play_arrow_rounded,
                  size: 44.sp,
                  color: Colors.red,
                )),
            radius: 40.w,
            tooltip: controller.timerStatus.value == TimerStatus.running
                ? 'pauseRecording'.tr
                : 'startRecording'.tr,
            isDarkMode: isDarkMode,
          ),
          // 完成按钮
          _buildActionButton(
            onTap: () => _bottomSheet(
              isDarkMode,
              MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 36.sp,
              color: Colors.green,
            ),
            radius: 32.w,
            tooltip: 'finishRecording'.tr,
            isDarkMode: isDarkMode,
          ),
        ],
      ),
    );
  }

  // 统一的操作按钮组件
  Widget _buildActionButton({
    required VoidCallback onTap,
    required Widget child,
    required double radius,
    required String tooltip,
    required bool isDarkMode,
  }) {
    final Color bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: bgColor,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordTypeBadge(bool isDarkMode) {
    return Obx(() {
      String label;
      IconData icon;
      Color color;

      switch (controller.audioType.value) {
        case 0:
          label = 'liveRecording'.tr;
          icon = Icons.mic_rounded;
          color = Colors.red;
          break;
        case 1:
          label = 'audioVideoRecording'.tr;
          icon = Icons.videocam_rounded;
          color = Colors.green;
          break;
        case 2:
        default:
          label = 'callRecording'.tr;
          icon = Icons.phone_in_talk_rounded;
          color = Colors.orange;
          break;
      }

      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDarkMode ? 0.25 : 0.12),
          borderRadius: BorderRadius.circular(999.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18.sp,
              color: isDarkMode ? Colors.white : color,
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      );
    });
  }

  // 底部编辑弹窗
  void _bottomSheet(bool isDarkMode, double bottomInset) async {
    //如果当前计时器在运行，先暂停录音，避免编辑时继续录音
    if (controller.timerStatus.value == TimerStatus.running) {
      await controller.toggleRecording();
    }

    Get.bottomSheet(
      Container(
        padding: EdgeInsets.only(
          left: 20.w,
          right: 20.w,
          top: 20.w,
          bottom: bottomInset + 20.w,
        ),
        decoration: BoxDecoration(
          color: isDarkMode ? AppColors.darkBackground : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽指示器
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 20.h),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),

            // 标题
            Text(
              'editMeetingTitle'.tr, // 对应中文：修改会议标题（非必填）
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: 16.h),

            // 输入框
            Container(
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.white10 : Colors.grey[100],
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: isDarkMode ? Colors.white24 : Colors.grey[300]!,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: controller.titleEditingController,
                autofocus: true,
                maxLength: 50,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16.sp,
                ),
                decoration: InputDecoration(
                  hintText: 'enterFileName'.tr,
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.white60 : Colors.grey[600],
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16.w),
                  counterText: '',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) async {
                  await controller.saveTitleChange();
                  final saved = await controller.saveRecording();
                  if (saved) {
                    _notifyMeetingLocalImport();
                    Get.back();
                  }
                },
              ),
            ),

            SizedBox(height: 24.h),

            // 按钮组
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: Get.back,
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          isDarkMode ? Colors.white70 : Colors.grey[700],
                      side: BorderSide(
                        color: isDarkMode ? Colors.white30 : Colors.grey[400]!,
                      ),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text('cancel'.tr),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await controller.saveTitleChange();
                      final saved = await controller.saveRecording();
                      if (saved) {
                        _notifyMeetingLocalImport();
                        Get.back(); //关闭弹窗
                        Get.back(result: 'meeting_record_saved'); //回退到会议记录页面
                        _deleteControllerAfterPop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDarkMode ? AppColors.primary : Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      elevation: 2,
                    ),
                    child: Text('confirm'.tr),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
    );
  }
}
