import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../controllers/meeting_controller.dart';
import '../../controllers/meeting_home_controller.dart';
import '../../utils/meeting_ui_utils.dart';

class FiltrateDrawer extends StatefulWidget {
  const FiltrateDrawer({super.key});

  @override
  State<FiltrateDrawer> createState() => _FiltrateDrawerState();
}

class _FiltrateDrawerState extends State<FiltrateDrawer> {
  final _controller = Get.find<MeetingController>();
  final _homeController = Get.find<MeetingHomeController>();

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              margin: EdgeInsets.symmetric(vertical: 15.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDarkMode
                    ? MeetingUIUtils.getTranslucentWhite(0.1)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(12.w),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    color: isDarkMode ? Colors.grey[400] : Colors.black87,
                    size: 20.w,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _homeController.filtrateController,
                      style: TextStyle(
                        color: MeetingUIUtils.getTextColor(isDarkMode),
                        fontSize: 14.sp,
                      ),
                      decoration: InputDecoration(
                        hintText: 'searchInAllFiles'.tr, // 对应中文：在所有文件中搜索
                        hintStyle: TextStyle(
                          color: isDarkMode ? Colors.grey[500] : Colors.black54,
                          fontSize: 14.sp,
                        ),
                        isDense: true,
                        focusedBorder: InputBorder.none,
                        fillColor: Colors.transparent,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10.w),
                      ),
                      onSubmitted: (String value) {
                        _controller.scaffoldKey.currentState?.closeDrawer();
                        _homeController.dataList.value =
                            _homeController.originalDataList.where((i) {
                          final titleLower = i['title'].trim().toLowerCase();
                          final queryLower = value.trim().toLowerCase();
                          bool isType = true;
                          if (_homeController.filtrateType.value.isNotEmpty) {
                            isType =
                                _homeController.filtrateType.value == i['type'];
                          }
                          return isType && titleLower.contains(queryLower);
                        }).toList();
                        if (_homeController.isAsc) {
                          _homeController.dataList.value =
                              _homeController.dataList.reversed.toList();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () {
                _filtrateDataList('');
              },
              behavior: HitTestBehavior.translucent,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.w),
                decoration: _homeController.filtrateType.value == ''
                    ? BoxDecoration(
                        color: isDarkMode
                            ? MeetingUIUtils.getTranslucentWhite(0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(12.w),
                        boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
                      )
                    : null,
                child: Row(
                  children: [
                    Icon(
                      Icons.folder,
                      color: Colors.red,
                      size: 20.w,
                    ),
                    6.horizontalSpace,
                    Text(
                      '${'allFiles'.tr}(${_homeController.originalDataList.length})', // 对应中文：全部文件
                      style: TextStyle(
                        color: MeetingUIUtils.getTextColor(isDarkMode),
                        fontSize: 14.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsetsGeometry.symmetric(vertical: 15.w),
              child: Divider(
                height: 1,
                color: isDarkMode ? Colors.grey[800] : Colors.grey[300],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(bottom: 10.w),
              child: Text(
                'from'.tr, // 对应中文：来自
                style: TextStyle(
                  color: isDarkMode ? Colors.grey[500] : Colors.grey,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ...['IMPORT', 'TRANSLAT', 'LOCAL'].map(
              (name) => GestureDetector(
                onTap: () {
                  _filtrateDataList(name);
                },
                behavior: HitTestBehavior.translucent,
                child: Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.w),
                  margin: EdgeInsets.symmetric(vertical: 2.w),
                  decoration: _homeController.filtrateType.value == name
                      ? BoxDecoration(
                          color: isDarkMode
                              ? MeetingUIUtils.getTranslucentWhite(0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12.w),
                          boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
                        )
                      : null,
                  child: Text(
                    name,
                    style: TextStyle(
                      color: MeetingUIUtils.getTextColor(isDarkMode),
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.w),
              child: Text(
                'sortBy'.tr, // 对应中文：排序方式
                style: TextStyle(
                  color: isDarkMode ? Colors.grey[500] : Colors.grey,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                _controller.scaffoldKey.currentState?.closeDrawer();
                _homeController.isAsc = !_homeController.isAsc;
                _homeController.dataList.value =
                    _homeController.dataList.reversed.toList();
              },
              behavior: HitTestBehavior.translucent,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10.w),
                margin: EdgeInsets.symmetric(vertical: 2.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'creationTime'.tr, // 对应中文：创建时间
                      style: TextStyle(
                        color: MeetingUIUtils.getTextColor(isDarkMode),
                        fontSize: 14.sp,
                      ),
                    ),
                    Icon(
                      _homeController.isAsc
                          ? Icons.keyboard_double_arrow_up
                          : Icons.keyboard_double_arrow_down,
                      color: isDarkMode ? Colors.grey[500] : Colors.grey,
                      size: 20.w,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _filtrateDataList(String type) {
    _controller.scaffoldKey.currentState?.closeDrawer();
    _homeController.filtrateType.value = type;
    _homeController.filtrateController.text = '';
    if (type.isNotEmpty) {
      _homeController.dataList.value = _homeController.originalDataList
          .where((i) => i['type'] == type)
          .toList();
    } else {
      _homeController.dataList.value =
          List.from(_homeController.originalDataList);
    }
    if (_homeController.isAsc) {
      _homeController.dataList.value =
          _homeController.dataList.reversed.toList();
    }
  }
}
