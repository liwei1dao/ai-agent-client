import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../controllers/meeting_connect_controller.dart';
import '../utils/meeting_ui_utils.dart';

class MeetingConnectView extends GetView<MeetingConnectController> {
  const MeetingConnectView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
      appBar: _buildAppBar(isDarkMode),
      body: _buildBody(isDarkMode),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDarkMode) {
    return AppBar(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: isDarkMode ? Colors.white : Colors.black,
          size: 20.sp,
        ),
        onPressed: () => Get.back(),
      ),
      title: Text(
        'bluetoothConnection'.tr, // 对应中文：蓝牙连接
        style: TextStyle(
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildBody(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Obx(
            () => Padding(
              padding: EdgeInsets.only(bottom: 30.w),
              child: Text(
                controller.stateStr.value,
                style: TextStyle(
                  fontSize: 20.sp,
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Obx(
            () => controller.isRescan.value
                ? _button('meetingReconnect'.tr, Icons.refresh, onTap: () { // 对应中文：重新连接
                    controller.startScan();
                  })
                : const SizedBox(),
          ),
          Obx(
            () => Text(
              controller.importedFilesStr.value,
              style: TextStyle(
                fontSize: 16.sp,
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          Obx(() => controller.isDownload.value
              ? Column(
                  children: [
                    Container(
                      width: 300.w,
                      height: 3.w,
                      margin: EdgeInsets.symmetric(vertical: 10.w),
                      child: LinearProgressIndicator(
                        value: controller.downloadProgress.value,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    ),
                    Text(
                      '${controller.totalReceived.value} / ${controller.fileSize.value} bytes',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                )
              : const SizedBox()),
        ],
      ),
    );
  }

  Widget _button(String text, IconData icon, {Function()? onTap}) {
    return Builder(
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: 150.w,
            height: 42.w,
            decoration: BoxDecoration(
              color: MeetingUIUtils.getButtonColor(isDarkMode),
              borderRadius: BorderRadius.circular(42.w),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: 20.sp,
                ),
                5.horizontalSpace,
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white,
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
