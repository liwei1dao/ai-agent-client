import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../profile/views/unified_avatar.dart';
import '../../controllers/meeting_mine_controller.dart';
import '../bottomSheet/member_bottom_sheet.dart';

class MeetingMemberView extends StatefulWidget {
  const MeetingMemberView({super.key});

  @override
  State<MeetingMemberView> createState() => _MeetingMemberViewState();
}

class _MeetingMemberViewState extends State<MeetingMemberView> {
  final _controller = Get.put(MeetingMineController());

  int _tabsIndex = 0;
  int _upgradeIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  // 构建应用栏
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      elevation: 0.5,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios,
          color: Colors.white,
          size: 20.sp,
        ),
        onPressed: () => Get.back(),
      ),
      title: Text(
        'voitransAiMember'.tr, // 对应中文：VOITRANS AI会员
        style: TextStyle(
          fontSize: 17.sp,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildBody() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: ListView(
        children: [
          _head(),
          _member(),
          _tabs(),
          _tabsIndex == 0 ? _comparison() : _detailed(),
          _upgrade(),
          _duration(),
        ],
      ),
    );
  }

  Widget _head() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.w),
      child: Row(
        children: [
          Container(
            margin: EdgeInsets.only(right: 10.w),
            child: UnifiedAvatar(
              radius: 25.w,
              backgroundColor: Colors.grey[200],
              iconColor: Colors.grey[600],
              iconSize: 25.r,
              isDarkMode: true,
            ),
          ),
          Expanded(
            child: Obx(
              () => Text(
                _controller.profileCtrl.userInfo.value.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _member() {
    return GestureDetector(
      onTap: () {
        Get.bottomSheet(
          const MemberBottomSheet(),
          isScrollControlled: true,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(12.r),
            ),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 15.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16.w),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Colors.amberAccent,
                  size: 25.sp,
                ),
                5.horizontalSpace,
                Text(
                  'unlockStarterMember'.tr, // 对应中文：解锁 Starter 会员
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.only(top: 15.w),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'bindDeviceToActivate'.tr, // 对应中文：绑定 Voitrans 设备可激活 Starter 会员
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.sp,
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 6.w,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50.w),
                      gradient: const LinearGradient(
                        colors: [Colors.blue, Colors.pink],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    child: Text(
                      'unlockNow'.tr, // 对应中文：立即解锁
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    return Container(
      padding: EdgeInsets.all(2.w),
      margin: EdgeInsets.only(top: 20.w, bottom: 5.w),
      decoration: BoxDecoration(
        color: Colors.grey[700],
        borderRadius: BorderRadius.circular(10.w),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _tabsIndex = 0;
                });
              },
              behavior: HitTestBehavior.translucent,
              child: Container(
                height: 30.w,
                alignment: Alignment.center,
                decoration: _tabsIndex == 0
                    ? BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8.w),
                      )
                    : null,
                child: Text(
                  'comparison'.tr, // 对应中文：对比
                  style: TextStyle(
                    color: _tabsIndex == 0 ? Colors.black : Colors.white,
                    fontSize: 14.sp,
                    fontWeight: _tabsIndex == 0 ? FontWeight.bold : null,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _tabsIndex = 1;
                });
              },
              behavior: HitTestBehavior.translucent,
              child: Container(
                height: 30.w,
                alignment: Alignment.center,
                decoration: _tabsIndex == 1
                    ? BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8.w),
                      )
                    : null,
                child: Text(
                  'detailedInfo'.tr, // 对应中文：详细信息
                  style: TextStyle(
                    color: _tabsIndex == 1 ? Colors.black : Colors.white,
                    fontSize: 14.sp,
                    fontWeight: _tabsIndex == 1 ? FontWeight.bold : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _comparison() {
    return Column(
      children: [
        Container(
          height: 50.w,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey[700]!,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              const Expanded(child: SizedBox.square()),
              Container(
                width: 60.w,
                alignment: Alignment.center,
                child: Text(
                  'Starter',
                  style: TextStyle(
                    color: Colors.grey[200],
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                width: 70.w,
                alignment: Alignment.center,
                child: Container(
                  width: 40.w,
                  height: 24.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.w),
                    gradient: const LinearGradient(
                      colors: [Colors.blue, Colors.pink],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Text(
                    'Pro',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Container(
                width: 72.w,
                alignment: Alignment.center,
                child: Container(
                  width: 72.w,
                  height: 24.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.w),
                    gradient: const LinearGradient(
                      colors: [
                        Colors.amberAccent,
                        Colors.white,
                        Colors.amberAccent
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Text(
                    'Unlimited',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _tableItem(
          'monthlyTranscriptionTime'.tr, // 对应中文：每月转写时长
          starter: '300',
          pro: '1200',
          unlimited: 'unlimited'.tr, // 对应中文：无限
          isGradient: true,
        ),
        _tableItem(
          'professionalTemplates'.tr, // 对应中文：专业模版
          starter: 'limited'.tr, // 对应中文：有限
          pro: 'fullTemplates'.tr, // 对应中文：全量模版
          unlimited: 'fullTemplates'.tr, // 对应中文：全量模版
        ),
        _tableItem(
          'professionalTerms'.tr, // 对应中文：专业术语
          starter: '—',
        ),
        _tableItem(
          'customTemplates'.tr, // 对应中文：自定义模版
          starter: '—',
        ),
        _tableItem(
          'Ask AI',
          starter: '—',
        ),
        _tableItem(
          'visualMindMap'.tr, // 对应中文：可视化思维导图
        ),
        _tableItem(
          'speakerIdentification'.tr, // 对应中文：区分说话人
        ),
        _tableItem(
          'Private Cloud Sync',
        ),
        _tableItem(
          'aiVoiceEnhancement'.tr, // 对应中文：AI 人声增强
        ),
        _tableItem(
          'audioImport'.tr, // 对应中文：音频导入
        ),
        _tableItem(
          'multipleExportFormats'.tr, // 对应中文：支持多种导出格式
        ),
      ],
    );
  }

  Widget _detailed() {
    return Column(
      children: [
        _detailedItem(
          Icons.description,
          Colors.purpleAccent,
          'professionalSummaryTemplates'.tr, // 对应中文：专业总结模版
          'professionalTemplateDesc'.tr, // 对应中文：专业模版设计，提高您的工作效率。根据行业需求量身定制。
        ),
        _detailedItem(
          Icons.edit_note,
          Colors.purpleAccent,
          'customTemplates'.tr, // 对应中文：自定义模版
          'customTemplateDesc'.tr, // 对应中文：您可以根据需求自定义总结 Prompts，并用它们生成所需的总结。
        ),
        _detailedItem(
          Icons.psychology,
          Colors.purpleAccent,
          'Ask AI',
          'askAiDesc'.tr, // 对应中文：从录音中智能挖掘更深入信息，一键生成数据表格、关键讨论结论、To Do、汇报邮件等格式内容。
        ),
        _detailedItem(
          Icons.account_tree,
          Colors.purpleAccent,
          'visualMindMap'.tr, // 对应中文：可视化思维导图
          'visualMindMapDesc'.tr, // 对应中文：超越总结-用思维导图整理和可视化要点，更有效地理解全文。
        ),
        _detailedItem(
          Icons.groups,
          Colors.purpleAccent,
          'templateCommunity'.tr, // 对应中文：模版社区
          'templateCommunityDesc'.tr, // 对应中文：发现、分享，并从用户创建的模版库中获得灵感。
        ),
        _detailedItem(
          Icons.people,
          Colors.red,
          'speakerIdentification'.tr, // 对应中文：区分说话人
          'speakerIdentificationDesc'.tr, // 对应中文：音频转写将支持区分发言者，更直观的还原会议或电话通话内容。同时总结将更加准确。
        ),
        _detailedItem(
          Icons.cloud_sync,
          Colors.red,
          'Private Cloud Sync',
          'privateCloudSyncDesc'.tr, // 对应中文：您的录音和转写等数据将安全存储在专属的云端服务器中，无论是上传还是下载，全程加密处理，确保隐私安全。
        ),
        _detailedItem(
          Icons.graphic_eq,
          Colors.red,
          'aiVoiceEnhancement'.tr, // 对应中文：AI人声增强
          'aiVoiceEnhancementDesc'.tr, // 对应中文：Al 人声增强支持多档降噪设置，智能消除背景噪音，增强语音清晰度，提升音频回放效果。
        ),
        _detailedItem(
          Icons.file_upload,
          Colors.red,
          'audioImport'.tr, // 对应中文：音频导入
          'audioImportDesc'.tr, // 对应中文：可以轻松从本地或第三方应用导入音频文件，如语音备忘录、Google云端硬盘等。
        ),
        _detailedItem(
          Icons.file_download,
          Colors.blue,
          'multipleExportFormats'.tr, // 对应中文：多种导出格式
          'multipleExportFormatsDesc'.tr, // 对应中文：导出您的音频录音、转写文本和摘要为各种格式(TXT、PDF、JPEG），以满足您的需求。
        ),
      ],
    );
  }

  Widget _tableItem(
    String title, {
    String starter = '',
    String pro = '',
    String unlimited = '',
    bool isGradient = false,
  }) {
    return Container(
      height: 50.w,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey[700]!,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: Colors.grey[200],
                fontSize: 12.sp,
              ),
            ),
          ),
          Container(
            width: 60.w,
            alignment: Alignment.center,
            child: starter.isNotEmpty
                ? Text(
                    starter,
                    style: TextStyle(
                      color: Colors.grey[200],
                      fontSize: 12.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : _check(false),
          ),
          Container(
            width: 70.w,
            alignment: Alignment.center,
            child: pro.isNotEmpty
                ? isGradient
                    ? ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.blue, Colors.pink],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ).createShader(bounds),
                        child: Text(
                          pro,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Text(
                        pro,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                : _check(isGradient),
          ),
          Container(
            width: 72.w,
            alignment: Alignment.center,
            child: unlimited.isNotEmpty
                ? ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        Colors.amberAccent,
                        Colors.yellowAccent,
                        Colors.amberAccent,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: Text(
                      unlimited,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : _check(true),
          ),
        ],
      ),
    );
  }

  Widget _detailedItem(
    IconData icon,
    Color color,
    String title,
    String description,
  ) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 10.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            margin: EdgeInsets.only(right: 10.w),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              icon,
              size: 24.w,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 4.w),
                  child: Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _check(bool isGradient) {
    return Container(
      width: 20.w,
      height: 20.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey[400],
        borderRadius: BorderRadius.circular(20.w),
        gradient: isGradient
            ? const LinearGradient(
                colors: [Colors.amberAccent, Colors.white, Colors.amberAccent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
      ),
      child: Icon(
        Icons.check,
        color: Colors.black,
        size: 16.sp,
      ),
    );
  }

  Widget _upgrade() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(top: 30.w),
          alignment: Alignment.center,
          child: Text(
            'upgradeMembership'.tr, // 对应中文：升级您的会员
            style: TextStyle(
              color: Colors.white,
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 15.w),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _upgradeIndex = 0;
                  });
                },
                behavior: HitTestBehavior.translucent,
                child: Container(
                  height: 36.w,
                  padding: EdgeInsets.symmetric(horizontal: 15.w),
                  alignment: Alignment.center,
                  decoration: _upgradeIndex == 0
                      ? BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(36.r),
                        )
                      : null,
                  child: Text(
                    'yearlySubscription'.tr, // 对应中文：年订阅
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _upgradeIndex = 1;
                  });
                },
                behavior: HitTestBehavior.translucent,
                child: Container(
                  height: 36.w,
                  padding: EdgeInsets.symmetric(horizontal: 15.w),
                  alignment: Alignment.center,
                  decoration: _upgradeIndex == 1
                      ? BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(36.r),
                        )
                      : null,
                  child: Text(
                    'monthlySubscription'.tr, // 对应中文：月订阅
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_upgradeIndex == 0)
          _upgradeItem(
            'proMonthly'.tr, // 对应中文：Pro ¥60/月
            'proMonthlyDesc'.tr, // 对应中文：7天免费试用，之后按¥800/年。试用期结束前可随时取消。
            'sevenDayTrial'.tr, // 对应中文：7天免费试用
            onTap: () {},
          ),
        if (_upgradeIndex == 0)
          _upgradeItem(
            'Unlimited ¥120/月',
            '7天免费试用，之后按¥1600/年。试用期结束前可随时取消。',
            '7天免费试用',
            isGolden: true,
            onTap: () {},
          ),
        if (_upgradeIndex == 0)
          Padding(
            padding: EdgeInsets.only(left: 10.w, top: 2.w),
            child: Text(
              '*免费试用7天，然后按年收费，随时取消。',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12.sp,
              ),
            ),
          ),
        if (_upgradeIndex == 1)
          _upgradeItem(
            'Pro ¥120',
            '¥120/月',
            '订阅',
            onTap: () {},
          ),
        if (_upgradeIndex == 1)
          _upgradeItem(
            'Unlimited ¥198',
            '¥198/月',
            '订阅',
            isGolden: true,
            onTap: () {},
          ),
        Padding(
          padding: EdgeInsets.only(left: 10.w, top: 15.w),
          child: Text(
            '*升级订阅后，原订阅的剩余天数会自动折算差价并退还至您的支付账户',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12.sp,
            ),
          ),
        ),
      ],
    );
  }

  Widget _upgradeItem(
    String title,
    String description,
    String btnText, {
    Function()? onTap,
    bool isGolden = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 15.w, vertical: 12.w),
      margin: EdgeInsets.symmetric(vertical: 5.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: Colors.grey[700]!,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 5.w),
                  child: Text(
                    description,
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 100.w,
              padding: EdgeInsets.symmetric(vertical: 8.w),
              margin: EdgeInsets.only(left: 10.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50.w),
                gradient: LinearGradient(
                  colors: isGolden
                      ? [Colors.amberAccent, Colors.white, Colors.amberAccent]
                      : [Colors.blue, Colors.pink],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Text(
                btnText,
                style: TextStyle(
                  color: isGolden ? Colors.black : Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _duration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 20.w, bottom: 10.w),
          child: Text(
            '购买更多转写时长',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Row(
          children: [
            _durationItem(
              '6,000分钟',
              '¥0.1/分钟',
              '¥600.00',
              '¥1200.00',
              onTap: () {},
            ),
            10.horizontalSpace,
            _durationItem(
              '3,000分钟',
              '¥0.11/分钟',
              '¥300.00',
              '¥600.00',
              onTap: () {},
            ),
          ],
        ),
        Row(
          children: [
            _durationItem(
              '600分钟',
              '¥0.114/分钟',
              '¥60.00',
              '¥120.00',
              onTap: () {},
            ),
            10.horizontalSpace,
            _durationItem(
              '120分钟',
              '¥0.184/分钟',
              '¥12.00',
              '¥24.00',
              onTap: () {},
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(left: 10.w, top: 5.w, bottom: 20.w),
          child: Text.rich(
            TextSpan(
              text: '*有效期：',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
              ),
              children: const [
                TextSpan(
                  text: '购买后立即激活，激活后2年内有效。',
                  style: TextStyle(
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _durationItem(
    String title,
    String description,
    String price,
    String originalPrice, {
    Function()? onTap,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.w),
        margin: EdgeInsets.symmetric(vertical: 5.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: Colors.grey[700]!,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14.sp,
              ),
            ),
            Text(
              description,
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12.sp,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        price,
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        originalPrice,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12.sp,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 15.w, vertical: 5.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                    child: Text(
                      '购买',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
