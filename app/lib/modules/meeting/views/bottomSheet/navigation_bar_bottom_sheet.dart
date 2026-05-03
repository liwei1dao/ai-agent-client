import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../bindings/meeting_record_binding.dart';
import '../../controllers/meeting_home_controller.dart';
import '../meeting_record_view.dart';

///会议底部导航栏抽屉，提供会议列表、会议详情、会议设置
class NavigationBarBottomSheet extends GetView<MeetingHomeController> {
  const NavigationBarBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (controller.meetingController.type == 0)
            _buildItem(
              context, // 传递 context 参数
              'startRecording'.tr, // 对应中文：开始录音
              Icons.mic_rounded,
              Colors.red,
            ),
          if (controller.meetingController.type == 1)
            _buildItem(
              context, // 传递 context 参数
              'liveRecording'.tr, // 对应中文：现场录音
              Icons.mic_rounded,
              Colors.red,
              onTap: () async {
                Get.back();
                await Get.to(
                  () => const MeetingRecordView(),
                  binding: MeetingRecordBinding(),
                  arguments: {'audioTypes': 0},
                );
              },
            ),
          if (controller.meetingController.type == 1)
            _buildItem(
              context, // 传递 context 参数
              'audioVideoRecording'.tr, // 对应中文：音、视频录音
              Icons.videocam,
              Colors.green,
              onTap: controller.bleManager.isConnected
                  ? () async {
                      Get.back();
                      await Get.to(
                        () => const MeetingRecordView(),
                        binding: MeetingRecordBinding(),
                        arguments: {'audioTypes': 1},
                      );
                    }
                  : null,
            ),
          if (controller.meetingController.type == 1)
            _buildItem(
              context, // 传递 context 参数
              'callRecording'.tr, // 对应中文：通话录音
              Icons.phone,
              Colors.orange,
              onTap: controller.bleManager.isConnected
                  ? () async {
                      Get.back();
                      await Get.to(
                        () => const MeetingRecordView(),
                        binding: MeetingRecordBinding(),
                        arguments: {'audioTypes': 2},
                      );
                    }
                  : null,
            ),
          _buildItem(
            context, // 传递 context 参数
            'importAudio'.tr, // 对应中文：导入音频
            Icons.file_upload_outlined,
            Colors.deepPurple,
            onTap: () {
              Get.back();
              controller.addAudio();
            },
          ),
          SizedBox(height: 24.w),
          GestureDetector(
            onTap: () => Get.back(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(Icons.close, color: Colors.white),
            ),
          ),
          const SizedBox(height: 19),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, // 添加 context 参数
    String title,
    IconData icon,
    Color color, {
    Function()? onTap,
  }) {
    final isDarkMode =
        Theme.of(context).brightness == Brightness.dark; // 在方法内部获取 isDarkMode
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220.w,
        height: 60.w,
        padding: EdgeInsets.all(5.w),
        margin: EdgeInsets.only(top: 15.w),
        decoration: BoxDecoration(
          color: isDarkMode
              ? Colors.grey[800]!.withValues(alpha: onTap != null ? 1 : 0.5)
              : Colors.white.withValues(alpha: onTap != null ? 1 : 0.5),
          borderRadius: BorderRadius.circular(60.w),
        ),
        child: Row(
          children: [
            Container(
              width: 46.w,
              height: 46.w,
              margin: EdgeInsets.only(right: 5.w),
              decoration: BoxDecoration(
                color: color.withValues(alpha: onTap != null ? 0.3 : 0.2),
                borderRadius: BorderRadius.circular(60.w),
              ),
              child: Icon(
                icon,
                color: color.withValues(alpha: onTap != null ? 1 : 0.5),
              ),
            ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15.sp,
                  color: isDarkMode
                      ? Colors.white.withValues(alpha: onTap != null ? 1 : 0.5)
                      : Colors.black87
                          .withValues(alpha: onTap != null ? 1 : 0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16.w,
              color: Colors.grey.withOpacity(onTap != null ? 1 : 0.5),
            ),
            5.horizontalSpace,
          ],
        ),
      ),
    );
  }
}
