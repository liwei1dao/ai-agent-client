import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../controllers/meeting_details_controller.dart';
import 'template_all_view.dart';
import 'template_details_view.dart';
import 'template_edit_view.dart';

class TemplateView extends StatefulWidget {
  final Map templateData;
  final int lastTemplateId;

  const TemplateView(this.templateData, this.lastTemplateId, {super.key});

  @override
  State<TemplateView> createState() => _TemplateViewState();
}

class _TemplateViewState extends State<TemplateView> {
  final _controller = Get.find<MeetingDetailsController>();

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

  List _categoryTemplateList = [];
  Map _templateData = {};

  @override
  void initState() {
    super.initState();
    _getTemplate();
  }

  void _getTemplate() {
    _categoryTemplateList = [];
    for (var element in _controller.categoryTemplateList) {
      List templateList = [];
      bool isAdd = false;
      if (element['id'] == widget.templateData['categoryid']) {
        isAdd = true;
      }
      for (var template in element['template']) {
        if (template['id'] == widget.templateData['id']) {
          isAdd = false;
          templateList.insert(0, template);
        } else {
          templateList.add(template);
        }
      }
      if (isAdd) {
        templateList.insert(0, widget.templateData);
      }
      _categoryTemplateList.add({
        'id': element['id'],
        'name': element['name'],
        'template': templateList,
      });
    }
    setState(() {
      _templateData = widget.templateData;
    });
  }

  void _returnCallback() {
    if (_controller.editTemplate.isNotEmpty) {
      _getTemplate();
      if (_controller.editTemplate['id'] == _templateData['id']) {
        _templateData['name'] = _controller.editTemplate['name'];
        _templateData['desc'] = _controller.editTemplate['desc'];
        _templateData['prompt'] = _controller.editTemplate['prompt'];
      }
    }
    if (_controller.deleteTemplateId != 0) {
      _getTemplate();
      if (_controller.deleteTemplateId == _templateData['id']) {
        _templateData = {};
      }
      _categoryTemplateList.last['template'].removeWhere(
          (element) => element['id'] == _controller.deleteTemplateId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.grey[50],
      appBar: _buildAppBar(isDarkMode),
      body: SafeArea(
        top: false,
        child: _buildBody(isDarkMode),
      ),
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
        'selectSummaryTemplate'.tr, // 对应中文：选择总结模版
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
          child: ListView.builder(
            itemCount: _categoryTemplateList.length,
            itemBuilder: (BuildContext context, int index) {
              Map data = _categoryTemplateList[index];
              return _item(data, index == _categoryTemplateList.length - 1);
            },
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.w),
          child: GestureDetector(
            onTap: () {
              if (_templateData.isNotEmpty) {
                Get.back(result: _templateData);
              }
            },
            child: Container(
              height: 48.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _templateData.isNotEmpty ? Colors.black : Colors.grey,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                'useThisTemplate'.tr, // 对应中文：就用这个模版
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _item(Map data, bool isLast) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () async {
            await Get.to(() => TemplateAllView(
                  data['name'],
                  data['id'],
                  _templateData,
                  widget.lastTemplateId,
                ));
            _returnCallback();
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.w),
            child: Row(
              children: [
                Text(
                  data['name'],
                  style: TextStyle(
                    fontSize: 18.sp,
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_right,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey,
                )
              ],
            ),
          ),
        ),
        Container(
          height: 150.w,
          margin: EdgeInsets.only(bottom: 15.w),
          child: isLast && data['template'].length == 0
              ? Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: _createTemplate(data['id']),
                )
              : ListView.builder(
                  itemCount: data['template'].length,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  itemBuilder: (BuildContext context, int index) {
                    Map template = data['template'][index];
                    return isLast && index == 0
                        ? Row(
                            children: [
                              _createTemplate(data['id']),
                              _template(template, true),
                            ],
                          )
                        : _template(template, false);
                  },
                ),
        ),
      ],
    );
  }

  Widget _template(Map template, bool isEdit) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 200.w,
      margin: EdgeInsets.symmetric(horizontal: 4.w),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14.w),
      ),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _templateData = template;
          });
        },
        child: Stack(
          children: [
            Container(
              padding: EdgeInsets.all(5.w),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
                gradient: _templateData['id'] == template['id']
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
                        _icons[template['icon']],
                        color: Colors.orange,
                        size: 30.w,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.w),
                      child: SizedBox(
                        height: 22.w,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            template['name'],
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
                    template['tag'].isNotEmpty
                        ? Wrap(
                            spacing: 5.w,
                            children: List.generate(
                              template['tag'].length,
                              (int idx) {
                                return Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 5.w, vertical: 2.w),
                                  decoration: BoxDecoration(
                                    color: isDarkMode
                                        ? Colors.grey[700]
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                  child: Text(
                                    template['tag'][idx],
                                    style: TextStyle(
                                      fontSize: 10.sp,
                                      color: isDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : Text(
                            template['desc'],
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
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () async {
                  await Get.to(
                      () => TemplateDetailsView(template, isEdit: isEdit));
                  _returnCallback();
                },
                child: Padding(
                  padding: EdgeInsets.all(10.w),
                  child: Icon(
                    Icons.fullscreen,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    size: 26.w,
                  ),
                ),
              ),
            ),
            if (widget.lastTemplateId == template['id'])
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
            if (_templateData['id'] == template['id'])
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

  Widget _createTemplate(int categoryid) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () async {
        await Get.to(() => TemplateEditView(categoryid: categoryid));
        if (_controller.editTemplate.isNotEmpty) {
          _getTemplate();
        }
      },
      child: Container(
        width: 200.w,
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.w),
        ),
        child: Container(
          color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 5.w),
                child: Icon(
                  Icons.add_circle_outlined,
                  color: Colors.orange,
                  size: 30.w,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.w),
                child: Text(
                  'create'.tr, // 创建
                  style: TextStyle(
                    fontSize: 16.sp,
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
