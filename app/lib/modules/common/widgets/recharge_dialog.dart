import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../routes/app_routes.dart';

/// 显示充值弹窗
/// [type] 充值类型，可选值为 'agent'、'translation'、'meeting'
/// 分别跳转对应ai充值、翻译充值、会议充值界面
void showRechargeDialog(String type) {
  Get.dialog(
    Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'tip'.tr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  (type == 'agent'
                          ? 'aiMemberExpiredDesc'
                          : 'insufficientBalanceDesc')
                      .tr, // 会员过期描述 / 余额不足描述
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Get.back();
                      if (type == 'agent') {
                        Get.toNamed(Routes.goodsvip);
                      } else if (type == 'translation') {
                        Get.toNamed(Routes.goodstrans);
                      } else if (type == 'meeting') {
                        Get.toNamed(Routes.goodsmeet);
                      }
                    },
                    child: Text('recharge'.tr),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Get.back(),
            ),
          ),
        ],
      ),
    ),
    barrierDismissible: true,
  );
}
