import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/meeting.dart';
import '../services/audio_recorder_service.dart';
import 'meeting_providers.dart';

class RecorderState {
  const RecorderState({
    this.status = RecorderStatus.idle,
    this.elapsedMs = 0,
    this.audioType = MeetingAudioType.live,
    this.title = '',
    this.marked = false,
    this.error,
    this.savedAudioPath,
  });

  final RecorderStatus status;
  final int elapsedMs;
  final MeetingAudioType audioType;
  final String title;
  final bool marked;
  final String? error;
  final String? savedAudioPath;

  bool get isRecording => status == RecorderStatus.recording;
  bool get isPaused => status == RecorderStatus.paused;
  bool get hasStarted =>
      status == RecorderStatus.recording || status == RecorderStatus.paused;

  RecorderState copyWith({
    RecorderStatus? status,
    int? elapsedMs,
    MeetingAudioType? audioType,
    String? title,
    bool? marked,
    Object? error = _sentinel,
    String? savedAudioPath,
  }) =>
      RecorderState(
        status: status ?? this.status,
        elapsedMs: elapsedMs ?? this.elapsedMs,
        audioType: audioType ?? this.audioType,
        title: title ?? this.title,
        marked: marked ?? this.marked,
        error: identical(error, _sentinel) ? this.error : error as String?,
        savedAudioPath: savedAudioPath ?? this.savedAudioPath,
      );
}

const _sentinel = Object();

enum RecorderStatus { idle, recording, paused, stopped }

final recorderServiceProvider = Provider<AudioRecorderService>((ref) {
  final svc = AudioRecorderService();
  ref.onDispose(svc.dispose);
  return svc;
});

final recorderProvider =
    StateNotifierProvider<RecorderNotifier, RecorderState>((ref) {
  return RecorderNotifier(ref);
});

class RecorderNotifier extends StateNotifier<RecorderState> {
  RecorderNotifier(this._ref) : super(RecorderState(title: _defaultTitle()));

  final Ref _ref;
  final _uuid = const Uuid();
  Timer? _ticker;
  String? _meetingId;
  String? _audioPath;

  AudioRecorderService get _svc => _ref.read(recorderServiceProvider);

  static String _defaultTitle() {
    final now = DateTime.now();
    return '会议-${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  void setTitle(String t) => state = state.copyWith(title: t);
  void setAudioType(MeetingAudioType t) =>
      state = state.copyWith(audioType: t);
  void toggleMark() => state = state.copyWith(marked: !state.marked);
  void clearError() => state = state.copyWith(error: null);

  Future<void> start() async {
    if (state.status == RecorderStatus.recording) return;
    try {
      _meetingId ??= _uuid.v4();
      final repo = _ref.read(meetingRepositoryProvider);
      _audioPath ??= await repo.resolveAudioPath(_meetingId!);
      await _svc.start(_audioPath!);
      state = state.copyWith(status: RecorderStatus.recording, error: null);
      _startTicker();
    } catch (e) {
      state = state.copyWith(error: '启动录音失败：$e');
    }
  }

  Future<void> pause() async {
    await _svc.pause();
    _ticker?.cancel();
    state = state.copyWith(status: RecorderStatus.paused);
  }

  Future<void> resume() async {
    await _svc.resume();
    state = state.copyWith(status: RecorderStatus.recording);
    _startTicker();
  }

  Future<void> toggle() async {
    if (state.status == RecorderStatus.idle ||
        state.status == RecorderStatus.stopped) {
      await start();
    } else if (state.isPaused) {
      await resume();
    } else {
      await pause();
    }
  }

  /// 结束并保存为一条会议记录。返回保存好的 [Meeting] 或 null。
  Future<Meeting?> stopAndSave() async {
    final repo = _ref.read(meetingRepositoryProvider);
    final id = _meetingId;
    if (id == null) {
      await _svc.cancel();
      return null;
    }
    final filePath = await _svc.stop();
    final path = filePath ?? _audioPath ?? '';

    final meeting = Meeting(
      id: id,
      title: state.title.trim().isEmpty ? _defaultTitle() : state.title.trim(),
      createdAt: DateTime.now(),
      durationMs: state.elapsedMs,
      audioType: state.audioType,
      audioPath: path,
      marked: state.marked,
    );
    await repo.upsert(meeting);
    state = state.copyWith(
      status: RecorderStatus.stopped,
      savedAudioPath: path,
    );
    _ticker?.cancel();
    // 录音保存后异步触发上传：建服务端记录 → COS 上传 → 绑定 audioUrl。
    // 上传过程不阻塞 UI，失败也只写日志。
    unawaited(_ref
        .read(meetingUploadCoordinatorProvider)
        .uploadInBackground(meeting.id));
    return meeting;
  }

  Future<void> discard() async {
    await _svc.cancel();
    final id = _meetingId;
    final path = _audioPath;
    if (id != null) {
      // 把可能写出来的部分音频清掉
      final repo = _ref.read(meetingRepositoryProvider);
      try {
        await repo.delete(id);
      } catch (_) {}
    }
    if (path != null) {
      try {
        await _ref
            .read(meetingStorageProvider)
            .deleteAudio(path);
      } catch (_) {}
    }
    _ticker?.cancel();
    state = RecorderState(title: _defaultTitle());
    _meetingId = null;
    _audioPath = null;
  }

  void _startTicker() {
    _ticker?.cancel();
    final start = DateTime.now().millisecondsSinceEpoch - state.elapsedMs;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      state = state.copyWith(elapsedMs: now - start);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
