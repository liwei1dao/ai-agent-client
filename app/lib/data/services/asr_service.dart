import 'dart:async';
import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:record/record.dart';

/// 真正落地的 ASR 服务实现：用 `record` 包录音到 WAV 文件，并通过订阅
/// `onAmplitudeChanged` 把振幅转成假的 16-bit PCM 帧，喂给
/// `MeetingRecordController` 让它的波形显示正常更新。
///
/// 不做语音识别（无原生 ASR 引擎接入），controller 内部期望的"音频流"语义
/// 在我们这边只用来做实时振幅可视化。
enum AudioSourceType {
  microphone,
  systemAudio,
  systemAudioPlusMicrophone,
  external,
}

class AsrService extends GetxService {
  static AsrService get to => Get.find();

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  StreamController<Uint8List>? _audioStream;
  int _sampleRate = 16000;
  int _channels = 1;
  bool _paused = false;

  Future<void> enableRecord([
    AudioSourceType audioSourceType = AudioSourceType.microphone,
    String? filePath,
    bool acceptAudioData = false,
  ]) async {
    if (filePath == null || filePath.isEmpty) return;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) return;

    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: _sampleRate,
        numChannels: _channels,
      ),
      path: filePath,
    );

    if (acceptAudioData) {
      _audioStream?.close();
      _audioStream = StreamController<Uint8List>.broadcast();
      _ampSub?.cancel();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amp) {
        if (_paused) return;
        // amp.current 单位 dBFS，范围 ~ -160..0；先转成线性 0..1 振幅。
        final db = amp.current.isFinite ? amp.current : -160.0;
        final linear =
            ((db + 60.0) / 60.0).clamp(0.0, 1.0).toDouble(); // -60..0 → 0..1
        // 构造一个伪 16-bit PCM 缓冲，让 _calculateAmplitude 的 RMS 计算
        // 复原出与 linear 等价的振幅。
        final sample = (linear * 32767).round();
        final lo = sample & 0xFF;
        final hi = (sample >> 8) & 0xFF;
        final buf = Uint8List(64);
        for (var i = 0; i < buf.length; i += 2) {
          buf[i] = lo;
          buf[i + 1] = hi;
        }
        _audioStream?.add(buf);
      });
    }
    _paused = false;
  }

  Future<void> pauseRecord() async {
    _paused = true;
    if (await _recorder.isRecording()) {
      try {
        await _recorder.pause();
      } catch (_) {}
    }
  }

  Future<void> resumeRecord() async {
    _paused = false;
    if (await _recorder.isPaused()) {
      try {
        await _recorder.resume();
      } catch (_) {}
    }
  }

  Future<bool> stopRecord([bool flush = false]) async {
    try {
      await _recorder.stop();
    } catch (_) {}
    await _ampSub?.cancel();
    _ampSub = null;
    await _audioStream?.close();
    _audioStream = null;
    _paused = false;
    return true;
  }

  void setAudioConfig({int sampleRate = 16000, int channels = 1}) {
    _sampleRate = sampleRate;
    _channels = channels;
  }

  Stream<Uint8List>? getAudioDataStream() => _audioStream?.stream;

  @override
  void onClose() {
    _ampSub?.cancel();
    _audioStream?.close();
    _recorder.dispose();
    super.onClose();
  }
}
