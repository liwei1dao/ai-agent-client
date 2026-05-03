import '../../../core/utils/logger.dart';
import '../db/sqflite_api.dart';
import '../network/api.dart';

/// 拉取 `/api/home/echomeet_gettemplates` 并写入本地 sqlite —— 与源项目
/// `SplashController._initMeetingTemplate` 行为对齐。模版列表是会议生成
/// 弹窗的数据源，登录成功 / 冷启动复用 token 时都需要刷新一次。
class MeetingTemplateService {
  MeetingTemplateService._();

  static Future<void> refresh() async {
    try {
      final response = await Api.getEchomeetTemplates();
      if (response is Map && response['templates'] is List) {
        await SqfliteApi.initMeetingTemplate(
          List.from(response['templates'] as List),
        );
        Logger.info(
            'MeetingTemplate refreshed: ${(response['templates'] as List).length} items');
      }
    } catch (e) {
      Logger.error('MeetingTemplate refresh failed: $e');
    }
  }
}
