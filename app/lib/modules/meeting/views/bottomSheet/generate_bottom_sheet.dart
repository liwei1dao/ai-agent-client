import '../../../../data/services/db/sqflite_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../controllers/meeting_details_controller.dart';
import 'record_language_bottom_sheet.dart';
import '../template/template_view.dart';
import '../../../../data/models/user_Info.dart';
import '../../../common/widgets/recharge_dialog.dart';

class GenerateBottomSheet extends StatefulWidget {
  final bool isSummarizeAgain;

  const GenerateBottomSheet({super.key, this.isSummarizeAgain = false});

  @override
  State<GenerateBottomSheet> createState() => _GenerateBottomSheetState();
}

class _GenerateBottomSheetState extends State<GenerateBottomSheet> {
  final _controller = Get.find<MeetingDetailsController>();
  final ScrollController _scrollController = ScrollController();

  final GetStorage _storage = GetStorage();

  bool _isSpeaker = true;
  String _formlanguageText = 'chineseSimplified'.tr; // 对应中文：中文普通话(简体)
  String _formlanguage = 'zh-CN';
  String _tolanguageText = 'chineseSimplified'.tr; // 对应中文：中文普通话(简体)
  String _tolanguage = 'zh-CN';

  final Map _icons = {
    'auto_stories': Icons.auto_stories,
    'auto_graph': Icons.auto_graph,
    'add_to_drive_outlined': Icons.add_to_drive_outlined,
    'perm_phone_msg': Icons.perm_phone_msg,
    'assignment': Icons.assignment,
    'lightbulb': Icons.lightbulb,
    'note': Icons.note,
    'rate_review': Icons.rate_review,
    'event_repeat': Icons.event_repeat,
    'handshake': Icons.handshake,
    'restart_alt': Icons.restart_alt,
    'rocket_launch': Icons.rocket_launch,
    'code': Icons.code,
    'bar_chart': Icons.bar_chart,
    'school': Icons.school,
    'auto_fix_high': Icons.auto_fix_high,
  };

  List _originalTemplate = [];

  Map _templateData = {};
  Map _lastTemplateData = {};
  List _templateList = [];

  @override
  void initState() {
    super.initState();
    _getTemplate();
  }

  void _getTemplate() async {
    _controller.categoryTemplateList =
        await SqfliteApi.getMeetingCategoryTemplateList();
    _controller.editTemplate = {};
    _controller.deleteTemplateId = 0;
    _lastTemplateData = _storage.read("meeting_last_template_Data") ?? {};
    _originalTemplate = _storage.read("meeting_template_list") ??
        _controller.categoryTemplateList[0]['template'];
    if (_lastTemplateData.isNotEmpty) {
      _templateData = _lastTemplateData;
    } else {
      _templateData = _originalTemplate[0];
    }
    setState(() {
      _templateList = List.from(_originalTemplate);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
            child: Row(
              children: [
                Icon(
                  Icons.audio_file_outlined,
                  color: isDarkMode ? Colors.grey[500] : Colors.grey,
                  size: 32.w,
                ),
                5.horizontalSpace,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _controller.meetingData.value.title,
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '${_controller.meetingData.value.seconds}s',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isDarkMode ? Colors.grey[500] : Colors.grey,
                        ),
                      ),
                    ],
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
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            margin: EdgeInsets.only(bottom: 10.w),
            child: Divider(
              height: 1,
              color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.w),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'selectSummaryTemplate'.tr, // 对应中文：选择总结模版
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    var result = await Get.to(
                      () => TemplateView(
                        _templateData,
                        _lastTemplateData['id'] ?? 0,
                      ),
                      preventDuplicates: false,
                    );
                    if (result != null) {
                      _scrollController.jumpTo(0);
                      List list = List.from(_originalTemplate);
                      int index = list.indexWhere(
                          (element) => element['id'] == result['id']);
                      if (index != -1) {
                        Map itemToMove = list.removeAt(index);
                        list.insert(0, itemToMove);
                      } else {
                        list.insert(0, result);
                      }
                      setState(() {
                        _templateData = result;
                        _templateList = list;
                      });
                    }
                    if (_controller.editTemplate.isNotEmpty) {
                      Map? editMap = _templateList.firstWhere(
                          (element) =>
                              element['id'] == _controller.editTemplate['id'],
                          orElse: () => null);
                      if (editMap != null) {
                        editMap['name'] = _controller.editTemplate['name'];
                        editMap['desc'] = _controller.editTemplate['desc'];
                        editMap['prompt'] = _controller.editTemplate['prompt'];
                      }
                      if (_controller.editTemplate['id'] ==
                          _templateData['id']) {
                        _templateData['name'] =
                            _controller.editTemplate['name'];
                        _templateData['desc'] =
                            _controller.editTemplate['desc'];
                        _templateData['prompt'] =
                            _controller.editTemplate['prompt'];
                      }
                      setState(() {});
                    }
                    if (_controller.deleteTemplateId != 0) {
                      _templateList.removeWhere((element) =>
                          element['id'] == _controller.deleteTemplateId);
                      if (_controller.deleteTemplateId == _templateData['id']) {
                        _templateData = _templateList[0];
                      }
                      setState(() {});
                      _storage.write("meeting_last_template_Data", {});
                      _storage.write("meeting_template_list", _templateList);
                    }
                  },
                  child: Row(
                    children: [
                      Text(
                        'viewAll'.tr, // 对应中文：查看全部
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isDarkMode ? Colors.grey[500] : Colors.grey,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_right,
                        color: isDarkMode ? Colors.grey[500] : Colors.grey,
                      )
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 130.w,
            margin: EdgeInsets.only(bottom: 16.w),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _templateList.length,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              itemBuilder: (BuildContext context, int index) {
                Map data = _templateList[index];
                return _item(data);
              },
            ),
          ),
          Container(
              margin: EdgeInsets.symmetric(horizontal: 12.w),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                children: [
                  if (!widget.isSummarizeAgain)
                    _row(
                      'speakerIdentification'.tr, // 对应中文：区分说话人
                      isDarkMode: isDarkMode,
                      widget: Transform.scale(
                        scale: 0.8,
                        alignment: Alignment.centerRight,
                        child: Switch(
                          value: _isSpeaker,
                          onChanged: (bool value) {
                            setState(() {
                              _isSpeaker = value;
                            });
                          },
                        ),
                      ),
                    ),
                  if (!widget.isSummarizeAgain)
                    _row(
                      'recordingLanguage'.tr, // 对应中文：录音语言
                      value: _formlanguageText,
                      isDarkMode: isDarkMode,
                      onTap: () {
                        Get.bottomSheet(
                          RecordLanguageBottomSheet(_formlanguage),
                          isScrollControlled: true,
                          backgroundColor:
                              isDarkMode ? Colors.grey[850] : Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12.r),
                            ),
                          ),
                        ).then((value) {
                          if (value != null) {
                            setState(() {
                              _formlanguageText = value['name'];
                              _formlanguage = value['value'];
                            });
                          }
                        });
                      },
                    ),
                  _row(
                    'targetLanguage'.tr, // 对应中文：目标语言
                    value: _tolanguageText,
                    isBorder: false,
                    isDarkMode: isDarkMode,
                    onTap: () {
                      Get.bottomSheet(
                        RecordLanguageBottomSheet(_tolanguage, title: 'targetLanguage'.tr),
                        isScrollControlled: true,
                        backgroundColor:
                            isDarkMode ? Colors.grey[850] : Colors.grey[100],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(12.r),
                          ),
                        ),
                      ).then((value) {
                        if (value != null) {
                          setState(() {
                            _tolanguageText = value['name'];
                            _tolanguage = value['value'];
                          });
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.w),
            child: GestureDetector(
              onTap: () {
                if (User.isLoggedIn() && User.instance.meetintegral <= 0) {
                  showRechargeDialog('meeting');
                  return;
                }
                if (_templateData['id'] != _templateList[0]['id']) {
                  int index = _templateList
                      .indexWhere((v) => v['id'] == _templateData['id']);
                  if (index != -1) {
                    Map itemToMove = _templateList.removeAt(index);
                    _templateList.insert(0, itemToMove);
                  }
                }
                _storage.write("meeting_last_template_Data", _templateData);
                _storage.write("meeting_template_list", _templateList);
                Get.back();
                if (widget.isSummarizeAgain) {
                  _controller.refreshSummary(
                    _templateData['id'],
                    _templateData['tid'] ?? '',
                    _tolanguage,
                  );
                } else {
                  _controller.summaryCreate(
                    _formlanguage,
                    _tolanguage,
                    _isSpeaker,
                    _templateData['id'],
                    _templateData['tid'] ?? '',
                  );
                }
              },
              child: Container(
                height: 48.w,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  'meetingGenerateNow'.tr, // 对应中文：立即生成
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
    );
  }

  Widget _item(Map data) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 200.w,
      margin: EdgeInsets.symmetric(horizontal: 8.w),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.w),
      ),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _templateData = data;
          });
        },
        child: Stack(
          children: [
            Container(
              padding: EdgeInsets.all(5.w),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                gradient: _templateData['id'] == data['id']
                    ? const LinearGradient(
                        colors: [Colors.blue, Colors.pinkAccent],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
              ),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.w),
                  color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(top: 5.w),
                      child: Icon(
                        _icons[data['icon']],
                        color: isDarkMode ? Colors.orange[300] : Colors.orange,
                        size: 30.w,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.w),
                      child: SizedBox(
                        height: 22.w,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data['name'],
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 16.sp,
                              color: isDarkMode ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    data['tag'].isNotEmpty
                        ? Wrap(
                            spacing: 5.w,
                            children: List.generate(
                              data['tag'].length,
                              (int idx) {
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 5.w, vertical: 2.w),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.grey[800]
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                  child: Text(
                                    data['tag'][idx],
                                    style: TextStyle(
                                      fontSize: 10.sp,
                                      color: isDarkMode
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : Text(
                            data['desc'],
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                  ],
                ),
              ),
            ),
            if (_lastTemplateData['id'] == data['id'])
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 1.w),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.w),
                      bottomRight: Radius.circular(4.w),
                    ),
                  ),
                  child: Text(
                    'lastUsed'.tr, // 对应中文：上次使用
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            if (_templateData['id'] == data['id'])
              Positioned(
                right: -18.w,
                bottom: -18.w,
                child: Container(
                  width: 40.w,
                  height: 40.w,
                  padding: EdgeInsets.all(2.w),
                  alignment: Alignment.topLeft,
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent,
                    borderRadius: BorderRadius.circular(40.r),
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 18.w,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    String title, {
    String? value,
    Widget? widget,
    bool isBorder = true,
    bool isDarkMode = false,
    Function()? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 15.w),
        child: Container(
          height: 46.w,
          padding: EdgeInsets.only(right: 10.w),
          decoration: BoxDecoration(
            border: isBorder
                ? Border(
                    bottom: BorderSide(
                      color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              widget ??
                  Row(
                    children: [
                      Text(
                        value ?? '',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: isDarkMode ? Colors.grey[500] : Colors.grey,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_right,
                        color: isDarkMode ? Colors.grey[500] : Colors.grey,
                      )
                    ],
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
