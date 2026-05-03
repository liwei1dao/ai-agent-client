import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../controllers/meeting_home_controller.dart';

class EditTitleBottomSheet extends GetView<MeetingHomeController> {
  final int id;

  const EditTitleBottomSheet(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'editMeetingTitle'.tr, // 编辑会议标题
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      width: 26.w,
                      height: 26.w,
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[700] : Colors.white,
                        borderRadius: BorderRadius.circular(26.r),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18.w,
                        color: Colors.grey[400],
                      ),
                    ),
                  )
                ],
              ),
            ),
            Divider(
              height: 1,
              color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
            ),
            Container(
              margin: EdgeInsets.symmetric(vertical: 20.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                borderRadius: BorderRadius.circular(12.w),
                boxShadow: isDarkMode
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: TextField(
                controller: controller.titleController,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16.sp,
                ),
                decoration: InputDecoration(
                  hintText: 'maxCharacters'.tr,
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.grey[500] : Colors.black54,
                    fontSize: 16.sp,
                  ),
                  isDense: true,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(10.w),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 20.w),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        height: 48.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color:
                              isDarkMode ? Colors.grey[700] : Colors.grey[300],
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          'cancel'.tr, // 取消
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                  10.horizontalSpace,
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        controller.editMeetingTitle(id);
                      },
                      child: Container(
                        height: 48.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          'confirm'.tr, // 确认
                          style: TextStyle(
                            fontSize: 16.sp,
                            color: isDarkMode ? Colors.black : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
