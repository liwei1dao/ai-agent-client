import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/services/db/sqflite_api.dart';
import '../views/meeting_home_view.dart';
import '../views/meeting_mine_view.dart';

// 会议模块控制器
class MeetingController extends GetxController {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  late PageController pageController;

  final List<Widget> pageList = [
    const MeetingHomeView(),
    const MeetingMineView(),
  ];

  int type = 1;

  RxInt pageIndex = 0.obs;

  RxMap user = {}.obs;

  @override
  void onInit() {
    super.onInit();
    pageController = PageController(initialPage: 0);
    _getUser();
  }

  void _getUser() async {
    user.value = Map.from(await SqfliteApi.getUser());
  }
}
