import 'dart:math';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../controllers/meeting_details_controller.dart';
import '../utils/meeting_ui_utils.dart';
import 'tabs/mind_map_tab.dart';
import 'bottomSheet/more_bottom_sheet.dart';
import 'tabs/overview_tab.dart';
import 'bottomSheet/share_bottom_sheet.dart';
import 'tabs/speech_tab.dart';
import 'tabs/summary_tab.dart';

///会议音频详情页面，提供会议音频播放、会议音频分享、会议音频更多操作
class MeetingDetailsView extends GetView<MeetingDetailsController> {
  const MeetingDetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      onPopInvokedWithResult: controller.popInvokedWithResult,
      child: Scaffold(
        backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
        appBar: _buildAppBar(context, isDarkMode),
        body: _buildBody(isDarkMode),
      ),
    );
  }

  // 构建应用栏
  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDarkMode) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Obx(
        () => AppBar(
          backgroundColor: isDarkMode
              ? (controller.isTop.value ? Colors.black : Colors.grey[900])
              : (controller.isTop.value ? Colors.grey[50] : Colors.grey[200]),
          surfaceTintColor: Colors.transparent,
          elevation: 0.5,
          leading: controller.isSpeakerText.value
              ? GestureDetector(
                  onTap: () {
                    controller.isSpeakerText.value = false;
                    controller.editSpeakerTextId.value = 0;
                    controller.editSpeakerTextList = [];
                  },
                  child: Center(
                    child: Text(
                      'cancel'.tr,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios,
                    color: isDarkMode ? Colors.white : Colors.black,
                    size: 20.sp,
                  ),
                  onPressed: () => Get.back(),
                ),
          title: Obx(
            () => Opacity(
              opacity:
                  (1 - (controller.dragOffset.value / 100.w)).clamp(0.0, 1.0),
              child: Container(
                width: 170.w,
                padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 3.w),
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? Colors.grey[850] ?? const Color(0xFF1F1F1F)
                      : Colors.grey[200],
                  borderRadius: BorderRadius.circular(30.r),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        if (controller.meetingData.value.filepath.isEmpty) {
                          controller.downloadAudio();
                        } else {
                          // 检查播放器是否已准备好
                          if (!controller.isPlayerReady.value) {
                            Get.snackbar(
                              'error'.tr,
                              'playerNotReady'.tr, // 音频播放器未准备好，请稍候
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 2),
                            );
                            return;
                          }

                          try {
                            if (controller.isPlay.value) {
                              await controller.playerController.pausePlayer();
                            } else {
                              await controller.playerController.startPlayer();
                            }
                          } catch (e) {
                            Get.snackbar(
                              'error'.tr,
                              "${'playFailed'.tr}: ${e.toString()}", // 播放失败
                              snackPosition: SnackPosition.BOTTOM,
                              duration: const Duration(seconds: 2),
                            );
                          }
                        }
                      },
                      child: Obx(
                        () => !controller.isLoading.value &&
                                controller.meetingData.value.filepath.isEmpty
                            ? Obx(
                                () => Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    if (controller.isDownload.value)
                                      SizedBox(
                                        width: 26.w,
                                        height: 26.w,
                                        child: CircularProgressIndicator(
                                          value:
                                              controller.downloadProgress.value,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                  Color>(Colors.red),
                                          strokeWidth: 2.w,
                                        ),
                                      ),
                                    Icon(
                                      Icons.download_for_offline,
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                      size: 30.w,
                                    ),
                                  ],
                                ),
                              )
                            : Icon(
                                controller.isPlay.value
                                    ? Icons.pause_circle
                                    : Icons.play_circle,
                                color: isDarkMode ? Colors.white : Colors.black,
                                size: 30.w,
                              ),
                      ),
                    ),
                    4.horizontalSpace,
                    GestureDetector(
                      onTap: () {
                        if (controller.isSpeakerText.value) return;
                        controller.dragOffset.value = 210.w;
                        controller.isTop.value = false;
                      },
                      behavior: HitTestBehavior.translucent,
                      child: SizedBox(
                        width: 130.w,
                        height: 30.w,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AudioFileWaveforms(
                            size: Size(350.w, 30.w),
                            playerController: controller.playerController,
                            waveformData: List.generate(88, (int index) {
                              return 0.01 + Random().nextDouble() * 0.09;
                            }),
                            waveformType: WaveformType.fitWidth,
                            enableSeekGesture: false,
                            playerWaveStyle: PlayerWaveStyle(
                              spacing: 4.w,
                              waveThickness: 2.w,
                              fixedWaveColor: Colors.grey[400]!,
                              liveWaveColor: Colors.red,
                              seekLineColor: Colors.red,
                              scaleFactor: 200,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          centerTitle: true,
          actions: [
            if (controller.isSpeakerText.value)
              GestureDetector(
                onTap: controller.editSpeakerText,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.w,
                    vertical: 6.w,
                  ),
                  child: Text(
                    'save'.tr,
                    style: TextStyle(
                      color: isDarkMode ? AppColors.primary : Colors.blue,
                      fontSize: 16.sp,
                    ),
                  ),
                ),
              ),
            if (!controller.isSpeakerText.value)
              IconButton(
                icon: Icon(
                  Icons.ios_share,
                  color: isDarkMode ? Colors.white : Colors.black,
                  size: 22.sp,
                ),
                onPressed: () {
                  Get.bottomSheet(
                    const ShareBottomSheet(),
                    isScrollControlled: true,
                    backgroundColor:
                        isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12.r),
                      ),
                    ),
                  );
                },
              ),
            if (!controller.isSpeakerText.value)
              IconButton(
                icon: Container(
                  width: 22.w,
                  height: 22.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                      color: isDarkMode ? Colors.white : Colors.black,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.more_horiz,
                    color: isDarkMode ? Colors.white : Colors.black,
                    size: 16.sp,
                  ),
                ),
                onPressed: () {
                  Get.bottomSheet(
                    const MoreBottomSheet(),
                    isScrollControlled: true,
                    backgroundColor:
                        isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(12.r),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  // 构建主体内容
  Widget _buildBody(bool isDarkMode) {
    double initialPosition = 0;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (DragStartDetails dragStartDetails) {
            initialPosition = dragStartDetails.localPosition.dy;
          },
          onVerticalDragUpdate: (DragUpdateDetails dragUpdateDetails) {
            controller.dragOffset.value += dragUpdateDetails.delta.dy;
          },
          onVerticalDragEnd: (DragEndDetails dragEndDetails) {
            double offset = initialPosition - dragEndDetails.localPosition.dy;
            if (offset > 0) {
              if (controller.isTop.value) {
                controller.dragOffset.value = 0;
                return;
              }
              if (offset > 60) {
                controller.dragOffset.value = 0;
                controller.isTop.value = true;
              } else {
                controller.dragOffset.value = 210.w;
                controller.isTop.value = false;
              }
            } else {
              if (!controller.isTop.value) {
                controller.dragOffset.value = 210.w;
                return;
              }
              if (offset < -60) {
                controller.dragOffset.value = 210.w;
                controller.isTop.value = false;
              } else {
                controller.dragOffset.value = 0;
                controller.isTop.value = true;
              }
            }
          },
          child: Column(
            children: [
              _soundWave(isDarkMode),
              Obx(
                () => !controller.isSpeakerText.value
                    ? Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        margin: EdgeInsets.symmetric(vertical: 10.w),
                        child: Obx(
                          () => Row(
                            children: [
                              _iconItem(Icons.summarize, 'overview'.tr, 0,
                                  isDarkMode), // 对应中文：概览
                              _iconItem(Icons.message, 'transcription'.tr, 1,
                                  isDarkMode), // 对应中文：转写
                              _iconItem(Icons.article, 'summary'.tr, 2,
                                  isDarkMode), // 对应中文：总结
                              _iconItem(Icons.lan, 'mindMap'.tr, 3,
                                  isDarkMode), // 对应中文：思维导图
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: TabBarView(
              controller: controller.tabController,
              physics: const NeverScrollableScrollPhysics(),
              clipBehavior: Clip.none,
              children: [
                Obx(
                  () => controller.isLoading.value
                      ? const SizedBox()
                      : controller.meetingDetails.value.tasktype > 0 &&
                              controller.meetingDetails.value.tasktype < 5
                          ? _meetingWait(
                              controller.meetingDetails.value.tasktype > 0 &&
                                      controller.meetingDetails.value.tasktype <
                                          3
                                  ? 'transcribing'.tr // 对应中文：正在转写...
                                  : 'analyzing'.tr) // 对应中文：正在分析...
                          : const OverviewTab(),
                ),
                Obx(
                  () => controller.meetingDetails.value.tasktype > 0 &&
                          controller.meetingDetails.value.tasktype < 3
                      ? _meetingWait('transcribing'.tr) // 对应中文：正在转写...
                      : const SpeechTab(),
                ),
                Obx(
                  () => controller.meetingDetails.value.tasktype > 0 &&
                          controller.meetingDetails.value.tasktype < 5
                      ? _meetingWait(
                          controller.meetingDetails.value.tasktype > 0 &&
                                  controller.meetingDetails.value.tasktype < 3
                              ? 'transcribing'.tr // 对应中文：正在转写...
                              : 'analyzing'.tr) // 对应中文：正在分析...
                      : const SummaryTab(),
                ),
                Obx(() => controller.meetingDetails.value.tasktype >= 5
                        ? const MindMapTab()
                        : controller.meetingDetails.value.tasktype == 0
                            ? const SizedBox()
                            : _meetingWait(controller
                                            .meetingDetails.value.tasktype >
                                        0 &&
                                    controller.meetingDetails.value.tasktype < 3
                                ? 'transcribing'.tr // 对应中文：正在转写...
                                : 'analyzing'.tr) // 对应中文：正在分析...
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _meetingWait(String title) {
    return Builder(
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            Lottie.asset(
              'assets/lottie/meeting_wait.json',
            ),
            Positioned(
              top: 320.w,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18.sp,
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _soundWave(bool isDarkMode) {
    return Obx(
      () => Opacity(
        opacity: (controller.dragOffset.value / 210.w).clamp(0.0, 1.0),
        child: SizedBox(
          height: controller.dragOffset.value < 0
              ? 0
              : controller.dragOffset.value > 210.w
                  ? 210.w
                  : controller.dragOffset.value,
          child: Stack(
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: 1.sw,
                  height: 200.w,
                  margin: EdgeInsets.only(bottom: 10.w),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[900]! : Colors.grey[200]!,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(20.r),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: EdgeInsets.only(bottom: 5.w),
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.grey[800] : Colors.white,
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: AudioFileWaveforms(
                          size: Size(350.w, 120.w),
                          playerController: controller.playerController,
                          waveformData: List.generate(88, (int index) {
                            return 0.01 + Random().nextDouble() * 0.09;
                          }),
                          waveformType: WaveformType.fitWidth,
                          playerWaveStyle: PlayerWaveStyle(
                            spacing: 4.w,
                            waveThickness: 2.w,
                            fixedWaveColor: Colors.grey[300]!,
                            liveWaveColor: Colors.red,
                            seekLineColor: Colors.red,
                            scaleFactor: 600,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 350.w,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Obx(
                              () => Text(
                                DateUtil.formatDateMs(
                                  controller.currentDuration.value,
                                  format: 'HH:mm:ss',
                                  isUtc: true,
                                ),
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[500],
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                            Obx(
                              () => Text(
                                DateUtil.formatDateMs(
                                  controller.durationMax.value,
                                  format: 'HH:mm:ss',
                                  isUtc: true,
                                ),
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[500],
                                  fontSize: 12.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          GestureDetector(
                            onTap: () {
                              int progress =
                                  controller.currentDuration.value - 10000;
                              if (progress < 0) {
                                progress = 0;
                              }
                              controller.playerController.seekTo(progress);
                            },
                            child: Icon(
                              Icons.replay_10,
                              color: isDarkMode ? Colors.white : Colors.black,
                              size: 30.w,
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              if (controller
                                  .meetingData.value.filepath.isEmpty) {
                                controller.downloadAudio();
                              } else {
                                // 检查播放器是否已准备好
                                if (!controller.isPlayerReady.value) {
                                  Get.snackbar(
                                    'error'.tr,
                                    'playerNotReady'.tr, // 音频播放器未准备好，请稍候
                                    snackPosition: SnackPosition.BOTTOM,
                                    duration: const Duration(seconds: 2),
                                  );
                                  return;
                                }

                                try {
                                  if (controller.isPlay.value) {
                                    await controller.playerController
                                        .pausePlayer();
                                  } else {
                                    await controller.playerController
                                        .startPlayer();
                                  }
                                } catch (e) {
                                  Get.snackbar(
                                    'error'.tr,
                                    "${'playFailed'.tr}: ${e.toString()}", // 播放失败
                                    snackPosition: SnackPosition.BOTTOM,
                                    duration: const Duration(seconds: 2),
                                  );
                                }
                              }
                            },
                            child: Obx(
                              () => !controller.isLoading.value &&
                                      controller
                                          .meetingData.value.filepath.isEmpty
                                  ? Obx(
                                      () => Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          if (controller.isDownload.value)
                                            SizedBox(
                                              width: 42.w,
                                              height: 42.w,
                                              child: CircularProgressIndicator(
                                                value: controller
                                                    .downloadProgress.value,
                                                valueColor:
                                                    const AlwaysStoppedAnimation<
                                                        Color>(Colors.red),
                                                strokeWidth: 3.w,
                                              ),
                                            ),
                                          Icon(
                                            Icons.download_for_offline,
                                            color: isDarkMode
                                                ? Colors.white
                                                : Colors.black,
                                            size: 48.w,
                                          ),
                                        ],
                                      ),
                                    )
                                  : Icon(
                                      controller.isPlay.value
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                                      color: isDarkMode
                                          ? Colors.white
                                          : Colors.black,
                                      size: 48.w,
                                    ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              int progress =
                                  controller.currentDuration.value + 10000;
                              controller.playerController.seekTo(progress);
                            },
                            child: Icon(
                              Icons.forward_10,
                              color: isDarkMode ? Colors.white : Colors.black,
                              size: 30.w,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconItem(IconData icon, String title, int index, bool isDarkMode) {
    bool isActive = controller.currentIndex.value == index;

    return Expanded(
      flex: isActive ? 1 : 0,
      child: GestureDetector(
        onTap: () {
          if (isActive) return;
          controller.tabController.index = index;
        },
        child: Container(
          height: 45.w,
          padding: EdgeInsets.symmetric(horizontal: 18.w),
          margin: EdgeInsets.symmetric(horizontal: 4.w),
          decoration: BoxDecoration(
            color: isActive
                ? (isDarkMode ? Colors.white : Colors.black)
                : (isDarkMode ? const Color(0xFF2D2D2D) : Colors.grey[200]),
            borderRadius: BorderRadius.circular(12.w),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive
                    ? (isDarkMode ? Colors.black : Colors.white)
                    : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                size: 20.sp,
              ),
              if (isActive)
                Padding(
                  padding: EdgeInsets.only(left: 5.w),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isDarkMode ? Colors.black : Colors.white,
                      fontSize: 16.sp,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
