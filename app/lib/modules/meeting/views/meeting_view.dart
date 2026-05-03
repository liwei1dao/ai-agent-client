import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../controllers/meeting_controller.dart';
import '../utils/meeting_ui_utils.dart';
import 'bottomSheet/filtrate_drawer.dart';
import 'bottomSheet/navigation_bar_bottom_sheet.dart';

///meeting模块主容器页面，提供底部导航栏、浮动按钮、侧板抽屉
class MeetingView extends GetView<MeetingController> {
  const MeetingView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: controller.scaffoldKey,
      backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
      body: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          PageView(
            physics: const NeverScrollableScrollPhysics(),
            controller: controller.pageController,
            children: controller.pageList,
          ),
          if (controller.type == 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Obx(
                () => SafeArea(
                  top: false,
                  child: BottomNavigationBar(
                    items: [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.folder_outlined),
                        activeIcon: Icon(Icons.folder),
                        label: 'files'.tr, // 对应中文：文件
                      ),
                      BottomNavigationBarItem(
                        icon: SizedBox(),
                        label: '',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.person_outline),
                        activeIcon: Icon(Icons.person),
                        label: 'mine'.tr, // 对应中文：我的
                      ),
                    ],
                    backgroundColor:
                        isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
                    currentIndex: controller.pageIndex.value,
                    unselectedItemColor: Colors.grey,
                    selectedItemColor: isDarkMode ? Colors.white : Colors.blue,
                    unselectedFontSize: 10.sp,
                    selectedFontSize: 10.sp,
                    onTap: (int index) {
                      if (index == 1 || index == controller.pageIndex.value) {
                        return;
                      }
                      if (index == 0) {
                        controller.pageIndex.value = 0;
                        controller.pageController.jumpToPage(0);
                      } else {
                        controller.pageIndex.value = 2;
                        controller.pageController.jumpToPage(1);
                      }
                    },
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: ScreenUtil().bottomBarHeight + 10,
            child: GestureDetector(
              onTap: () {
                Get.bottomSheet(
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: const NavigationBarBottomSheet(),
                  ),
                  isScrollControlled: true,
                );
              },
              child: Container(
                width: 60,
                height: 60,
                padding: const EdgeInsets.all(5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
                  borderRadius: BorderRadius.circular(60),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: isDarkMode ? 0.3 : 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MeetingUIUtils.getButtonColor(isDarkMode),
                    borderRadius: BorderRadius.circular(60),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        width: 260.w,
        backgroundColor: isDarkMode ? const Color(0xFF1A1A1A) : Colors.grey[50],
        child: const FiltrateDrawer(),
      ),
      drawerEnableOpenDragGesture: false,
    );
  }
}
