import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

class RecordLanguageBottomSheet extends StatefulWidget {
  final String language;
  final String? title;

  const RecordLanguageBottomSheet(this.language, {super.key, this.title});

  @override
  State<RecordLanguageBottomSheet> createState() =>
      _RecordLanguageBottomSheetState();
}

class _RecordLanguageBottomSheetState extends State<RecordLanguageBottomSheet> {
  final List _languages = [
    {'name': 'chinese'.tr, 'value': 'zh-CN'}, // 对应中文：中文普通话(简体)
    {'name': 'cantonese'.tr, 'value': 'cant'}, // 对应中文：粤语
    {'name': 'sichuan'.tr, 'value': 'sc'}, // 对应中文：四川话
    {'name': 'shanghai'.tr, 'value': 'zh_shanghai'}, // 对应中文：上海话
    {'name': 'english'.tr, 'value': 'en-US'}, // 对应中文：英文
    {'name': 'japanese'.tr, 'value': 'ja-JP'}, // 对应中文：日语
    {'name': 'korean'.tr, 'value': 'ko-KR'}, // 对应中文：韩语
    {'name': 'french'.tr, 'value': 'fr-FR'}, // 对应中文：法语
    {'name': 'spanish'.tr, 'value': 'es-MX'}, // 对应中文：西班牙语
    {'name': 'portuguese'.tr, 'value': 'pt-BR'}, // 对应中文：葡萄牙语
    {'name': 'indonesian'.tr, 'value': 'id-ID'}, // 对应中文：印尼语
  ];

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
                    widget.title ?? 'recordLanguage'.tr, // 对应中文：录音语言
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
              margin: EdgeInsets.symmetric(vertical: 20.w),
              constraints: BoxConstraints(
                maxHeight: 1.sh - 180.w,
              ),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: ListView.builder(
                itemCount: _languages.length,
                shrinkWrap: true,
                itemBuilder: (BuildContext context, int index) {
                  Map data = _languages[index];
                  return _item(index, data, isDarkMode);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(int index, Map data, bool isDarkMode) {
    return GestureDetector(
      onTap: () {
        Get.back(result: data);
      },
      child: Padding(
        padding: EdgeInsets.only(left: 15.w),
        child: Container(
          height: 46.w,
          padding: EdgeInsets.only(right: 10.w),
          decoration: BoxDecoration(
            border: index != 0
                ? Border(
                    top: BorderSide(
                      color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  data['name'],
                  style: TextStyle(
                    fontSize: 14.sp,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (widget.language == data['value'])
                Icon(
                  Icons.check,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
