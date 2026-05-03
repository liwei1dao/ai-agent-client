import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../bindings/meeting_details_binding.dart';
import '../../controllers/meeting_home_controller.dart';
import '../../model/meeting_model.dart';
import '../../utils/meeting_ui_utils.dart';
import '../meeting_details_view.dart';

class MeetingTranscriptionView extends GetView<MeetingHomeController> {
  const MeetingTranscriptionView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
      appBar: _buildAppBar(isDarkMode),
      body: SafeArea(
        top: false,
        child: _buildBody(isDarkMode),
      ),
    );
  }

  // 构建应用栏
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
        onPressed: () => Get.back(),
      ),
      title: Text(
        'transcriptionRecord'.tr, // 对应中文：转写记录
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
    return Obx(
      () => ListView.builder(
        itemCount: controller.originalDataList.length,
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.w),
        itemBuilder: (BuildContext context, int index) {
          MeetingModel data =
              MeetingModel.fromJson(controller.originalDataList[index]);
          return data.tasktype >= 2
              ? _item(context, isDarkMode, data)
              : const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _item(BuildContext context, bool isDarkMode, MeetingModel data) {
    return GestureDetector(
      onTap: () {
        Get.to(
          () => const MeetingDetailsView(),
          binding: MeetingDetailsBinding(id: data.id),
          arguments: {'id': data.id},
        );
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
        ),
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
}
