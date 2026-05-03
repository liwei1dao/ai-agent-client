import 'dart:convert';

import 'package:common_utils/common_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:lottie/lottie.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../../../data/services/network/api.dart';
import '../../controllers/meeting_details_controller.dart';

class SpeakerAllBottomSheet extends StatefulWidget {
  const SpeakerAllBottomSheet({super.key});

  @override
  State<SpeakerAllBottomSheet> createState() => _SpeakerAllBottomSheetState();
}

class _SpeakerAllBottomSheetState extends State<SpeakerAllBottomSheet> {
  final _controller = Get.find<MeetingDetailsController>();
  final GetStorage _storage = GetStorage();

  List _dataList = [];

  List _historySpeakerList = [];
  List _speakerList = [];

  @override
  void initState() {
    super.initState();
    _controller.playerController.pausePlayer();
    _controller.speakerAllStarttime.value = -1;
    _controller.speakerAllEndtime.value = -1;
    _getSpeakerList();
  }

  @override
  void dispose() {
    _controller.playerController.pausePlayer();
    _controller.speakerAllStarttime.value = -1;
    _controller.speakerAllEndtime.value = -1;
    super.dispose();
  }

  void _getSpeakerList() {
    _historySpeakerList = _storage.read("speaker_list") ?? [];
    _speakerList = List.from(_historySpeakerList);
    List textList = _controller.textList;
    List dataList = [];
    for (var item in textList) {
      String speaker = item['speaker'];
      Map? foundElement = dataList.firstWhere(
        (element) => element['speaker'] == speaker,
        orElse: () => null,
      );
      if (foundElement != null) {
        int time = item['endtime'] - item['starttime'];
        foundElement['totaltime'] = foundElement['totaltime'] + time;
        if (!foundElement['isOmit']) {
          if (foundElement['list'].length < 2) {
            foundElement['list'].add(Map.from(item));
          } else {
            foundElement['isOmit'] = true;
          }
        }
      } else {
        dataList.add({
          'speaker': speaker,
          'speakerText': TextEditingController(),
          'isShow': false,
          'totaltime': item['endtime'] - item['starttime'],
          'isOmit': false,
          'list': [Map.from(item)],
        });
      }
      if (speaker.isNotEmpty &&
          !RegExp(r'^Speaker \d+$').hasMatch(speaker) &&
          !_speakerList.contains(speaker)) {
        _speakerList.add(speaker);
      }
    }
    setState(() {
      _dataList = dataList;
    });
  }

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
                    'nameSpeaker'.tr, // 对应中文：命名发言者
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
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[400],
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
              constraints: BoxConstraints(
                maxHeight:
                    1.sh - 240.w - MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ListView.builder(
                itemCount: _dataList.length,
                shrinkWrap: true,
                itemBuilder: (BuildContext context, int index) {
                  Map item = _dataList[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: EdgeInsets.only(top: 15.w),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF2D2D2D)
                              : Colors.white,
                          borderRadius:
                              item['isShow'] && _speakerList.isNotEmpty
                                  ? BorderRadius.vertical(
                                      top: Radius.circular(12.r),
                                    )
                                  : BorderRadius.circular(12.r),
                        ),
                        child: Focus(
                          onFocusChange: (bool hasFocus) {
                            setState(() {
                              item['isShow'] = hasFocus;
                            });
                          },
                          child: TextField(
                            controller: item['speakerText'],
                            style: TextStyle(
                              fontSize: 16.sp,
                              color: isDarkMode ? Colors.white : Colors.black87,
                              letterSpacing: 0,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              hintText: item['speaker'],
                              hintStyle: TextStyle(
                                fontSize: 16.sp,
                                color: isDarkMode
                                    ? Colors.grey[500]
                                    : Colors.grey[400],
                                letterSpacing: 0,
                                height: 1.4,
                              ),
                              isDense: true,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10.w,
                                vertical: 12.w,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (item['isShow'] && _speakerList.isNotEmpty)
                        Container(
                          padding: EdgeInsets.only(left: 10.w),
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF2D2D2D)
                                : Colors.white,
                            borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(12.r),
                            ),
                            border: Border(
                              top: BorderSide(
                                width: 1,
                                color: isDarkMode
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    EdgeInsets.only(top: 10.w, bottom: 5.w),
                                child: Text(
                                  'recentlyUsedNames'.tr, // 对应中文：最近使用过的名称
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: isDarkMode
                                        ? Colors.grey[500]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ),
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: 150.h,
                                ),
                                child: ListView.builder(
                                  itemCount: _speakerList.length,
                                  shrinkWrap: true,
                                  itemBuilder: (BuildContext context, int idx) {
                                    return GestureDetector(
                                      onTap: () {
                                        item['speakerText'].text =
                                            _speakerList[idx];
                                        FocusScope.of(context).unfocus();
                                      },
                                      behavior: HitTestBehavior.translucent,
                                      child: SizedBox(
                                        height: 42.w,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _speakerList[idx],
                                            style: TextStyle(
                                              fontSize: 14.sp,
                                              color: isDarkMode
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 8.w,
                        ),
                        child: Row(
                          children: [
                            Text(
                              'totalTime'.tr, // 对应中文：总计
                              style: TextStyle(
                                fontSize: 12.sp,
                                color:
                                    isDarkMode ? Colors.grey[500] : Colors.grey,
                              ),
                            ),
                            5.horizontalSpace,
                            Text(
                              '${item['totaltime'] / 1000}s',
                              style: TextStyle(
                                fontSize: 12.sp,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...List.generate(
                        item['list'].length,
                        (int idx) {
                          Map data = item['list'][idx];
                          return Obx(() {
                            bool isActive = false;
                            if (_controller.speakerAllStarttime.value ==
                                    data['starttime'] &&
                                _controller.speakerAllEndtime.value ==
                                    data['endtime']) {
                              isActive = true;
                            }
                            return GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onTap: () {
                                if (isActive) {
                                  _controller.playerController.pausePlayer();
                                  _controller.speakerAllStarttime.value = -1;
                                  _controller.speakerAllEndtime.value = -1;
                                } else {
                                  _controller.speakerAllStarttime.value =
                                      data['starttime'];
                                  _controller.speakerAllEndtime.value =
                                      data['endtime'];
                                  _controller.playerController
                                      .seekTo(data['starttime']);
                                  _controller.playerController.startPlayer();
                                }
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10.w),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isActive
                                              ? Icons.pause_circle
                                              : Icons.play_circle,
                                          color: Colors.red[400],
                                          size: 15.w,
                                        ),
                                        2.horizontalSpace,
                                        Text(
                                          DateUtil.formatDateMs(
                                            data['starttime'],
                                            format: 'HH:mm:ss',
                                            isUtc: true,
                                          ),
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.grey[500]
                                                : Colors.grey,
                                            fontSize: 12.sp,
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 2.w),
                                          child: Text(
                                            '-',
                                            style: TextStyle(
                                              color: isDarkMode
                                                  ? Colors.grey[500]
                                                  : Colors.grey,
                                              fontSize: 12.sp,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          DateUtil.formatDateMs(
                                            data['endtime'],
                                            format: 'HH:mm:ss',
                                            isUtc: true,
                                          ),
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.grey[500]
                                                : Colors.grey,
                                            fontSize: 12.sp,
                                          ),
                                        ),
                                        5.horizontalSpace,
                                        Text(
                                          '${(data['endtime'] - data['starttime']) / 1000}s',
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.black54,
                                            fontSize: 12.sp,
                                          ),
                                        ),
                                        if (isActive)
                                          Container(
                                            width: 16.w,
                                            height: 16.w,
                                            margin: EdgeInsets.only(left: 5.w),
                                            alignment: Alignment.center,
                                            clipBehavior: Clip.hardEdge,
                                            decoration: const BoxDecoration(),
                                            child: Transform.scale(
                                              scale: 1.6,
                                              child: Lottie.asset(
                                                'assets/lottie/sound_effect.json',
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 8.w),
                                      child: Text(
                                        data['content'],
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                        style: TextStyle(
                                          color: isActive
                                              ? Colors.red
                                              : isDarkMode
                                                  ? Colors.grey[400]
                                                  : Colors.grey[700],
                                          fontSize: 12.sp,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          });
                        },
                      ),
                      if (item['isOmit'])
                        Padding(
                          padding: EdgeInsets.only(
                              left: 10.w, top: 5.w, bottom: 8.w),
                          child: Row(
                            children: List.generate(
                              6,
                              (int idx) => Container(
                                width: 3.w,
                                height: 3.w,
                                margin: EdgeInsets.only(right: 3.w),
                                decoration: BoxDecoration(
                                  color: Colors.grey[700],
                                  borderRadius: BorderRadius.circular(3.r),
                                ),
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(top: 7.w),
                        child: _separator(),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 5.w),
              child: Text(
                'summarySpeakerWillBeUpdatedAutomatically'
                    .tr, // 对应中文：总结的发言者将自动更新
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
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
                          'cancel'.tr, // 对应中文：取消
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
                      onTap: _save,
                      child: Container(
                        height: 48.w,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDarkMode ? Colors.white : Colors.black,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Text(
                          'confirm'.tr, // 对应中文：确认

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

  Widget _separator() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 2.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[700] : Colors.grey[300]),
              ),
            );
          }),
        );
      },
    );
  }

  void _save() async {
    EasyLoading.show();
    List textList = _controller.textList;
    List newTextList = [];
    List editSpeakerList = [];
    List personnelList = [];
    String personnel = '';
    bool isLoopEnd = false;
    for (var element in textList) {
      final dataMap = Map<String, dynamic>.from(element);
      for (var data in _dataList) {
        String speaker = data['speakerText'].text;
        if (speaker.isNotEmpty && speaker != data['speaker']) {
          if (!isLoopEnd) {
            personnelList.add({
              'original': data['speaker'],
              'speaker': speaker,
            });
          }
          if (dataMap['speaker'] == data['speaker']) {
            dataMap['speaker'] = speaker;
            editSpeakerList.add({
              'id': dataMap['id'],
              'speaker': dataMap['speaker'],
            });
          }
          if (!RegExp(r'^Speaker \d+$').hasMatch(speaker) &&
              !_historySpeakerList.contains(speaker)) {
            _historySpeakerList.insert(0, speaker);
          }
        }
      }
      if (!personnel.contains(dataMap['speaker'])) {
        personnel += '[${dataMap['speaker']}] ';
      }
      newTextList.add(dataMap);
      isLoopEnd = true;
    }
    if (editSpeakerList.isNotEmpty) {
      var result = await SqfliteApi.editMeetingSpeaker(editSpeakerList);
      if (result != null) {
        bool isEditSummary = false;
        String summaryText = _controller.meetingDetails.value.summary;
        _controller.textList.value = newTextList;
        Map modifyData = {
          'id': _controller.meetingData.value.id,
          'translate': jsonEncode(_controller.textList),
          'personnel': personnel,
        };
        for (var element in personnelList) {
          if (summaryText.contains('[${element['original']}]')) {
            summaryText = summaryText.replaceAll(
                '[${element['original']}]', '[${element['speaker']}]');
            isEditSummary = true;
          }
        }
        if (isEditSummary) {
          SqfliteApi.editMeeting(_controller.id, {
            'summary': summaryText,
            'personnel': personnel,
          });
          modifyData.addAll({'summary': summaryText});
          _controller.meetingDetails.value.summary = summaryText;
          _controller.summaryNumberModifications.value++;
        } else {
          SqfliteApi.editMeeting(_controller.id, {'personnel': personnel});
        }
        await Api.modifyRecordEchomeet(modifyData);
        _controller.meetingDetails.value.personnel = personnel;
        _controller.personnelNumberModifications.value++;
        _controller.meetingDetails.refresh();
        _storage.write("speaker_list", _historySpeakerList);
        Get.back();
      }
    } else {
      Get.back();
    }
    EasyLoading.dismiss();
  }
}
