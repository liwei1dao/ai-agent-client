import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';
import '../../profile/views/unified_avatar.dart';

import '../controllers/meeting_controller.dart';
import '../controllers/meeting_mine_controller.dart';
import '../utils/meeting_ui_utils.dart';
import 'bottomSheet/member_bottom_sheet.dart';
import 'bottomSheet/statistics_bottom_sheet.dart';
import 'mine/meeting_cloud_view.dart';
import 'mine/meeting_member_view.dart';
import 'mine/meeting_transcription_view.dart';

class MeetingMineView extends StatefulWidget {
  const MeetingMineView({super.key});

  @override
  State<MeetingMineView> createState() => _MeetingMineViewState();
}

class _MeetingMineViewState extends State<MeetingMineView>
    with AutomaticKeepAliveClientMixin {
  final _controller = Get.put(MeetingMineController());
  final _meetingController = Get.put(MeetingController());

  @override
  bool get wantKeepAlive => true;

  // 添加 isDarkMode 作为类的 getter
  bool get isDarkMode => Theme.of(context).brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            alignment: Alignment.topCenter,
            image: AssetImage('assets/images/mine-background.png'),
            fit: BoxFit.fitWidth,
          ),
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 90.w),
            children: [
              _head(),
              _statistics(),
              _member(),
              _box([
                _item(
                  Icons.article_outlined,
                  'transcriptionRecords'.tr, // 对应中文：转写记录
                  onTap: () {
                    Get.to(() => const MeetingTranscriptionView());
                  },
                ),
              ]),
              _box([
                _item(
                  Icons.layers_outlined,
                  'templateCommunity'.tr, // 对应中文：模版社区
                  description: 'comingSoon'.tr, // 对应中文：尽请期待
                  onTap: () {},
                ),
                _item(
                  Icons.sync_alt_outlined,
                  'integration'.tr, // 对应中文：集成
                  description: 'comingSoon'.tr, // 对应中文：尽请期待
                  onTap: () {},
                ),
              ]),
              _box([
                Obx(
                  () => _item(
                    Icons.cloud_upload_outlined,
                    'VOITRANS PRIVATE CLOUD',
                    description: _meetingController.user['privatecloud'] == 1
                        ? 'enabled'.tr // 对应中文：开启
                        : 'disabled'.tr, // 对应中文：关闭
                    onTap: () {
                      Get.to(() => const MeetingCloudView());
                    },
                  ),
                ),
              ]),
              _box([
                _item(
                  Icons.language_outlined,
                  'WEB',
                  description: 'web.voitrans.com',
                  onTap: () {},
                ),
                _item(
                  Icons.settings_remote_outlined,
                  'myVoitransDevice'.tr, // 对应中文：我的VOITRANS设备
                  onTap: () {
                    context.push('/devices');
                  },
                ),
              ]),
              _box([
                _item(
                  Icons.help_outline_rounded,
                  'helpAndFeedback'.tr, // 对应中文：帮助与反馈
                  onTap: () {
                    Get.snackbar('提示', '帮助与反馈待实现');
                  },
                ),
                _item(
                  Icons.info_outline_rounded,
                  'aboutVoitrans'.tr, // 对应中文：关于VOITRANS
                  description: 'v1.0.0',
                  onTap: () {},
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.w),
      child: GestureDetector(
        onTap: () => Get.snackbar('提示', '个人信息页待实现'), // 占位
        child: Row(
          children: [
            // 使用统一头像组件，避免闪烁问题
            Container(
              margin: EdgeInsets.only(right: 10.w),
              child: UnifiedAvatar(
                radius: 25.w,
                backgroundColor:
                    isDarkMode ? Colors.grey[700] : Colors.grey[200],
                iconColor: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                iconSize: 25.r,
                isDarkMode: isDarkMode,
              ),
            ),
            Expanded(
              child: Obx(
                () => Text(
                  _controller.profileCtrl.userInfo.value.name,
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16.w,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[700],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statistics() {
    return GestureDetector(
      onTap: () {
        Get.bottomSheet(
          const StatisticsBottomSheet(),
          isScrollControlled: true,
        );
      },
      child: Container(
        padding: EdgeInsets.all(8.w),
        margin: EdgeInsets.only(bottom: 15.w),
        decoration: BoxDecoration(
          color: MeetingUIUtils.getCardColor(isDarkMode),
          borderRadius: BorderRadius.circular(16.w),
          boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
        ),
        child: Obx(
          () => Column(
            children: [
              Row(
                children: [
                  _statisticsItem(
                    '${_controller.days.value}',
                    'meetingDays'.tr, // 对应中文：天
                    Colors.lime,
                  ),
                  _statisticsItem(
                    '${_controller.numberFiles.value}',
                    'files'.tr, // 对应中文：文件
                    Colors.lightGreen,
                  ),
                  _statisticsItem(
                    '${_controller.hourage.value}',
                    'meetingHours'.tr, // 对应中文：小时
                    Colors.blueGrey,
                  ),
                ],
              ),
              Container(
                height: 80.w,
                padding: EdgeInsets.symmetric(horizontal: 2.w),
                margin: EdgeInsets.only(top: 8.w, bottom: 2.w),
                child: GridView.builder(
                  controller: _controller.scrollController,
                  scrollDirection: Axis.horizontal,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 2.w,
                    crossAxisSpacing: 2.w,
                  ),
                  itemCount: 364,
                  itemBuilder: (BuildContext context, int index) {
                    int type = 0;
                    if (_controller.statistics.containsKey(index + 1)) {
                      if (_controller.statistics[index + 1]['count'] <=
                          _controller.averageNumberFiles) {
                        type = 1;
                      } else {
                        type = 2;
                      }
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: type == 0
                            ? Colors.grey[200]
                            : type == 1
                                ? Colors.red[100]
                                : Colors.red,
                        borderRadius: BorderRadius.circular(2.w),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statisticsItem(String amount, String unit, Color color) {
    return Expanded(
      child: Container(
        height: 30.w,
        margin: EdgeInsets.symmetric(horizontal: 2.w),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8.w),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              amount,
              style: TextStyle(
                height: 0.1,
                color: isDarkMode ? Colors.white : Colors.black87,
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            2.horizontalSpace,
            Text(
              unit,
              style: TextStyle(
                height: 0.1,
                color: isDarkMode ? Colors.grey[500] : Colors.grey,
                fontSize: 10.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _member() {
    return Container(
      margin: EdgeInsets.only(bottom: 15.w),
      decoration: BoxDecoration(
        color: MeetingUIUtils.getCardColor(isDarkMode),
        borderRadius: BorderRadius.circular(16.w),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              Get.to(() => const MeetingMemberView());
            },
            behavior: HitTestBehavior.translucent,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'voitransAiMember'.tr, // 对应中文：Voitrans AI会员
                    style: TextStyle(
                      color: MeetingUIUtils.getTextColor(isDarkMode),
                      fontSize: 16.sp,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16.w,
                    color: isDarkMode ? Colors.grey[500] : Colors.grey,
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              Get.bottomSheet(
                const MemberBottomSheet(),
                isScrollControlled: true,
                backgroundColor:
                    isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(12.r),
                  ),
                ),
              );
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 15.w),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.black87,
                borderRadius: BorderRadius.circular(16.w),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: Colors.amberAccent,
                        size: 25.sp,
                      ),
                      5.horizontalSpace,
                      Text(
                        'unlockStarterMember'.tr, // 对应中文：解锁 Starter 会员
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 15.w),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'bindDeviceToActivate'
                              .tr, // 对应中文：绑定 Voitrans 设备可激活 Starter 会员
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.sp,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.w,
                            vertical: 6.w,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(50.w),
                            gradient: const LinearGradient(
                              colors: [Colors.blue, Colors.pink],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          child: Text(
                            'unlockNow'.tr, // 对应中文：立即解锁
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(List<Widget> children) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 5.w),
      margin: EdgeInsets.only(bottom: 15.w),
      decoration: BoxDecoration(
        color: MeetingUIUtils.getCardColor(isDarkMode),
        borderRadius: BorderRadius.circular(16.w),
        boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _item(
    IconData icon,
    String title, {
    String? description,
    Function()? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.w),
        child: Row(
          children: [
            Icon(
              icon,
              size: 24.w,
              color: isDarkMode ? Colors.grey[400] : Colors.grey,
            ),
            8.horizontalSpace,
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16.sp,
                ),
              ),
            ),
            if (description != null)
              Padding(
                padding: EdgeInsets.only(right: 5.w),
                child: Text(
                  description,
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey[500] : Colors.grey,
                    fontSize: 16.sp,
                  ),
                ),
              ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16.w,
              color: isDarkMode ? Colors.grey[400] : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
