import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:lottie/lottie.dart';

import '../../controllers/meeting_details_controller.dart';
import '../../utils/meeting_ui_utils.dart';
import '../bottomSheet/ai_bottom_sheet.dart';
import '../bottomSheet/generate_bottom_sheet.dart';
import '../bottomSheet/speaker_all_bottom_sheet.dart';
import '../bottomSheet/speaker_bottom_sheet.dart';

class SpeechTab extends GetView<MeetingDetailsController> {
  const SpeechTab({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Obx(
          () => controller.meetingDetails.value.tasktype != 10002
              ? ListView.builder(
                  itemCount: controller.textList.length,
                  padding: EdgeInsets.only(bottom: 80.w),
                  itemBuilder: (BuildContext context, int index) {
                    Map item = controller.textList[index];
                    TextStyle textStyle = TextStyle(
                      fontSize: 15.sp,
                      color: MeetingUIUtils.getTextColor(isDarkMode),
                      letterSpacing: 0,
                      height: 1.4,
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 10.w),
                          child: Row(
                            children: [
                              if (item['speaker'].isNotEmpty)
                                Container(
                                  width: 11.w,
                                  height: 11.w,
                                  margin: EdgeInsets.only(right: 3.w),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(11.r),
                                    border: Border.all(
                                      color: const Color(0xFFFFC107),
                                      width: 3.w,
                                    ),
                                  ),
                                ),
                              if (item['speaker'].isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    if (controller.isSpeakerText.value) return;
                                    Get.bottomSheet(
                                      SpeakerBottomSheet(
                                          item['id'], item['speaker']),
                                      isScrollControlled: true,
                                      backgroundColor: isDarkMode
                                          ? Colors.grey[800]
                                          : Colors.grey[100],
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(12.r),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.only(right: 5.w),
                                    child: Text(
                                      item['speaker'],
                                      style: TextStyle(
                                        color: const Color(0xFFFFC107),
                                        fontSize: 13.sp,
                                      ),
                                    ),
                                  ),
                                ),
                              Text(
                                DateUtil.formatDateMs(
                                  item['starttime'],
                                  format: 'HH:mm:ss',
                                  isUtc: true,
                                ),
                                style: TextStyle(
                                  color: MeetingUIUtils.getSecondaryTextColor(
                                      isDarkMode),
                                  fontSize: 13.sp,
                                ),
                              ),
                              Obx(() {
                                bool isActive = false;
                                int starttime = item['starttime'];
                                int endtime = 0;
                                if (index == controller.textList.length - 1) {
                                  endtime = controller.durationMax.value;
                                } else {
                                  endtime = controller.textList[index + 1]
                                      ['starttime'];
                                }
                                if (controller.currentDuration.value != 0) {
                                  if (controller.currentDuration.value >=
                                          starttime &&
                                      controller.currentDuration.value <
                                          endtime) {
                                    isActive = true;
                                  }
                                }
                                return isActive
                                    ? Container(
                                        width: 16.w,
                                        height: 16.w,
                                        margin: EdgeInsets.only(left: 5.w),
                                        alignment: Alignment.center,
                                        clipBehavior: Clip.hardEdge,
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          borderRadius:
                                              BorderRadius.circular(4.r),
                                        ),
                                        child: Transform.scale(
                                          scale: 1.6,
                                          child: Lottie.asset(
                                            'assets/lottie/sound_effect.json',
                                            controller:
                                                controller.lottieController,
                                          ),
                                        ),
                                      )
                                    : const SizedBox();
                              }),
                            ],
                          ),
                        ),
                        Obx(() {
                          if (controller.isSpeakerText.value) {
                            TextEditingController speakerTextController =
                                TextEditingController(text: item['content']);
                            return Obx(
                              () => Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14.w,
                                ),
                                decoration: BoxDecoration(
                                  color: controller.editSpeakerTextId.value ==
                                          item['id']
                                      ? Colors.blue[100]
                                      : null,
                                  borderRadius: BorderRadius.circular(8.w),
                                ),
                                child: FocusScope(
                                  onFocusChange: (bool hasFocus) {
                                    if (hasFocus) {
                                      controller.editSpeakerTextId.value =
                                          item['id'];
                                      controller.editSpeakerTextChange = '';
                                    } else {
                                      if (speakerTextController.text !=
                                          item['content']) {
                                        Map? foundElement = controller
                                            .editSpeakerTextList
                                            .firstWhere(
                                          (element) =>
                                              element['id'] == item['id'],
                                          orElse: () => null,
                                        );
                                        if (foundElement != null) {
                                          foundElement['content'] =
                                              speakerTextController.text;
                                        } else {
                                          controller.editSpeakerTextList.add({
                                            'id': item['id'],
                                            'content':
                                                speakerTextController.text,
                                          });
                                        }
                                      }
                                    }
                                  },
                                  child: TextField(
                                    controller: speakerTextController,
                                    style: textStyle,
                                    minLines: 1,
                                    maxLines: 100,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      fillColor: Colors.transparent,
                                      border: InputBorder.none,
                                      contentPadding:
                                          EdgeInsets.symmetric(vertical: 5.w),
                                    ),
                                    onChanged: (String value) {
                                      controller.editSpeakerTextChange = value;
                                    },
                                  ),
                                ),
                              ),
                            );
                          } else {
                            return Obx(() {
                              bool isActive = false;
                              int starttime = item['starttime'];
                              int endtime = 0;
                              if (index == controller.textList.length - 1) {
                                endtime = controller.durationMax.value;
                              } else {
                                endtime =
                                    controller.textList[index + 1]['starttime'];
                              }
                              if (controller.currentDuration.value != 0) {
                                if (controller.currentDuration.value >=
                                        starttime &&
                                    controller.currentDuration.value <
                                        endtime) {
                                  isActive = true;
                                }
                              }
                              return GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () {
                                  if (isActive) {
                                    if (controller.isPlay.value) {
                                      controller.playerController.pausePlayer();
                                    } else {
                                      controller.playerController.startPlayer();
                                    }
                                  } else {
                                    controller.playerController
                                        .seekTo(item['starttime']);
                                    controller.playerController.startPlayer();
                                  }
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14.w,
                                    vertical: 5.w,
                                  ),
                                  child: Text(
                                    item['content'],
                                    style: TextStyle(
                                      fontSize: 15.sp,
                                      color: isActive
                                          ? Colors.red
                                          : MeetingUIUtils.getTextColor(
                                              isDarkMode),
                                      letterSpacing: 0,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              );
                            });
                          }
                        }),
                      ],
                    );
                  },
                )
              : Container(
                  height: 200.w,
                  alignment: Alignment.center,
                  child: Text(
                    'transcriptionFailed'.tr, // 转写失败，请稍后重试
                    style: TextStyle(
                      color: MeetingUIUtils.getSecondaryTextColor(isDarkMode),
                      fontSize: 14.sp,
                    ),
                  ),
                ),
        ),
        Obx(
          () => Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20.w,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (controller.meetingDetails.value.tasktype >= 2 &&
                    !controller.isSpeakerText.value &&
                    controller.meetingDetails.value.tasktype != 10002)
                  _button(
                    Icons.edit,
                    'editSpeaker'.tr, // 对应中文：编辑
                    () {
                      controller.isSpeakerText.value = true;
                      controller.dragOffset.value = 0;
                      controller.isTop.value = true;
                    },
                  ),
                if (controller.meetingDetails.value.tasktype >= 2 &&
                    !controller.isSpeakerText.value &&
                    controller.meetingDetails.value.tasktype != 10002)
                  _button(
                    Icons.supervisor_account,
                    'nameSpeaker'.tr, // 对应中文：命名发言者
                    () {
                      Get.bottomSheet(
                        const SpeakerAllBottomSheet(),
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
                if (controller.meetingDetails.value.tasktype >= 2 &&
                    !controller.isSpeakerText.value &&
                    controller.meetingDetails.value.tasktype != 10002)
                  _button(
                    Icons.auto_awesome,
                    'Ask AI',
                    () {
                      Get.bottomSheet(
                        const AIBottomSheet(),
                        isScrollControlled: true,
                        backgroundColor:
                            isDarkMode ? Colors.grey[800] : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(12.r),
                          ),
                        ),
                      );
                    },
                  ),
                if (controller.meetingDetails.value.tasktype == 0)
                  SizedBox(
                    width: 150.w,
                    child: _button(
                      Icons.auto_awesome,
                      'generate'.tr, // 对应中文：生成
                      () {
                        Get.bottomSheet(
                          const GenerateBottomSheet(),
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
                  ),
                if (controller.meetingDetails.value.tasktype == 10002)
                  SizedBox(
                    width: 150.w,
                    child: _button(
                      Icons.auto_awesome,
                      'regenerate'.tr, // 重新生成
                      () {
                        Get.bottomSheet(
                          const GenerateBottomSheet(),
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
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _button(IconData icon, String title, Function() onTap) {
    return Builder(
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42.w,
            padding: EdgeInsets.symmetric(horizontal: 15.w),
            margin: EdgeInsets.symmetric(horizontal: 4.w),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(42.w),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isDarkMode ? Colors.black : Colors.white,
                  size: 20.sp,
                ),
                5.horizontalSpace,
                Text(
                  title,
                  style: TextStyle(
                    color: isDarkMode ? Colors.black : Colors.white,
                    fontSize: 14.sp,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
