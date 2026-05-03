import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../../../data/services/deapsound_ai_service.dart';
import '../../../../data/services/network/api.dart';
import '../../controllers/meeting_details_controller.dart';

class TemplateEditView extends StatefulWidget {
  final Map? data;
  final int? categoryid;

  const TemplateEditView({super.key, this.data, this.categoryid});

  @override
  State<TemplateEditView> createState() => _TemplateEditViewState();
}

class _TemplateEditViewState extends State<TemplateEditView> {
  final _controller = Get.find<MeetingDetailsController>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();

  bool _isEnable = false;

  final _deapsoundAI = DeapsoundAIService();
  StreamSubscription? _aiResponseSubscription;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _nameController.text = widget.data?['name'];
      _descController.text = widget.data?['desc'];
      _promptController.text = widget.data?['prompt'];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _promptController.dispose();
    _aiResponseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: isDarkMode ? Colors.black : Colors.grey[50],
        appBar: _buildAppBar(isDarkMode),
        body: _buildBody(isDarkMode),
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
        widget.data != null
            ? 'editTemplate'.tr
            : 'createTemplate'.tr, // 编辑模版/创建模版
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
              _input(isDarkMode, 'name'.tr, _nameController), // 名称
              _input(isDarkMode, 'description'.tr, _descController), // 描述
              _input(
                isDarkMode,
                'template'.tr, // 模版
                _promptController,
                minLines: 8,
                maxLines: 100,
                hintText: 'templateContentHint'
                    .tr, // 请输入模版内容！温馨提示：点击上方AI，根据上面填写的名称和描述，可以帮助你快速生成模版内容
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.w),
          child: GestureDetector(
            onTap: () {
              if (_nameController.text.isNotEmpty &&
                  _descController.text.isNotEmpty &&
                  _promptController.text.isNotEmpty) {
                _submit();
              }
            },
            child: Container(
              height: 48.w,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _nameController.text.isNotEmpty &&
                        _descController.text.isNotEmpty &&
                        _promptController.text.isNotEmpty
                    ? (isDarkMode ? Colors.white : Colors.black)
                    : Colors.grey,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Text(
                'submit'.tr, // 提交
                style: TextStyle(
                  fontSize: 16.sp,
                  color: _nameController.text.isNotEmpty &&
                          _descController.text.isNotEmpty &&
                          _promptController.text.isNotEmpty
                      ? (isDarkMode ? Colors.black : Colors.white)
                      : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _input(
    bool isDarkMode,
    String title,
    TextEditingController controller, {
    int minLines = 1,
    int maxLines = 1,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 10.w),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
            if (maxLines > 1)
              GestureDetector(
                onTap: () {
                  _generateTemplatePrompt();
                },
                child: Container(
                  width: 26.w,
                  height: 26.w,
                  margin: EdgeInsets.only(right: 10.w),
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? const Color(0xFF4C3F91)
                        : const Color(0xFF6A5AE0),
                    borderRadius: BorderRadius.circular(26.r),
                  ),
                  child: Icon(
                    _isLoading ? Icons.pause : Icons.smart_toy,
                    size: 18.w,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        Container(
          margin: EdgeInsets.only(top: 10.w, bottom: 20.w),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF2D2D2D) : Colors.white,
            borderRadius: BorderRadius.circular(12.w),
            boxShadow: isDarkMode
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: TextField(
            controller: controller,
            minLines: minLines,
            maxLines: maxLines,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontSize: 14.sp,
            ),
            decoration: InputDecoration(
              hintText: hintText ?? '${'pleaseEnter'.tr}$title', // 请输入
              hintStyle: TextStyle(
                color: isDarkMode ? Colors.grey[500] : Colors.black54,
                fontSize: 14.sp,
              ),
              isDense: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(10.w),
            ),
            onChanged: (value) {
              bool isEnable = false;
              if (_nameController.text.isNotEmpty &&
                  _descController.text.isNotEmpty &&
                  _promptController.text.isNotEmpty) {
                isEnable = true;
              }
              if (_isEnable != isEnable) {
                setState(() {
                  _isEnable = isEnable;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  void _submit() async {
    EasyLoading.show();
    Map data = {
      "template": <String, Object?>{
        'ttype': '自定义',
        'tags': '',
        'icon': 'auto_fix_high',
        'outline': '您将扮演一名会议事件归纳专家，能准确抓住会议中事件的关键点，并每个事件只需一句话精简总结。',
        'title': _nameController.text,
        'description': _descController.text,
        'template': _promptController.text,
      },
    };
    if (widget.data != null) {
      data['template']['id'] = widget.data?['id'];
      var response = await Api.updateEchomeetTemplates(data);
      if (response != null) {
        await SqfliteApi.editMeetingTemplate(widget.data?['id'], {
          'name': _nameController.text,
          'desc': _descController.text,
          'prompt': _promptController.text,
        });
        _controller.editTemplate = {
          'id': widget.data?['id'],
          'name': _nameController.text,
          'desc': _descController.text,
          'prompt': _promptController.text,
        };
        final GetStorage storage = GetStorage();
        Map lastTemplateData = storage.read("meeting_last_template_Data") ?? {};
        List originalTemplate = storage.read("meeting_template_list") ?? [];
        if (lastTemplateData.isNotEmpty &&
            lastTemplateData['id'] == widget.data?['id']) {
          lastTemplateData['name'] = _nameController.text;
          lastTemplateData['desc'] = _descController.text;
          lastTemplateData['prompt'] = _promptController.text;
          storage.write("meeting_last_template_Data", lastTemplateData);
        }
        if (originalTemplate.isNotEmpty) {
          Map? originalMap = originalTemplate.firstWhere(
              (element) => element['id'] == widget.data?['id'],
              orElse: () => null);
          if (originalMap != null) {
            originalMap['name'] = _nameController.text;
            originalMap['desc'] = _descController.text;
            originalMap['prompt'] = _promptController.text;
            storage.write("meeting_template_list", originalTemplate);
          }
        }
      }
    } else {
      var response = await Api.addEchomeetTemplates(data);
      if (response != null) {
        await SqfliteApi.insertMeetingTemplate({
          "id": response['template']['id'],
          'categoryid': widget.categoryid,
          'name': _nameController.text,
          'icon': 'auto_fix_high',
          'tag': '',
          'desc': _descController.text,
          'outline': '您将扮演一名会议事件归纳专家，能准确抓住会议中事件的关键点，并每个事件只需一句话精简总结。',
          'prompt': _promptController.text,
        });
        _controller.editTemplate = {
          'id': response['template']['id'],
          'name': _nameController.text,
          'desc': _descController.text,
          'prompt': _promptController.text,
        };
      }
    }
    _controller.categoryTemplateList =
        await SqfliteApi.getMeetingCategoryTemplateList();
    Get.back(result: {
      'name': _nameController.text,
      'desc': _descController.text,
      'prompt': _promptController.text,
    });
    EasyLoading.dismiss();
  }

  void _generateTemplatePrompt() {
    if (_isLoading ||
        _nameController.text.isEmpty ||
        _descController.text.isEmpty) {
      return;
    }
    _promptController.clear();
    setState(() {
      _isLoading = true;
    });
    final responseStream = _deapsoundAI.sendMessageStream(
      messages: [
        {'role': 'system', 'content': '名称：${_nameController.text}'},
        {'role': 'system', 'content': '描述：${_descController.text}'},
        {
          'role': 'user',
          'content':
              '请基于以上名称与描述，生成一个高质量会议总结提示词（Prompt），用于指导模型对会议记录进行结构化总结。只返回提示词文本，不要提供示例或额外解释。',
        },
      ],
    );
    _aiResponseSubscription = responseStream.listen(
      (chunk) {
        _promptController.text += chunk;
      },
      onDone: () {
        setState(() {
          _isLoading = false;
        });
      },
    );
  }
}
