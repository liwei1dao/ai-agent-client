import 'package:get_storage/get_storage.dart';

import '../../../core/services/log_service.dart';
import '../db/sqflite_api.dart';

/// 把本地会议缓存按"当前登录用户 uid"做隔离 —— 切账号 / 登出时清空 sqlite
/// 里的会议表 + GetStorage 里所有以 `meeting_*` / `operation_*` 开头的键，
/// 避免上一个用户的数据泄漏到下一个用户。
class MeetingUserScope {
  MeetingUserScope._();

  static const _lastUidKey = 'meeting.last_login_uid';
  static final GetStorage _storage = GetStorage();

  /// 登录成功后调用 —— 比较已记录的 uid 与新 uid，不同则清本地缓存。
  static Future<void> onLogin(String uid) async {
    final talker = LogService.instance.talker;
    final last = _storage.read<String>(_lastUidKey);
    if (last == uid) {
      talker.info('[MeetingUserScope] same uid=$uid, keep local cache');
      return;
    }
    talker.info(
        '[MeetingUserScope] uid changed: last=$last → new=$uid, wiping cache');
    await _wipe();
    await _storage.write(_lastUidKey, uid);
  }

  /// 登出时调用 —— 清掉本地缓存，并把 last_uid 也清掉，下次登录走"全新"路径。
  static Future<void> onLogout() async {
    LogService.instance.talker.info('[MeetingUserScope] logout, wiping cache');
    await _wipe();
    await _storage.remove(_lastUidKey);
  }

  static Future<void> _wipe() async {
    try {
      await SqfliteApi.clearAllMeetingData();
    } catch (e) {
      LogService.instance.talker
          .error('[MeetingUserScope] clearAllMeetingData failed: $e');
    }
    // GetStorage 里所有会议相关的键
    const meetingKeys = [
      'meeting_upload_list',
      'meeting_pending_local_recording_titles',
      'meeting_last_template_Data',
      'meeting_template_list',
      'operation_records',
      'operation_delids',
    ];
    for (final k in meetingKeys) {
      await _storage.remove(k);
    }
  }
}
