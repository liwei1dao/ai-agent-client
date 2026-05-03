import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import '../webview_page.dart';
import '../../../core/utils/doc_url_helper.dart';

/// 隐私政策弹窗组件
class PrivacyPolicyDialog extends StatelessWidget {
  final VoidCallback? onAccept; // 同意回调
  final VoidCallback? onReject; // 拒绝回调
  final bool canDismiss; // 是否可以通过返回键关闭

  const PrivacyPolicyDialog({
    super.key,
    this.onAccept,
    this.onReject,
    this.canDismiss = false,
  });

  /// 显示隐私政策弹窗
  static Future<void> show({
    VoidCallback? onAccept,
    VoidCallback? onReject,
    bool canDismiss = false,
  }) {
    return Get.dialog(
      PrivacyPolicyDialog(
        onAccept: onAccept,
        onReject: onReject,
        canDismiss: canDismiss,
      ),
      barrierDismissible: canDismiss,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Get.theme.brightness == Brightness.dark;

    return PopScope(
      canPop: canDismiss, // 根据参数决定是否可以通过返回键关闭
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        backgroundColor:
            isDarkMode ? Colors.grey[800] : Colors.white, // 暗黑模式使用深灰色背景
        child: Container(
          padding: EdgeInsets.all(20.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'loginDeclaration'.tr, // APP 声明
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black, // 暗黑模式使用白色文字
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'welcomeToThisApp'.tr, // 欢迎使用本APP，请充分阅读
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: isDarkMode
                              ? Colors.white70
                              : Colors.black87, // 暗黑模式使用浅白色
                        ),
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: GestureDetector(
                          onTap: () {
                            Get.to(() => WebViewPage(
                                  url: privacyPolicyUrl(),
                                  title: 'privacyPolicy'.tr,
                                ));
                          },
                          child: Text(
                            'privacyPolicy'.tr, // 隐私政策
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                      ),
                      TextSpan(
                        text: 'and'.tr, // 和
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: GestureDetector(
                          onTap: () {
                            Get.to(() => WebViewPage(
                                  url: userAgreementUrl(),
                                  title: 'userAgreement'.tr, // 用户协议
                                ));
                          },
                          child: Text(
                            'userAgreement'.tr, // 用户协议
                            style: TextStyle(
                              fontSize: 14.sp,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                      ),
                      TextSpan(
                        text: 'privacyPolicyText'
                            .tr, // '，点击"同意并进入"表示您已充分阅读并同意上述协议。点击"不同意"将退出应用。',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      if (onReject != null) {
                        onReject!();
                      } else {
                        // 默认行为：退出应用
                        exit(0);
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: isDarkMode
                          ? Colors.grey[400]
                          : Colors.black54, // 暗黑模式使用浅灰色
                    ),
                    child: Text(
                      'disagree'.tr, // 不同意
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.black54,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (onAccept != null) {
                        onAccept!();
                      } else {
                        // 默认行为：关闭弹窗
                        Get.back();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0066CC),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      elevation: isDarkMode ? 4 : 2, // 暗黑模式下增加阴影效果提高辨识度
                      padding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 10.h), // 统一的内边距
                    ),
                    child: Text('agreeAndEnter'.tr), // 同意并进入
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
