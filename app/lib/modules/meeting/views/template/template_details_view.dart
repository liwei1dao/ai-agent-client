import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../../../data/services/network/api.dart';
import '../../controllers/meeting_details_controller.dart';
import 'template_edit_view.dart';

class TemplateDetailsView extends StatefulWidget {
  final Map data;
  final bool isEdit;

  const TemplateDetailsView(this.data, {super.key, this.isEdit = false});

  @override
  State<TemplateDetailsView> createState() => _TemplateDetailsViewState();
}

class _TemplateDetailsViewState extends State<TemplateDetailsView> {
  final _controller = Get.find<MeetingDetailsController>();

  Map _templateData = {};

  @override
  void initState() {
    super.initState();
    _templateData = widget.data;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.grey[50],
      appBar: _buildAppBar(isDarkMode),
      body: _buildBody(isDarkMode),
    );
  }

  // 构建应用栏
  PreferredSizeWidget _buildAppBar(bool isDarkMode) {
    return AppBar(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: isDarkMode ? Colors.white : Colors.black,
          size: 20.sp,
        ),
        onPressed: () => Get.back(),
      ),
      title: Text(
        'templateDetails'.tr, // 模版详情
        style: TextStyle(
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      centerTitle: true,
    );
  }

  // 构建主体内容
  Widget _buildBody(bool isDarkMode) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            children: [
              Padding(
                padding: EdgeInsets.only(top: 20.w),
                child: Text(
                  _templateData['name'],
                  style: TextStyle(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 20.w, bottom: 5.w),
                child: Text(
                  'tag'.tr, // 标签
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              Wrap(
                spacing: 5.w,
                children: List.generate(
                  _templateData['tag'].length,
                  (int idx) {
                    return Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.w),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        _templateData['tag'][idx],
                        style: TextStyle(
                          fontSize: 10.sp,
                          color:
                              isDarkMode ? Colors.grey[300] : Colors.grey[600],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 20.w, bottom: 5.w),
                child: Text(
                  'description'.tr, // 描述
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              Text(
                _templateData['desc'],
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 20.w, bottom: 5.w),
                child: Text(
                  'template'.tr, // 模版
                  style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              MarkdownBody(
                data: _templateData['prompt'],
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: isDarkMode ? Colors.grey[300] : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.isEdit)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.w),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      var result = await Get.to(
                          () => TemplateEditView(data: _templateData));
                      if (result != null) {
                        setState(() {
                          _templateData['name'] = result['name'];
                          _templateData['desc'] = result['desc'];
                          _templateData['prompt'] = result['prompt'];
                        });
                      }
                    },
                    child: Container(
                      height: 48.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      child: Text(
                        'edit'.tr, // 编辑
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                15.horizontalSpace,
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Get.dialog(
                        AlertDialog(
                          backgroundColor:
                              isDarkMode ? Colors.grey[900] : Colors.white,
                          title: Text(
                            'deleteTemplate'.tr, // 删除模版
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                          content: Text(
                            'deleteTemplateConfirm'.tr, // 确定要删除当前模版吗？
                            style: TextStyle(
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Get.back(),
                              child: Text(
                                'cancel'.tr,
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                Get.back();
                                var response = await Api.delEchomeetTemplates({
                                  'ids': [_templateData['id']],
                                });
                                if (response != null) {
                                  await SqfliteApi.deleteMeetingTemplate(
                                      _templateData['id']);
                                  _controller.categoryTemplateList =
                                      await SqfliteApi
                                          .getMeetingCategoryTemplateList();
                                  _controller.deleteTemplateId =
                                      _templateData['id'];
                                  Get.back();
                                }
                              },
                              child: Text(
                                'confirm'.tr,
                                style: const TextStyle(
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      height: 48.w,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        'delete'.tr, // 删除
                        style: TextStyle(
                          fontSize: 16.sp,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
