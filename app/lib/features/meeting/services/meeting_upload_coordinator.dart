import 'dart:async';

import '../../../core/services/log_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/meeting_repository.dart';
import 'cos_uploader.dart';
import 'meeting_remote_service.dart';

/// 录音保存后调用 — 串行执行三步：
///
///   1. POST `/api/home/echomeet_addrecord` 拿到 serverId
///   2. 上传音频文件到腾讯 COS
///   3. POST `/api/home/echomeet_uprecord` 把 audioUrl 绑回去
///
/// 期间通过 [progressFor] 暴露每条会议的实时上传进度（0~1）。失败时把
/// 错误写入日志，但不抛给 UI（保证录音永远先存到本地）。
class MeetingUploadCoordinator {
  MeetingUploadCoordinator({
    required this.repo,
    required this.remote,
    required this.cos,
    required this.readAuth,
  });

  final MeetingRepository repo;
  final MeetingRemoteService remote;
  final CosUploader cos;
  final AuthState Function() readAuth;

  final Map<String, double> _progress = {};
  final _changes = StreamController<String>.broadcast();

  /// 监听某条会议的进度变化（id 通过 stream 推送，UI 取最新值）。
  Stream<String> get changes => _changes.stream;
  double progressFor(String id) => _progress[id] ?? 0.0;

  /// 后台异步执行整套流程。重复对同一 id 调用时会幂等：已上传 (audioUrl 非空)
  /// 直接返回；只缺 [serverId] 或只缺音频任意一步会从对应步骤继续。
  Future<void> uploadInBackground(String meetingId) async {
    final auth = readAuth();
    if (!auth.isAuthed) return;
    final token = auth.user!.token;

    var meeting = await repo.getById(meetingId);
    if (meeting == null) return;
    if (meeting.audioUrl.isNotEmpty) return; // 已经上传过

    try {
      _setProgress(meetingId, 0.01);

      // 1. 服务端建记录
      if (meeting.serverId == 0) {
        try {
          final id = await remote.addRecord(
              meeting: meeting, token: token);
          if (id == null) {
            LogService.instance.talker
                .info('meeting upload skipped: api base empty (mock mode)');
            _setProgress(meetingId, 0);
            return;
          }
          meeting = meeting.copyWith(serverId: id);
          await repo.upsert(meeting);
        } catch (e) {
          LogService.instance.talker
              .error('echomeet_addrecord failed: $e');
          _setProgress(meetingId, 0);
          return;
        }
      }

      // 2. 上传 COS
      if (!cos.isReady) {
        LogService.instance.talker
            .warning('COS 未配置（缺少 AppConfig），跳过上传');
        _setProgress(meetingId, 0);
        return;
      }
      late final String audioUrl;
      try {
        audioUrl = await cos.upload(
          filePath: meeting.audioPath,
          rootDir: MeetingRemoteService.cosBucketDir(meeting.audioType),
          userId: auth.user!.id,
          onProgress: (sent, total) {
            if (total > 0) _setProgress(meetingId, sent / total);
          },
        );
      } catch (e) {
        LogService.instance.talker.error('COS upload failed: $e');
        _setProgress(meetingId, 0);
        return;
      }

      // 3. 把 audioUrl 绑回服务端
      try {
        await remote.updateAudioUrl(
          serverId: meeting.serverId,
          audioUrl: audioUrl,
          token: token,
        );
      } catch (e) {
        LogService.instance.talker.error('echomeet_uprecord failed: $e');
        // 即使 uprecord 失败，也保留本地的 audioUrl，方便后续重试
      }

      // 4. 标记本地状态
      await repo.upsert(meeting.copyWith(
        audioUrl: audioUrl,
        uploaded: true,
      ));
      _setProgress(meetingId, 1.0);
    } finally {
      // 完成后给 UI 一次清空机会
      Future<void>.delayed(const Duration(seconds: 1), () {
        _progress.remove(meetingId);
        _changes.add(meetingId);
      });
    }
  }

  /// 重新尝试某条会议的上传（详情页"上传到云端"按钮用）。
  Future<void> retry(String meetingId) => uploadInBackground(meetingId);

  void _setProgress(String id, double v) {
    _progress[id] = v.clamp(0, 1).toDouble();
    if (!_changes.isClosed) _changes.add(id);
  }

  void dispose() {
    _changes.close();
  }
}
