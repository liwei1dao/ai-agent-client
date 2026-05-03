import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../common/webview_page.dart';

class MemberBottomSheet extends StatelessWidget {
  const MemberBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(12.r),
          ),
          image: const DecorationImage(
            alignment: Alignment.topCenter,
            image: AssetImage('assets/images/mine-background.png'),
            fit: BoxFit.fitWidth,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 12.w),
              alignment: Alignment.centerRight,
              child: GestureDetector(
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
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[400],
                  ),
                ),
              ),
            ),
            Text(
              '解锁 Starter 会员',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 5.w, bottom: 20.w),
              child: Text(
                '绑定 VOITRANS 设备可激活 Starter 会员权益，解锁:',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 14.sp,
                ),
              ),
            ),
            _item(
                Icons.access_time,
                Colors.red,
                'monthlyTranscriptionDuration'.tr,
                isDarkMode), //对应中文：每月300分钟转写时长
            _item(
                Icons.description,
                Colors.purpleAccent,
                'industrySpecificSummaryTemplate'.tr,
                isDarkMode), //对应中文：为行业细分场景设计的专业总结模版
            _item(
                Icons.auto_awesome,
                Colors.purpleAccent,
                'autopilotTemplateSummary'.tr,
                isDarkMode), //对应中文：Autopilot 模版自动总结
            _item(Icons.people, Colors.red, 'distinguishDifferentSpeakers'.tr,
                isDarkMode), //对应中文：区分不同说话人
            _item(Icons.cloud_upload, Colors.red, 'importAudioFromAppWeb'.tr,
                isDarkMode), //对应中文：从APP、WEB导入音频进行转写和总结
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20.w),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Get.to(
                          () => const WebViewPage(
                            url: 'https://web.voitrans.net',
                            title: 'Voitrans',
                          ),
                        );
                      },
                      child: Container(
                        height: 48.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: isDarkMode
                                ? Colors.grey[600]!
                                : Colors.grey[400]!,
                          ),
                        ),
                        child: Text(
                          'findMore'.tr, //对应中文：发现更多
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
                      onTap: () {},
                      child: Container(
                        height: 48.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          'bindImmediately'.tr, //对应中文：立即绑定
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

  Widget _item(IconData icon, Color color, String title, bool isDarkMode) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.w),
      child: Row(
        children: [
          Container(
            width: 50.w,
            height: 50.w,
            margin: EdgeInsets.only(right: 10.w),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: Colors.red.withOpacity(0.1),
                width: 2.w,
              ),
            ),
            child: Icon(
              icon,
              size: 24.w,
              color: color,
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 14.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
