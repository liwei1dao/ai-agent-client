import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart' as wav;
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../../../core/services/log_service.dart';

/// Thin wrapper around `package:record` + the waveform recorder.
///
/// We keep TWO recorders because:
/// - `Record` (record package) gives us the actual file at `path` with
///   pause/resume support and configurable codec.
/// - `RecorderController` (audio_waveforms) feeds the live waveform widget.
///
/// They start/stop in lockstep so the user sees the wave that matches the
/// captured file.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  final wav.RecorderController _waveform = wav.RecorderController()
    ..androidEncoder = wav.AndroidEncoder.aac
    ..androidOutputFormat = wav.AndroidOutputFormat.mpeg4
    ..iosEncoder = wav.IosEncoder.kAudioFormatMPEG4AAC
    ..sampleRate = 16000
    ..bitRate = 64000
    ..updateFrequency = const Duration(milliseconds: 100);

  wav.RecorderController get waveform => _waveform;

  Future<bool> ensurePermission() async {
    final st = await Permission.microphone.request();
    return st.isGranted;
  }

  Future<bool> isRecording() => _recorder.isRecording();
  Future<bool> isPaused() => _recorder.isPaused();

  Future<void> start(String path) async {
    if (!await ensurePermission()) {
      throw const _RecorderError('permission_denied', '麦克风权限被拒绝');
    }
    if (await _recorder.isRecording() || await _recorder.isPaused()) {
      // 兜底 — 旧的录音可能没退出干净
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        bitRate: 64000,
        numChannels: 1,
      ),
      path: path,
    );
    try {
      await _waveform.record(path: path);
    } catch (e, st) {
      // waveform 失败不影响主录音 — 仅记日志
      LogService.instance.talker.warning('waveform.record failed: $e\n$st');
    }
  }

  Future<void> pause() async {
    if (await _recorder.isRecording()) {
      await _recorder.pause();
    }
    if (_waveform.isRecording) {
      await _waveform.pause();
    }
  }

  Future<void> resume() async {
    if (await _recorder.isPaused()) {
      await _recorder.resume();
    }
    try {
      await _waveform.record();
    } catch (_) {}
  }

  Future<String?> stop() async {
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    try {
      await _waveform.stop();
    } catch (_) {}
    return path;
  }

  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
    try {
      await _waveform.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _recorder.dispose();
    } catch (_) {}
    try {
      _waveform.dispose();
    } catch (_) {}
  }
}

class _RecorderError implements Exception {
  const _RecorderError(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RecorderError($code, $message)';
}
