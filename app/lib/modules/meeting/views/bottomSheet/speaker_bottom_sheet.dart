import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../../../data/services/network/api.dart';
import '../../controllers/meeting_details_controller.dart';

class SpeakerBottomSheet extends StatefulWidget {
  final int id;
  final String speakerName;

  const SpeakerBottomSheet(this.id, this.speakerName, {super.key});

  @override
  State<SpeakerBottomSheet> createState() => _SpeakerBottomSheetState();
}

class _SpeakerBottomSheetState extends State<SpeakerBottomSheet> {
  final _controller = Get.find<MeetingDetailsController>();
  final GetStorage _storage = GetStorage();

  final TextEditingController _speakerController = TextEditingController();
  int _type = 1;
  List _historySpeakerList = [];
  List _speakerList = [];

  @override
  void initState() {
    super.initState();
    _getSpeakerList();
  }

  void _getSpeakerList() {
    _historySpeakerList = _storage.read("speaker_list") ?? [];
    List speakerList = List.from(_historySpeakerList);
    List textList = _controller.textList;
    for (var element in textList) {
      String speaker = element['speaker'];
      if (speaker.isNotEmpty &&
          !RegExp(r'^Speaker \d+$').hasMatch(speaker) &&
          !speakerList.contains(speaker)) {
        speakerList.add(speaker);
      }
    }
    setState(() {
      _speakerList = speakerList;
    });
  }

  @override
  void dispose() {
    _speakerController.dispose();
    super.dispose();
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
                    'nameCurrentSpeaker'.tr, // 对应中文：命名当前发言者
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
                        color: Colors.grey[400],
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
              margin: EdgeInsets.symmetric(vertical: 15.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: TextField(
                controller: _speakerController,
                style: TextStyle(
                  fontSize: 16.sp,
                  color: isDarkMode ? Colors.white : Colors.black87,
                  letterSpacing: 0,
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: widget.speakerName,
                  hintStyle: TextStyle(
                    fontSize: 16.sp,
                    color: Colors.grey[400],
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
            Container(
              constraints: BoxConstraints(
                maxHeight:
                    1.sh - 390.w - MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ListView.builder(
                itemCount: _speakerList.length,
                shrinkWrap: true,
                itemBuilder: (BuildContext context, int index) {
                  return Container(
                    padding: EdgeInsets.only(left: 10.w),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
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
                        if (index == 0)
                          Text(
                            'recentlyUsedNames'.tr, // 对应中文：最近使用过的名称
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: isDarkMode
                                  ? Colors.grey[500]
                                  : Colors.grey[600],
                            ),
                          ),
                        GestureDetector(
                          onTap: () {
                            _speakerController.text = _speakerList[index];
                          },
                          behavior: HitTestBehavior.translucent,
                          child: SizedBox(
                            height: 42.w,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _speakerList[index],
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            _row(
                'applyToCurrentParagraph'.tr, // 对应中文：应用到当前段落
                _type == 0,
                isDarkMode: isDarkMode, onTap: () {
              setState(() {
                _type = 0;
              });
            }),
            _row(
              'applyToAllParagraphs'.tr, // 对应中文：应用到这个发言者的所有段落
              _type == 1,
              isDarkMode: isDarkMode,
              description:
                  'summaryWillBeUpdatedAutomatically'.tr, // 对应中文：总结将根据模版自动更新
              onTap: () {
                setState(() {
                  _type = 1;
                });
              },
            ),
            Padding(
              padding: EdgeInsets.only(top: 10.w, bottom: 20.w),
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
                    'save'.tr, // 对应中文：保存
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
    );
  }

  Widget _row(String name, bool isActive,
      {String? description, Function()? onTap, bool isDarkMode = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.w),
        child: Row(
          children: [
            isActive ? _round(isDarkMode) : _circle(isDarkMode),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (description != null)
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
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

  Widget _circle(bool isDarkMode) {
    return Container(
      width: 18.w,
      height: 18.w,
      margin: EdgeInsets.only(right: 6.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          width: 1.5,
          color: isDarkMode ? Colors.grey[600]! : Colors.grey[300]!,
        ),
      ),
    );
  }

  Widget _round(bool isDarkMode) {
    return Container(
      width: 18.w,
      height: 18.w,
      padding: EdgeInsets.all(2.w),
      margin: EdgeInsets.only(right: 6.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          width: 1.5,
          color: isDarkMode ? Colors.white : Colors.black87,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white : Colors.black87,
          borderRadius: BorderRadius.circular(18.r),
        ),
      ),
    );
  }

  void _save() {
    if (_speakerController.text.isNotEmpty &&
        _speakerController.text != widget.speakerName) {
      if (_type == 0) {
        _single();
      } else {
        _all();
      }
    } else {
      Get.back();
    }
  }

  void _single() async {
    EasyLoading.show();
    List list = [
      {
        'id': widget.id,
        'speaker': _speakerController.text,
      }
    ];
    var result = await SqfliteApi.editMeetingSpeaker(list);
    if (result != null) {
      int index =
          _controller.textList.indexWhere((item) => item['id'] == widget.id);
      if (index != -1) {
        final dataMap = Map<String, dynamic>.from(_controller.textList[index]);
        dataMap['speaker'] = _speakerController.text;
        _controller.textList[index] = dataMap;
      }
      await Api.modifyRecordEchomeet({
        'id': _controller.meetingData.value.id,
        'translate': jsonEncode(_controller.textList),
      });
      _addHistorySpeaker();
      Get.back();
    }
    EasyLoading.dismiss();
  }

  void _all() async {
    EasyLoading.show();
    List textList = _controller.textList;
    List newTextList = [];
    List editSpeakerList = [];
    String personnel = '';
    for (var element in textList) {
      final dataMap = Map<String, dynamic>.from(element);
      if (dataMap['speaker'] == widget.speakerName) {
        dataMap['speaker'] = _speakerController.text;
        editSpeakerList.add({
          'id': dataMap['id'],
          'speaker': dataMap['speaker'],
        });
      }
      String speaker = dataMap['speaker'];
      if (!personnel.contains(speaker)) {
        personnel += '[$speaker] ';
      }
      newTextList.add(dataMap);
    }
    var result = await SqfliteApi.editMeetingSpeaker(editSpeakerList);
    if (result != null) {
      _controller.textList.value = newTextList;
      Map modifyData = {
        'id': _controller.meetingData.value.id,
        'translate': jsonEncode(_controller.textList),
        'personnel': personnel,
      };
      if (_controller.meetingDetails.value.summary
          .contains('[${widget.speakerName}]')) {
        String summaryText = _controller.meetingDetails.value.summary
            .replaceAll(
                '[${widget.speakerName}]', '[${_speakerController.text}]');
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
      _addHistorySpeaker();
      Get.back();
    }
    EasyLoading.dismiss();
  }

  void _addHistorySpeaker() {
    String speaker = _speakerController.text;
    if (speaker.isNotEmpty &&
        !RegExp(r'^Speaker \d+$').hasMatch(speaker) &&
        !_historySpeakerList.contains(speaker)) {
      _historySpeakerList.insert(0, speaker);
      _storage.write("speaker_list", _historySpeakerList);
    }
  }
}
