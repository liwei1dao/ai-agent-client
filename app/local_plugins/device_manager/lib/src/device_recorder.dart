import 'dart:async';
import 'dart:typed_data';

import 'package:device_plugin_interface/device_plugin_interface.dart';

/// 录音通道 ID。与 native [JieliDeviceRecordPort] / `DeviceRecordFeature`
/// 保持一致，跨厂商通用：
/// - [inUplink]   — 本端/耳机麦克风（user 侧）
/// - [inDownlink] — 对端/通话对方（peer 侧）
class DeviceRecordStreams {
  static const String inUplink = 'in.uplink';
  static const String inDownlink = 'in.downlink';
}

/// 单帧录音 PCM。
class DeviceRecordFrame {
  const DeviceRecordFrame({
    required this.streamId,
    required this.pcm,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.tsMs,
  });

  /// [DeviceRecordStreams.inUplink] 或 [DeviceRecordStreams.inDownlink]。
  final String streamId;

  /// 16bit signed PCM（小端，interleaved when channels>1）。
  final Uint8List pcm;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int tsMs;

  static DeviceRecordFrame? tryFromFeature(DeviceFeatureEvent feat) {
    if (feat.key != _kAudioKey) return null;
    final pcm = feat.data['pcm'];
    final streamId = feat.data['streamId'] as String?;
    if (pcm is! Uint8List || streamId == null) return null;
    return DeviceRecordFrame(
      streamId: streamId,
      pcm: pcm,
      sampleRate: (feat.data['sampleRate'] as num?)?.toInt() ?? 16000,
      channels: (feat.data['channels'] as num?)?.toInt() ?? 1,
      bitsPerSample: (feat.data['bitsPerSample'] as num?)?.toInt() ?? 16,
      tsMs: (feat.data['tsMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 录音状态变更（启动 / 停止）。
enum DeviceRecordPhase { started, stopped }

class DeviceRecordStateEvent {
  const DeviceRecordStateEvent({
    required this.phase,
    required this.tsMs,
    this.sampleRate,
  });

  final DeviceRecordPhase phase;

  /// 仅 [DeviceRecordPhase.started] 时携带。
  final int? sampleRate;
  final int tsMs;

  static DeviceRecordStateEvent? tryFromFeature(DeviceFeatureEvent feat) {
    final phase = switch (feat.key) {
      _kStartKey => DeviceRecordPhase.started,
      _kStopKey => DeviceRecordPhase.stopped,
      _ => null,
    };
    if (phase == null) return null;
    return DeviceRecordStateEvent(
      phase: phase,
      sampleRate: (feat.data['sampleRate'] as num?)?.toInt(),
      tsMs: (feat.data['tsMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 设备录音的厂商无关 facade。
///
/// 包装 [DeviceSession.invokeFeature] + [DeviceSession.eventStream] 上的
/// `jieli.deviceRecord.*` feature key（厂商插件内部把私有事件桥接到这套通用
/// key，业务侧不需要写 vendor 分支）。
///
/// # 用法
/// ```dart
/// final rec = DeviceRecorder(session);
/// final sub = rec.audioFrames.listen((frame) {
///   // frame.streamId == DeviceRecordStreams.inUplink   → 本端
///   // frame.streamId == DeviceRecordStreams.inDownlink → 对端
///   appendToFile(frame.streamId, frame.pcm);
/// });
/// await rec.start(sampleRate: 16000);
/// // ...
/// await rec.stop();
/// await sub.cancel();
/// rec.dispose();
/// ```
///
/// 与 [DeviceCallTranslationPort] / 本端"通话翻译"模式互斥；厂商插件保证
/// 启动录音前会先 stop 翻译，反之亦然。
class DeviceRecorder {
  DeviceRecorder(this._session) {
    _evtSub = _session.eventStream.listen(_onEvent);
  }

  final DeviceSession _session;
  StreamSubscription<DeviceSessionEvent>? _evtSub;

  final _audioCtrl = StreamController<DeviceRecordFrame>.broadcast();
  final _stateCtrl = StreamController<DeviceRecordStateEvent>.broadcast();
  final _errorCtrl = StreamController<DeviceException>.broadcast();

  bool _disposed = false;

  /// PCM 帧流。
  Stream<DeviceRecordFrame> get audioFrames => _audioCtrl.stream;

  /// 录音 start/stop 状态流。
  Stream<DeviceRecordStateEvent> get stateChanges => _stateCtrl.stream;

  /// 录音错误流（来自 `jieli.deviceRecord.*` 通道的 error 事件）。
  Stream<DeviceException> get errors => _errorCtrl.stream;

  /// 启动设备录音上行。
  ///
  /// [sampleRate] 默认 16000，与杰理 SDK CALL_TRANSLATION + DEVICE_ALWAYS_RECORDING
  /// 的默认值一致；其他厂商可传入支持的采样率。
  Future<void> start({int sampleRate = 16000}) {
    _checkAlive();
    return _session.invokeFeature('jieli.deviceRecord.start', {
      'sampleRate': sampleRate,
    });
  }

  /// 停止设备录音上行。幂等。
  Future<void> stop() {
    _checkAlive();
    return _session.invokeFeature('jieli.deviceRecord.stop');
  }

  /// 查询录音状态。返回的 map 至少包含 `recording: bool`。
  Future<Map<String, Object?>> status() {
    _checkAlive();
    return _session.invokeFeature('jieli.deviceRecord.status');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _evtSub?.cancel();
    _evtSub = null;
    await _audioCtrl.close();
    await _stateCtrl.close();
    await _errorCtrl.close();
  }

  // ─── 内部 ────────────────────────────────────────────────────────────────

  void _checkAlive() {
    if (_disposed) throw StateError('DeviceRecorder already disposed');
  }

  void _onEvent(DeviceSessionEvent e) {
    switch (e.type) {
      case DeviceSessionEventType.feature:
        final f = e.feature;
        if (f == null) return;
        final frame = DeviceRecordFrame.tryFromFeature(f);
        if (frame != null) {
          if (!_audioCtrl.isClosed) _audioCtrl.add(frame);
          return;
        }
        final state = DeviceRecordStateEvent.tryFromFeature(f);
        if (state != null && !_stateCtrl.isClosed) {
          _stateCtrl.add(state);
        }
      case DeviceSessionEventType.error:
        // 仅转发录音相关错误（jieli.deviceRecord 前缀），其他错误属于其它通道。
        final msg = e.errorMessage ?? '';
        if (!msg.contains('deviceRecord')) return;
        if (!_errorCtrl.isClosed) {
          _errorCtrl.add(DeviceException(
            e.errorCode ?? DeviceErrorCode.featureFailed,
            msg,
          ));
        }
      default:
        break;
    }
  }
}

const _kAudioKey = 'jieli.deviceRecord.audio';
const _kStartKey = 'jieli.deviceRecord.start';
const _kStopKey = 'jieli.deviceRecord.stop';
