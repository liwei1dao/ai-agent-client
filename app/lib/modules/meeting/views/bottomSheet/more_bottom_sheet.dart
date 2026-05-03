import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../controllers/meeting_home_controller.dart';
import '../../controllers/meeting_details_controller.dart';
import 'generate_bottom_sheet.dart';

class MoreBottomSheet extends StatefulWidget {
  const MoreBottomSheet({super.key});

  @override
  State<MoreBottomSheet> createState() => _MoreBottomSheetState();
}

class _MoreBottomSheetState extends State<MoreBottomSheet> {
  final _controller = Get.find<MeetingHomeController>();
  final _detailsController = Get.find<MeetingDetailsController>();

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 10.w),
            _shareItem(Icons.refresh, 'reSummarize'.tr, //重新总结
                isDarkMode: isDarkMode,
                onTap: _detailsController.meetingDetails.value.tasktype >= 5 &&
                        _detailsController.meetingDetails.value.tasktype < 10002
                    ? () {
                        Get.back();
                        Get.bottomSheet(
                          const GenerateBottomSheet(
                            isSummarizeAgain: true,
                          ),
                          isScrollControlled: true,
                          backgroundColor:
                              isDarkMode ? Colors.grey[850] : Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12.r),
                            ),
                          ),
                        );
                      }
                    : null),
            _shareItem(Icons.delete_outline, 'delete'.tr,
                isDarkMode: isDarkMode, onTap: () async {
              _controller.deleteMeeting(
                _detailsController.meetingData.value.id,
                _detailsController.meetingData.value.filepath,
              );
              Get.back();
              Get.back();
            }),
          ],
        ),
      ),
    );
  }

  Widget _shareItem(
    IconData icon,
    String title, {
    VoidCallback? onTap,
    bool isDarkMode = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.w),
        margin: EdgeInsets.only(bottom: 10.w),
        decoration: BoxDecoration(
          color: onTap != null
              ? (isDarkMode ? const Color(0xFF2D2D2D) : Colors.white)
              : (isDarkMode ? Colors.grey[800] : Colors.grey[200]),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: onTap != null ? 1.0 : 0.5,
              child: Icon(
                icon,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            10.horizontalSpace,
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: (isDarkMode ? Colors.white : Colors.black87)
                      .withValues(alpha: onTap != null ? 1 : 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
