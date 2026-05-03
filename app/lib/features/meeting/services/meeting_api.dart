import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/meeting.dart';
import '../models/meeting_detail.dart';

/// Meeting backend interface — uploads audio, fetches transcription, summary,
/// and mind-map. Default impl is a [MockMeetingApi]; when
/// `MEETING_API_BASE_URL` is set in `.env`, [DioMeetingApi] is used.
abstract class MeetingApi {
  Future<String> uploadAudio({
    required String meetingId,
    required String filePath,
    required String token,
    void Function(int sent, int total)? onProgress,
  });

  Future<MeetingDetail> requestTranscription({
    required Meeting meeting,
    required String token,
  });

  Future<MeetingDetail> requestSummary({
    required Meeting meeting,
    required MeetingDetail detail,
    required String prompt,
    required String token,
  });

  static MeetingApi create() {
    final base = AppConfig.instance.apiBaseUrl;
    return base.isEmpty ? MockMeetingApi() : DioMeetingApi(base);
  }
}

class MockMeetingApi implements MeetingApi {
  @override
  Future<String> uploadAudio({
    required String meetingId,
    required String filePath,
    required String token,
    void Function(int sent, int total)? onProgress,
  }) async {
    final size = File(filePath).lengthSync();
    for (var sent = 0; sent < size; sent += size ~/ 5) {
      await Future.delayed(const Duration(milliseconds: 200));
      onProgress?.call(sent, size);
    }
    onProgress?.call(size, size);
    return 'mock://uploaded/$meetingId';
  }

  @override
  Future<MeetingDetail> requestTranscription({
    required Meeting meeting,
    required String token,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return MeetingDetail(
      meetingId: meeting.id,
      address: '',
      personnel: '',
      summary: '',
      overview: '',
      mindmapHtml: '',
      segments: const [],
    );
  }

  @override
  Future<MeetingDetail> requestSummary({
    required Meeting meeting,
    required MeetingDetail detail,
    required String prompt,
    required String token,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return detail.copyWith(
      summary: '## ${meeting.title}\n\n（mock）AI 摘要正文……',
      overview: '决策 1：…\n决策 2：…\n待办 1：…',
      mindmapHtml:
          '${meeting.title}\n  议题 1\n    要点 A\n    要点 B\n  议题 2\n    结论',
    );
  }
}

class DioMeetingApi implements MeetingApi {
  DioMeetingApi(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 5),
        ));

  final Dio _dio;

  Options _opts(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  @override
  Future<String> uploadAudio({
    required String meetingId,
    required String filePath,
    required String token,
    void Function(int sent, int total)? onProgress,
  }) async {
    final form = FormData.fromMap({
      'meeting_id': meetingId,
      'file': await MultipartFile.fromFile(filePath, filename: 'audio.m4a'),
    });
    final res = await _dio.post('/meetings/$meetingId/upload',
        data: form, options: _opts(token), onSendProgress: onProgress);
    final data = res.data as Map<String, dynamic>;
    return data['url'] as String? ?? '';
  }

  @override
  Future<MeetingDetail> requestTranscription({
    required Meeting meeting,
    required String token,
  }) async {
    final res = await _dio.post('/meetings/${meeting.id}/transcribe',
        options: _opts(token));
    return MeetingDetail.fromJson(_extract(res));
  }

  @override
  Future<MeetingDetail> requestSummary({
    required Meeting meeting,
    required MeetingDetail detail,
    required String prompt,
    required String token,
  }) async {
    final res = await _dio.post(
      '/meetings/${meeting.id}/summary',
      data: {'prompt': prompt},
      options: _opts(token),
    );
    return MeetingDetail.fromJson(_extract(res));
  }

  Map<String, dynamic> _extract(Response res) {
    final data = res.data;
    if (data is Map && data['data'] is Map) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    return Map<String, dynamic>.from(data as Map);
  }
}

/// Helper for screens to grab the current token + a [MeetingApi] in one call.
class MeetingApiContext {
  const MeetingApiContext({required this.api, required this.token});
  final MeetingApi api;
  final String token;
}

extension MeetingApiResolver on AuthState {
  MeetingApiContext? toApiContext() {
    final t = user?.token;
    if (t == null) return null;
    return MeetingApiContext(api: MeetingApi.create(), token: t);
  }
}
