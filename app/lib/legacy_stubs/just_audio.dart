/// Stub of `just_audio` for the legacy meeting module port.
///
/// 仅替换 `addMeetingAudio` 这种"读一下时长就行"的场景：`setAudioSource`
/// 收到本地 WAV 时，从 RIFF 头里 (`byteRate` + `data chunk size`) 算秒数，
/// 让 home 控制器扫到本地录音能正常入库。其他场景仍然是空实现。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

Duration? _readWavDuration(String filePath) {
  try {
    if (!filePath.toLowerCase().endsWith('.wav')) return null;
    final f = File(filePath);
    if (!f.existsSync()) return null;
    final raf = f.openSync();
    try {
      final header = raf.readSync(64);
      if (header.lengthInBytes < 44) return null;
      final bd = ByteData.sublistView(Uint8List.fromList(header));
      // RIFF / WAVE / fmt 校验
      if (bd.getUint32(0, Endian.little) != 0x46464952) return null; // "RIFF"
      if (bd.getUint32(8, Endian.little) != 0x45564157) return null; // "WAVE"
      final byteRate = bd.getUint32(28, Endian.little);
      if (byteRate == 0) return null;
      // data chunk 大小一般在 40，但如果 fmt chunk 不是 16 字节就要扫
      int dataSize = bd.getUint32(40, Endian.little);
      if (bd.getUint32(36, Endian.little) != 0x61746164) {
        // 不是 "data"，回退到文件总长 - 44 估算
        dataSize = f.lengthSync() - 44;
      }
      final ms = dataSize * 1000 ~/ byteRate;
      return Duration(milliseconds: ms);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return null;
  }
}

class AudioPlayer {
  AudioPlayer();

  final _stateController = StreamController<PlayerState>.broadcast();
  final _positionController = StreamController<Duration>.broadcast();
  final _durationController = StreamController<Duration?>.broadcast();
  final _processingStateController =
      StreamController<ProcessingState>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _bufferedPositionController = StreamController<Duration>.broadcast();

  Duration? duration;
  Duration position = Duration.zero;
  Duration bufferedPosition = Duration.zero;
  bool playing = false;
  ProcessingState processingState = ProcessingState.idle;
  double speed = 1.0;
  double volume = 1.0;

  Stream<PlayerState> get playerStateStream => _stateController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<ProcessingState> get processingStateStream =>
      _processingStateController.stream;
  Stream<bool> get playingStream => _playingController.stream;
  Stream<Duration> get bufferedPositionStream =>
      _bufferedPositionController.stream;

  Future<void> play() async {}
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> seek(Duration? position) async {}
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }

  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  Future<Duration?> setUrl(String url) async => null;
  Future<Duration?> setFilePath(String path) async {
    final d = _readWavDuration(path);
    if (d != null) duration = d;
    return d;
  }

  Future<Duration?> setAudioSource(AudioSource source) async {
    final p = source._filePath;
    if (p == null) return null;
    final d = _readWavDuration(p);
    if (d != null) duration = d;
    return d;
  }

  Future<void> dispose() async {
    await _stateController.close();
    await _positionController.close();
    await _durationController.close();
    await _processingStateController.close();
    await _playingController.close();
    await _bufferedPositionController.close();
  }
}

class PlayerState {
  final bool playing;
  final ProcessingState processingState;
  PlayerState(this.playing, this.processingState);
}

enum ProcessingState { idle, loading, buffering, ready, completed }

class AudioSource {
  AudioSource._({String? filePath}) : _filePath = filePath;
  final String? _filePath;

  static AudioSource uri(Uri uri, {dynamic tag}) =>
      AudioSource._(filePath: uri.scheme == 'file' ? uri.toFilePath() : null);
  static AudioSource file(String filePath, {dynamic tag}) =>
      AudioSource._(filePath: filePath);
}
