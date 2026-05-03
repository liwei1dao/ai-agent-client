import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../data/services/db/sqflite_api.dart';
import '../../profile/controllers/profile_controller.dart';
import 'meeting_controller.dart';
import 'meeting_home_controller.dart';

class MeetingMineController extends GetxController {
  final _meetingController = Get.find<MeetingController>();
  final _homeController = Get.find<MeetingHomeController>();
  final profileCtrl = Get.find<ProfileController>();

  final ScrollController scrollController = ScrollController();

  late final Worker _pageIndexListener;
  late final Worker _originalDataListener;

  bool isStatistics = true;
  Map statistics = {};

  RxInt days = 0.obs;
  RxInt numberFiles = 0.obs;
  RxDouble hourage = 0.0.obs;
  RxInt continuousDays = 0.obs;
  RxInt maxNumberFiles = 0.obs;
  RxDouble maxHourage = 0.0.obs;

  int averageNumberFiles = 0;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        final now = DateTime.now();
        if (now.month > 6) {
          scrollController.jumpTo(scrollController.position.maxScrollExtent);
        }
      }
    });
    _getStatistics();
    _pageIndexListener = ever(_meetingController.pageIndex, (value) {
      if (isStatistics && value == 2) {
        _getStatistics();
      }
    });
    _originalDataListener = ever(_homeController.originalDataList, (value) {
      isStatistics = true;
    });
  }

  @override
  void onClose() {
    _pageIndexListener.dispose();
    _originalDataListener.dispose();
    scrollController.dispose();
    super.onClose();
  }

  void _getStatistics() async {
    if (!isStatistics) return;
    List dataList = await SqfliteApi.getMeetingList();
    numberFiles.value = dataList.length;
    statistics = {};

    for (var element in dataList) {
      DateTime creationtime =
          DateTime.fromMillisecondsSinceEpoch(element['creationtime']);
      int dayOfYear = DateUtil.getDayOfYear(creationtime);

      if (!statistics.containsKey(dayOfYear)) {
        statistics[dayOfYear] = {
          'creationtime': creationtime,
          'count': 0,
          'seconds': 0,
        };
      }
      statistics[dayOfYear]['count']++;
      statistics[dayOfYear]['seconds'] += element['seconds'];
    }

    int currentD = 1;
    int maxD = 1;
    int previous = 0;
    int h = 0;
    int maxH = 0;
    int maxN = 0;
    int minN = 0;
    statistics.forEach((key, value) {
      h += value['seconds'] as int;
      if (key + 1 == previous) {
        currentD++;
        if (currentD > maxD) {
          maxD = currentD;
        }
      } else {
        currentD = 1;
      }
      previous = key;
      if (value['count'] > maxN) {
        maxN = value['count'];
      }
      if (value['count'] < minN || minN == 0) {
        minN = value['count'];
      }
      if (value['seconds'] > maxH) {
        maxH = value['seconds'];
      }
    });

    days.value = statistics.length;
    hourage.value = double.parse((h / 60 / 60).toStringAsFixed(2));
    continuousDays.value = maxD;
    maxNumberFiles.value = maxN;
    maxHourage.value = double.parse((maxH / 60 / 60).toStringAsFixed(2));
    averageNumberFiles = (maxN + minN) ~/ 2;
    isStatistics = false;
  }
}
