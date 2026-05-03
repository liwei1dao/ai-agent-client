import 'package:common_utils/common_utils.dart';
import 'package:fleather/fleather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:parchment/codecs.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../../../data/services/network/api.dart';
import '../../controllers/meeting_details_controller.dart';
import '../../utils/meeting_ui_utils.dart';
import '../bottomSheet/ai_bottom_sheet.dart';
import '../bottomSheet/generate_bottom_sheet.dart';
import '../bottomSheet/speaker_all_bottom_sheet.dart';

class SummaryTab extends StatefulWidget {
  const SummaryTab({super.key});

  @override
  State<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends State<SummaryTab> {
  final _controller = Get.find<MeetingDetailsController>();

  late final Worker _personnelListener;

  final String _addressPrefix = '${'location'.tr}:'; // 对应中文：地点
  String _addressText = '';
  final String _personnelPrefix = '${'attendees'.tr}:'; // 对应中文：与会人员
  String _personnelText = '';
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _personnelController = TextEditingController();

  final FocusNode _focusNode = FocusNode();
  final GlobalKey<EditorState> _editorKey = GlobalKey();
  FleatherController? _fleatherController;

  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _initController();
    _addressController.addListener(_handleAddressChanged);
    _personnelController.addListener(_handlePersonnelChanged);
    _focusNode.addListener(() {
      setState(() {
        _hasFocus = _focusNode.hasFocus;
      });
    });
    _personnelListener =
        ever(_controller.personnelNumberModifications, (value) {
      _initController();
    });
  }

  void _initController() {
    _addressController.text = _addressPrefix +
        (_controller.meetingDetails.value.address.isNotEmpty
            ? _controller.meetingDetails.value.address
            : '[${'inputLocation'.tr}]'); // 对应中文：输入地点
    _personnelController.text = _personnelPrefix +
        (_controller.meetingDetails.value.personnel.isNotEmpty
            ? _controller.meetingDetails.value.personnel
            : '[${'inputAttendees'.tr}]'); // 对应中文：输入与会人员
    final raw = _controller.meetingDetails.value.summary;
    // 空内容时给个占位换行，避免 ParchmentMarkdownCodec 在空字符串上抛异常。
    final markdown = const ParchmentMarkdownCodec().decode(
      raw.isEmpty ? '\n' : raw,
    );
    setState(() {
      _fleatherController = FleatherController(document: markdown);
    });
  }

  void _handleAddressChanged() {
    String currentText = _addressController.text;
    TextSelection currentSelection = _addressController.selection;
    if (!currentText.startsWith(_addressPrefix)) {
      _addressController.value = TextEditingValue(
        text: _addressPrefix + _addressText,
        selection: TextSelection.collapsed(
          offset: _addressPrefix.length + _addressText.length,
        ),
      );
      return;
    } else {
      _addressText = currentText.substring(_addressPrefix.length);
    }

    if (currentSelection.start < _addressPrefix.length ||
        currentSelection.end < _addressPrefix.length) {
      int newStart = currentSelection.start < _addressPrefix.length
          ? _addressPrefix.length
          : currentSelection.start;
      int newEnd = currentSelection.end < _addressPrefix.length
          ? _addressPrefix.length
          : currentSelection.end;
      _addressController.selection = currentSelection.copyWith(
        baseOffset: newStart,
        extentOffset: newEnd,
      );
    }
  }

  void _handlePersonnelChanged() {
    String currentText = _personnelController.text;
    TextSelection currentSelection = _personnelController.selection;
    if (!currentText.startsWith(_personnelPrefix)) {
      _personnelController.value = TextEditingValue(
        text: _personnelPrefix + _personnelText,
        selection: TextSelection.collapsed(
          offset: _personnelPrefix.length + _personnelText.length,
        ),
      );
      return;
    } else {
      _personnelText = currentText.substring(_personnelPrefix.length);
    }

    if (currentSelection.start < _personnelPrefix.length ||
        currentSelection.end < _personnelPrefix.length) {
      int newStart = currentSelection.start < _personnelPrefix.length
          ? _personnelPrefix.length
          : currentSelection.start;
      int newEnd = currentSelection.end < _personnelPrefix.length
          ? _personnelPrefix.length
          : currentSelection.end;
      _personnelController.selection = currentSelection.copyWith(
        baseOffset: newStart,
        extentOffset: newEnd,
      );
    }
  }

  void _saveSummary() async {
    final markdown =
        const ParchmentMarkdownCodec().encode(_fleatherController!.document);
    if (markdown != _controller.meetingDetails.value.summary) {
      Api.modifyRecordEchomeet({
        'id': _controller.id,
        'summary': markdown,
      });
      SqfliteApi.editMeeting(
        _controller.id,
        {'summary': markdown},
      );
      _controller.meetingDetails.value.summary = markdown;
      _controller.summaryNumberModifications.value++;
    }
  }

  @override
  void dispose() {
    _personnelListener.dispose();
    _saveSummary();
    _fleatherController?.dispose();
    _focusNode.dispose();
    _addressController.dispose();
    _personnelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final TextStyle textStyle = TextStyle(
      color: isDarkMode ? Colors.grey[400] : Colors.grey[700],
      fontSize: 16.sp,
      letterSpacing: 0,
      height: 1.5,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SingleChildScrollView(
          padding: EdgeInsets.only(bottom: 80.w),
          child: Obx(
            () => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.w),
                  child: Text(
                    _controller.meetingData.value.title,
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.w),
                      margin: EdgeInsets.only(right: 10.w),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[900] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(4.w),
                      ),
                      child: Text(
                        _controller.meetingData.value.type,
                        style: TextStyle(
                          color:
                              isDarkMode ? Colors.grey[400] : Colors.grey[500],
                          fontSize: 10.sp,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.calendar_month,
                      size: 14.w,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                    ),
                    2.horizontalSpace,
                    Text(
                      DateUtil.formatDateMs(
                        _controller.meetingData.value.creationtime,
                        format: DateFormats.y_mo_d_h_m,
                      ),
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                        fontSize: 12.sp,
                      ),
                    ),
                    10.horizontalSpace,
                    Icon(
                      Icons.access_time,
                      size: 14.w,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                    ),
                    2.horizontalSpace,
                    Text(
                      _formatDateSeconds(_controller.meetingData.value.seconds),
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.w),
                  child: Divider(
                    height: 1,
                    color: isDarkMode ? Colors.grey[900] : Colors.grey[300],
                  ),
                ),
                Container(
                  padding: EdgeInsets.only(left: 20.w),
                  margin: EdgeInsets.symmetric(vertical: 10.w),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        width: 2,
                        color: isDarkMode
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.grey[300]!,
                      ),
                    ),
                  ),
                  child: Focus(
                    onFocusChange: (bool hasFocus) {
                      if (!hasFocus) {
                        bool isEdit = false;
                        if (_addressText.isNotEmpty &&
                            _addressText !=
                                _controller.meetingDetails.value.address) {
                          _controller.meetingDetails.value.address =
                              _addressText;
                          isEdit = true;
                        }
                        if (_personnelText.isNotEmpty &&
                            _personnelText !=
                                _controller.meetingDetails.value.personnel) {
                          _controller.meetingDetails.value.personnel =
                              _personnelText;
                          isEdit = true;
                        }
                        if (isEdit) {
                          Api.modifyRecordEchomeet({
                            'id': _controller.id,
                            'address': _controller.meetingDetails.value.address,
                            'personnel':
                                _controller.meetingDetails.value.personnel,
                          });
                          SqfliteApi.editMeeting(
                            _controller.id,
                            {
                              'address':
                                  _controller.meetingDetails.value.address,
                              'personnel':
                                  _controller.meetingDetails.value.personnel,
                            },
                          );
                        }
                      }
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${'dateAndTime'.tr}:${DateUtil.formatDateMs(
                            _controller.meetingData.value.creationtime,
                            format: DateFormats.y_mo_d_h_m,
                          )}',
                          style: textStyle,
                        ),
                        TextField(
                          controller: _addressController,
                          style: textStyle,
                          minLines: 1,
                          maxLines: 100,
                          decoration: const InputDecoration(
                            isDense: true,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        TextField(
                          controller: _personnelController,
                          style: textStyle,
                          minLines: 1,
                          maxLines: 100,
                          decoration: const InputDecoration(
                            isDense: true,
                            fillColor: Colors.transparent,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 10.w),
                  child: _controller.meetingDetails.value.tasktype < 10000
                      ? FleatherEditor(
                          controller: _fleatherController!,
                          focusNode: _focusNode,
                          editorKey: _editorKey,
                        )
                      : Center(
                          child: Text(
                            'summaryFailed'.tr, // 总结失败，请稍后重试
                            style: TextStyle(
                              color: MeetingUIUtils.getSecondaryTextColor(
                                  isDarkMode),
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (!_hasFocus)
          Obx(
            () => Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 20.w,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_controller.meetingDetails.value.tasktype >= 3 &&
                      _controller.meetingDetails.value.tasktype < 10000)
                    _button(
                      Icons.supervisor_account,
                      'editSpeaker'.tr, // 对应中文：编辑发言者
                      () {
                        Get.bottomSheet(
                          const SpeakerAllBottomSheet(),
                          isScrollControlled: true,
                          backgroundColor:
                              isDarkMode ? Colors.grey[800] : Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12.r),
                            ),
                          ),
                        );
                      },
                    ),
                  if (_controller.meetingDetails.value.tasktype >= 3 &&
                      _controller.meetingDetails.value.tasktype < 10000)
                    _button(
                      Icons.auto_awesome,
                      'Ask AI',
                      () {
                        Get.bottomSheet(
                          const AIBottomSheet(),
                          isScrollControlled: true,
                          backgroundColor:
                              isDarkMode ? Colors.grey[800] : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(12.r),
                            ),
                          ),
                        );
                      },
                    ),
                  if (_controller.meetingDetails.value.tasktype == 0)
                    SizedBox(
                      width: 150.w,
                      child: _button(
                        Icons.auto_awesome,
                        'generate'.tr, // 对应中文：生成
                        () {
                          Get.bottomSheet(
                            const GenerateBottomSheet(),
                            isScrollControlled: true,
                            backgroundColor: isDarkMode
                                ? Colors.grey[800]
                                : Colors.grey[100],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(12.r),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (_controller.meetingDetails.value.tasktype == 10002)
                    SizedBox(
                      width: 150.w,
                      child: _button(
                        Icons.auto_awesome,
                        'regenerate'.tr, // 重新生成
                        () {
                          Get.bottomSheet(
                            const GenerateBottomSheet(),
                            isScrollControlled: true,
                            backgroundColor: isDarkMode
                                ? Colors.grey[800]
                                : Colors.grey[100],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(12.r),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  if (_controller.meetingDetails.value.tasktype == 10001)
                    SizedBox(
                      width: 150.w,
                      child: _button(
                        Icons.auto_awesome,
                        'reSummarize'.tr, // 重新总结
                        () {
                          Get.bottomSheet(
                            const GenerateBottomSheet(
                              isSummarizeAgain: true,
                            ),
                            isScrollControlled: true,
                            backgroundColor: isDarkMode
                                ? Colors.grey[800]
                                : Colors.grey[100],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(12.r),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (_hasFocus)
          Positioned(
            bottom: 0,
            left: -12.w,
            right: -12.w,
            child: SafeArea(
              top: false,
              child: Container(
                height: 40,
                color: isDarkMode ? Colors.grey[800] : Colors.white,
                alignment: Alignment.center,
                child: FleatherToolbar.basic(
                  controller: _fleatherController!,
                  editorKey: _editorKey,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _button(IconData icon, String title, Function() onTap) {
    return Builder(
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42.w,
            padding: EdgeInsets.symmetric(horizontal: 15.w),
            margin: EdgeInsets.symmetric(horizontal: 4.w),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(42.w),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isDarkMode ? Colors.black : Colors.white,
                  size: 20.sp,
                ),
                5.horizontalSpace,
                Text(
                  title,
                  style: TextStyle(
                    color: isDarkMode ? Colors.black : Colors.white,
                    fontSize: 14.sp,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDateSeconds(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      int minutes = seconds ~/ 60;
      int remainingSeconds = seconds % 60;
      return '${minutes}m ${remainingSeconds}s';
    } else {
      int hours = seconds ~/ 3600;
      int remainingMinutes = (seconds % 3600) ~/ 60;
      int remainingSeconds = seconds % 60;
      return '${hours}h ${remainingMinutes}m ${remainingSeconds}s';
    }
  }
}
