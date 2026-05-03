import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../controllers/meeting_details_controller.dart';
import '../../utils/meeting_ui_utils.dart';
import '../bottomSheet/ai_bottom_sheet.dart';
import '../bottomSheet/generate_bottom_sheet.dart';

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  final _controller = Get.find<MeetingDetailsController>();

  List _dataList = [];

  @override
  void initState() {
    super.initState();
    if (_controller.meetingDetails.value.overview.isNotEmpty) {
      _dataList = _controller.meetingDetails.value.overview.split('\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        _dataList.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 5.w),
                    child: Text(
                      DateUtil.formatDateMs(
                        _controller.meetingData.value.creationtime,
                        format: DateFormats.y_mo_d_h_m,
                      ),
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.black54,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 10.w),
                    child: Text(
                      _controller.meetingData.value.title,
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 10.w),
                    child: Divider(
                      height: 1,
                      color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 10.w),
                    child: Text(
                      'keyEventsAnalyzed'.tr.replaceAll('{count}',
                          '${_dataList.length}'), // 对应中文：分析出{count}个关键事件。
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey,
                        fontSize: 12.sp,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _dataList.length,
                      padding: EdgeInsets.fromLTRB(10.w, 10.w, 10.w, 80.w),
                      itemBuilder: (BuildContext context, int index) {
                        return _item(_dataList[index]);
                      },
                    ),
                  ),
                ],
              )
            : _empty(),
        Obx(
          () => Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 20.w,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_controller.meetingDetails.value.tasktype >= 3 &&
                    _controller.meetingDetails.value.tasktype < 10000)
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
                if (_controller.meetingDetails.value.tasktype == 0)
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
                if (_controller.meetingDetails.value.tasktype == 10002)
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
                if (_controller.meetingDetails.value.tasktype == 10001)
                  SizedBox(
                    width: 150.w,
                    child: _button(
                      Icons.auto_awesome,
                      'reSummarize'.tr, // 重新总结
                      () {
                        Get.bottomSheet(
                          const GenerateBottomSheet(
                            isSummarizeAgain: true,
                          ),
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

  Widget _item(String data) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(10.w),
      margin: EdgeInsets.symmetric(vertical: 5.w),
      decoration: BoxDecoration(
        color: MeetingUIUtils.getCardColor(isDarkMode),
        borderRadius: BorderRadius.circular(12.w),
        boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
      ),
      child: Text(
        data,
        style: TextStyle(
          color: MeetingUIUtils.getTextColor(isDarkMode),
        ),
      ),
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

  Widget _empty() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.w),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10.w),
            child: Icon(
              Icons.summarize,
              color: isDarkMode ? Colors.grey[400] : Colors.grey,
              size: 40.sp,
            ),
          ),
          Text(
            'overview'.tr, // 对应中文：概览
            style: TextStyle(
              color: MeetingUIUtils.getTextColor(isDarkMode),
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            _controller.meetingDetails.value.tasktype < 10000
                ? 'aiAnalysisDesc'.tr // 对应中文：AI分析识别录音中的关键事件，让你选择重要事件进行AI生成。
                : 'analysisFailed'.tr, // 分析失败，请稍后重试
            style: TextStyle(
              color: MeetingUIUtils.getSecondaryTextColor(isDarkMode),
              fontSize: 14.sp,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
