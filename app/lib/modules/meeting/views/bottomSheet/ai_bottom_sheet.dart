import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../../../data/services/deapsound_ai_service.dart';
import '../../controllers/meeting_details_controller.dart';

class AIBottomSheet extends StatefulWidget {
  const AIBottomSheet({super.key});

  @override
  State<AIBottomSheet> createState() => _AIBottomSheetState();
}

class _AIBottomSheetState extends State<AIBottomSheet> {
  final _controller = Get.find<MeetingDetailsController>();
  final ScrollController _scrollController = ScrollController();

  final _deapsoundAI = DeapsoundAIService();
  StreamSubscription? _aiResponseSubscription;

  final TextEditingController _textController = TextEditingController();

  String _allText = '';

  List _dataList = [];

  final List _cruxList = [
    'todoList'.tr, //对应中文：代办事项
    'extractConclusion'.tr, //对应中文：提取结论
    'generateKeyIndicators'.tr, //对应中文：生成关键指标
  ];
  final StringBuffer _buffer = StringBuffer();
  bool _isAdd = true;

  bool _isLoading = false;

  // 输入框是否有内容
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _getAllText();
    _getDataList();
    // 监听输入框内容变化
    _textController.addListener(_onTextChanged);
  }

  // 输入框内容变化回调
  void _onTextChanged() {
    final hasText = _textController.text.isNotEmpty;
    if (_hasText != hasText) {
      setState(() {
        _hasText = hasText;
      });
    }
  }

  void _getAllText() {
    for (var element in _controller.textList) {
      if (element['speaker'].isNotEmpty) {
        _allText += '${element['speaker']}:';
      }
      _allText += '${element['content']}\n';
    }
  }

  void _getDataList() async {
    List dataList = await SqfliteApi.getMeetingAiList(
      _controller.meetingData.value.id,
    );
    setState(() {
      _dataList = List.from(dataList);
    });
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _aiResponseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        constraints: BoxConstraints(
          maxHeight: 1.sh - 50.h - MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.symmetric(vertical: 10.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  26.horizontalSpace,
                  Text(
                    'Ask AI',
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
                        color: isDarkMode ? Colors.grey[700] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(26.r),
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18.w,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _dataList.isNotEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: _dataList.length,
                        shrinkWrap: true,
                        reverse: true,
                        itemBuilder: (BuildContext context, int index) {
                          Map data = _dataList[index];
                          return _item(index, data);
                        },
                      ),
                    )
                  : _empty(),
            ),
            _inputBox(),
          ],
        ),
      ),
    );
  }

  Widget _item(int index, Map data) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    List list = [];
    if (index == 0 && data['cruxtext'].isNotEmpty) {
      list = data['cruxtext'].split(RegExp(r'[？?]'));
      list = list.where((element) => element.isNotEmpty).toList();
    }
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(vertical: 10.w),
          alignment: Alignment.centerRight,
          child: Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text(
              data['user'],
              style: TextStyle(
                fontSize: 14.sp,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
        if (data['assistant'].isNotEmpty)
          Container(
            padding: EdgeInsets.symmetric(vertical: 10.w),
            alignment: Alignment.centerLeft,
            child: MarkdownBody(
              data: data['assistant'],
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 14.sp,
                ),
                h1: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.bold,
                ),
                h2: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
                h3: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.bold,
                ),
                listBullet: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 14.sp,
                ),
                code: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  backgroundColor:
                      isDarkMode ? Colors.grey[800] : Colors.grey[200],
                  fontSize: 12.sp,
                ),
              ),
            ),
          ),
        if (list.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 10.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: 5.w),
                  child: Text(
                    'continueAsk'.tr, //对应中文：继续提问
                    style: TextStyle(
                      color: isDarkMode ? Colors.grey[500] : Colors.grey,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ...List.generate(
                  list.length,
                  (int idx) => GestureDetector(
                    onTap: () {
                      _sendMessage('${list[idx]}?');
                    },
                    child: Container(
                      width: double.infinity,
                      padding:
                          EdgeInsets.symmetric(horizontal: 15.w, vertical: 8.w),
                      margin: EdgeInsets.symmetric(vertical: 5.w),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.grey[700]!
                              : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        '${list[idx]}?',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: isDarkMode ? Colors.white : Colors.black87,
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

  Widget _empty() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'askAIPrompt'.tr, //对应中文：今天我能帮您做点什么呢？
            style: TextStyle(
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 10.w, bottom: 30.w),
            child: Row(
              children: [
                Icon(
                  Icons.audio_file_outlined,
                  size: 14.w,
                  color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                ),
                2.horizontalSpace,
                Text(
                  _controller.meetingData.value.title,
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
          ...List.generate(
            _cruxList.length,
            (int index) => GestureDetector(
              onTap: () {
                _sendMessage(_cruxList[index]);
              },
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 8.w),
                margin: EdgeInsets.symmetric(vertical: 5.w),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                child: Text(
                  _cruxList[index],
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBox() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 42.w,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      margin: EdgeInsets.only(bottom: 10.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(42.r),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFFab47bc).withValues(alpha: isDarkMode ? 0.2 : 0.1),
            const Color(0xFFec407a).withValues(alpha: isDarkMode ? 0.3 : 0.2),
          ],
        ),
      ),
      child: Row(
        children: [
          5.horizontalSpace,
          Expanded(
            child: TextField(
              controller: _textController,
              style: TextStyle(
                fontSize: 16.sp,
                color: isDarkMode ? Colors.white : Colors.black87,
                letterSpacing: 0,
                height: 1.4,
              ),
              decoration: InputDecoration(
                hintText: 'askAI'.tr, //对应中文：问 AI ...
                hintStyle: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.grey[400],
                  letterSpacing: 0,
                  height: 1.4,
                ),
                isDense: true,
                fillColor: Colors.transparent,
                focusedBorder: InputBorder.none,
                border: InputBorder.none,
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          10.horizontalSpace,
          GestureDetector(
            onTap: () {
              if (_hasText || _isLoading) {
                _sendMessage(_textController.text);
              }
            },
            child: Container(
              width: 26.w,
              height: 26.w,
              decoration: BoxDecoration(
                color: _isLoading
                    ? Colors.black87
                    : (_hasText ? const Color(0xFF2196F3) : Colors.grey),
                borderRadius: BorderRadius.circular(26.r),
              ),
              child: Icon(
                _isLoading ? Icons.pause : Icons.arrow_upward,
                size: 18.w,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String value) {
    if (_isLoading || value.isEmpty) return;
    _buffer.clear();
    _isAdd = true;
    _textController.clear();
    setState(() {
      _isLoading = true;
      _dataList.insert(0, {
        'user': value,
        'assistant': '',
        'cruxtext': '',
      });
    });
    if (_dataList.length > 1) {
      _scrollController.jumpTo(0);
    }
    final responseStream = _deapsoundAI.sendMessageStream(
      messages: [
        ..._getUserMessage(),
        {'role': 'user', 'content': value},
      ],
    );
    _aiResponseSubscription = responseStream.listen(
      (chunk) {
        _buffer.write(chunk);
        final text = _buffer.toString();
        Map item = _dataList.first;
        if (_isAdd) {
          final index = text.indexOf('@continue_asking@');
          if (index != -1) {
            item['assistant'] = text.substring(0, index);
            _isAdd = false;
          } else {
            item['assistant'] = text;
          }
          setState(() {});
        }
      },
      onDone: () {
        final text = _buffer.toString();
        final index = text.indexOf('@continue_asking@');
        if (index != -1) {
          _dataList.first['cruxtext'] =
              text.substring(index + '@continue_asking@'.length).trim();
        }
        SqfliteApi.insertMeetingAi({
          ..._dataList.first,
          'meetingid': _controller.meetingData.value.id,
        });
        setState(() {
          _isLoading = false;
        });
      },
    );
  }

  List _getUserMessage() {
    List<Map<String, String>> messages = [
      {
        'role': 'system',
        'content': '你只能根据这段对话记录回答问题，禁止引入外部知识。对话内容：$_allText',
      },
      {
        'role': 'system',
        'content':
            '请基于对话上下文生成内容。在回复末尾，添加2-4个简短的、旨在继续对话的问题，并放入@continue_asking@后面。',
      },
    ];
    for (int i = _dataList.length - 1; i >= 0; i--) {
      messages.add({'role': 'user', 'content': _dataList[i]['user']});
    }
    return messages;
  }
}
