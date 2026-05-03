import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

class SecondLevelBottomSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final Function(int index) onTap;
  final List children;

  const SecondLevelBottomSheet(
      this.title, this.subtitle, this.onTap, this.children,
      {super.key});

  @override
  State<SecondLevelBottomSheet> createState() => _SecondLevelBottomSheetState();
}

class _SecondLevelBottomSheetState extends State<SecondLevelBottomSheet> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
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
            Padding(
              padding: EdgeInsetsGeometry.only(
                top: 20.w,
                bottom: 10.w,
                left: 12.w,
              ),
              child: Text(
                widget.subtitle,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey[600],
                ),
              ),
            ),
            Container(
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Column(
                children: List.generate(widget.children.length, (int index) {
                  Map item = widget.children[index];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 12.w, vertical: 14.w),
                      decoration: BoxDecoration(
                        border: item['isBorder']
                            ? Border(
                                bottom: BorderSide(
                                  width: 0.5,
                                  color: isDarkMode
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            item['icon'],
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                          10.horizontalSpace,
                          Expanded(
                            child: Text(
                              item['title'],
                              style: TextStyle(
                                fontSize: 14.sp,
                                color:
                                    isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (_selectedIndex == index)
                            Icon(
                              Icons.check,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 20.w),
              child: GestureDetector(
                onTap: () {
                  Get.back();
                  widget.onTap(_selectedIndex);
                },
                child: Container(
                  height: 48.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white : Colors.black,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    'export'.tr, // 对应中文：导出
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
}
