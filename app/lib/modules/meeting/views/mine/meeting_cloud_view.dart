import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../../data/services/db/sqflite_api.dart';
import '../../controllers/meeting_controller.dart';
import '../../utils/meeting_ui_utils.dart';

class MeetingCloudView extends StatefulWidget {
  const MeetingCloudView({super.key});

  @override
  State<MeetingCloudView> createState() => _MeetingCloudViewState();
}

class _MeetingCloudViewState extends State<MeetingCloudView> {
  final _controller = Get.put(MeetingController());

  bool _isSync = false;

  @override
  void initState() {
    super.initState();
    _isSync = _controller.user['privatecloud'] == 1;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        int privatecloud = _isSync ? 1 : 0;
        if (privatecloud != _controller.user['privatecloud']) {
          _controller.user['privatecloud'] = privatecloud;
          SqfliteApi.editUser(_controller.user['id'],
              Map<String, Object?>.from(_controller.user));
        }
      },
      child: Scaffold(
        backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
        appBar: _buildAppBar(isDarkMode),
        body: _buildBody(isDarkMode),
      ),
    );
  }

  // 构建应用栏
  PreferredSizeWidget _buildAppBar(bool isDarkMode) {
    return AppBar(
      backgroundColor: MeetingUIUtils.getBackgroundColor(isDarkMode),
      surfaceTintColor: Colors.transparent,
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
        'syncToCloud'.tr, // 对应中文：同步到云端
        style: TextStyle(
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildBody(bool isDarkMode) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.w),
          margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 15.w),
          decoration: BoxDecoration(
            color: MeetingUIUtils.getCardColor(isDarkMode),
            borderRadius: BorderRadius.circular(12.w),
            boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
          ),
          child: Column(
            children: [
              Container(
                width: 60.w,
                height: 60.w,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.w),
                  border: Border.all(
                    color: Colors.grey,
                  ),
                ),
                child: Icon(
                  Icons.phone_android,
                  size: 40.w,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 20.w, bottom: 10.w),
                child: Text(
                  'syncToCloud'.tr, // 对应中文：同步到云端
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                'syncToCloudTip'
                    .tr, // 对应中文：自动将你的录音同步到云端，你可以通过任意VOITRANS APP或VOITRANS Web（web.voitrans.com）播放、管理和分享录音。
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 14.sp,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 2.w),
          margin: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: MeetingUIUtils.getCardColor(isDarkMode),
            borderRadius: BorderRadius.circular(12.w),
            boxShadow: MeetingUIUtils.getCardShadow(isDarkMode),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'syncToVoitransApp'.tr, // 对应中文：同步VOITRANS APP
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 16.sp,
                ),
              ),
              Transform.scale(
                scale: 0.9,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: _isSync,
                  onChanged: (bool value) {
                    setState(() {
                      _isSync = value;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
