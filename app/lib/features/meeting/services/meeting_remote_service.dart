import 'dart:io';

import '../../../core/services/api_client.dart';
import '../../../core/services/log_service.dart';
import '../models/meeting.dart';

/// 与源项目 `Api.addRecordEchomeet` / `upRecordEchomeet` 一一对应。
/// 走共享的 [ApiClient]（自动签名 + 拆 `data`）。
///
/// `.env` 没配 `API_BASE_URL` 时直接 no-op（mock 模式）。
class MeetingRemoteService {
  /// 在服务端建会议记录，返回服务端分配的 int id。
  Future<int?> addRecord({
    required Meeting meeting,
    required String token,
  }) async {
    final dio = ApiClient.instance.maybeDio();
    if (dio == null) return null;

    final fileSize = meeting.audioPath.isEmpty
        ? 0
        : await _safeFileSize(meeting.audioPath);
    final body = {
      'rtype': _rtypeOf(meeting.audioType),
      'size': fileSize,
      'title': meeting.title,
      'type': _rtypeOf(meeting.audioType),
      'seconds': (meeting.durationMs / 1000).round(),
      'filepath': meeting.audioPath,
      'audiourl': '',
      'tasktype': 0,
      'creationtime': meeting.createdAt.millisecondsSinceEpoch,
      'localid': meeting.id,
    };
    final res = await dio.post('/api/home/echomeet_addrecord', data: body);
    final root = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
    // 后端返回结构：{ record: { id, ... } } 或直接 { id }
    final record = root['record'] is Map
        ? Map<String, dynamic>.from(root['record'] as Map)
        : root;
    final id = record['id'];
    LogService.instance.talker
        .info('[meeting] echomeet_addrecord => id=$id');
    if (id is num) return id.toInt();
    if (id is String) return int.tryParse(id);
    return null;
  }

  /// 绑定上传成功的 audioUrl 到会议记录。
  Future<void> updateAudioUrl({
    required int serverId,
    required String audioUrl,
    required String token,
  }) async {
    final dio = ApiClient.instance.maybeDio();
    if (dio == null) return;
    await dio.post('/api/home/echomeet_uprecord', data: {
      'id': serverId,
      'audiourl': audioUrl,
    });
    LogService.instance.talker
        .info('[meeting] echomeet_uprecord id=$serverId ok');
  }

  /// 启动后端转写 / 摘要任务。
  Future<void> startTask({
    required int serverId,
    required String token,
    String fromLanguage = '',
    String toLanguage = '',
    bool distinguishSpeaker = true,
    int templateId = 0,
  }) async {
    final dio = ApiClient.instance.maybeDio();
    if (dio == null) return;
    await dio.post('/api/home/echomeet_starttask', data: {
      'id': serverId,
      'formlanguage': fromLanguage,
      'tolanguage': toLanguage,
      'isdistinguishspeaker': distinguishSpeaker,
      'templateid': templateId,
    });
  }

  Future<int> _safeFileSize(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  /// 与源项目对齐：录音类型代码字符串。
  static String _rtypeOf(MeetingAudioType t) => switch (t) {
        MeetingAudioType.live => 'LOCAL',
        MeetingAudioType.audioVideo => 'EXTERNAL',
        MeetingAudioType.call => 'CALL',
      };

  /// COS 上传时的 rootDir：与源项目一致，本地录音用 `LocalAudio`，
  /// 外部导入用 `ExternalAudio`。
  static String cosBucketDir(MeetingAudioType t) => switch (t) {
        MeetingAudioType.live => 'LocalAudio',
        MeetingAudioType.audioVideo => 'ExternalAudio',
        MeetingAudioType.call => 'CallAudio',
      };
}
