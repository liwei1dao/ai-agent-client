import 'dart:async';

import 'package:device_plugin_interface/device_plugin_interface.dart';
import 'package:flutter/services.dart';

import '../device_jieli.dart';

/// Jieli 会话适配。
///
/// 连接生命周期映射：
/// - `ConnectionStateEvent.state == 2` (CONNECTING) → [DeviceConnectionState.connecting]
/// - `ConnectionStateEvent.state == 1` (OK)        → [DeviceConnectionState.linkConnected]
/// - `RcspInitEvent(success=true)`                  → [DeviceConnectionState.ready]
/// - `ConnectionStateEvent.state == 0` (DISCONNECT) → [DeviceConnectionState.disconnected]
///
/// 当前 native 侧未暴露 mic uplink / spk downlink 通道，
/// `openMicUplink` / `openSpeakerDownlink` 暂抛 `device.not_supported`，
/// 等 kotlin 层接 PCM/Opus 后再实装。
class JieliDeviceSession implements DeviceSession {
  JieliDeviceSession({
    required Jielihome home,
    required this.deviceId,
    required this.vendor,
    required Set<DeviceCapability> capabilities,
    required this.onClosed,
    String initialName = '',
  })  : _home = home,
        _capabilities = capabilities,
        _info = DeviceInfo(id: deviceId, name: initialName, vendor: vendor);

  static const MethodChannel _method = MethodChannel('device_jieli/method');

  final Jielihome _home;
  final void Function() onClosed;

  @override
  final String deviceId;
  @override
  final String vendor;

  final Set<DeviceCapability> _capabilities;
  DeviceInfo _info;

  DeviceConnectionState _state = DeviceConnectionState.connecting;
  final StreamController<DeviceSessionEvent> _evt =
      StreamController.broadcast();
  Completer<DeviceSession>? _readyCompleter;
  Timer? _readyTimer;
  bool _disposed = false;

  @override
  DeviceConnectionState get state => _state;

  @override
  DeviceInfo get info => _info;

  @override
  Set<DeviceCapability> get capabilities => _capabilities;

  @override
  Stream<DeviceSessionEvent> get eventStream => _evt.stream;

  /// `JieliDevicePlugin.connect` 中等待握手完成。
  Future<DeviceSession> waitReady({required Duration timeout}) {
    if (_state == DeviceConnectionState.ready) return Future.value(this);
    final c = _readyCompleter ??= Completer<DeviceSession>();
    _readyTimer ??= Timer(timeout, () {
      if (!c.isCompleted) {
        c.completeError(
          DeviceException(DeviceErrorCode.connectTimeout,
              'jieli connect/handshake timeout'),
        );
        _close(silent: true);
      }
    });
    return c.future;
  }

  /// 由 plugin 转发 ConnectionStateEvent。
  void updateConnectionFromRaw(int raw) {
    switch (raw) {
      case ConnectionStateEvent.connectionConnecting:
        _setState(DeviceConnectionState.connecting);
      case ConnectionStateEvent.connectionOk:
        _setState(DeviceConnectionState.linkConnected);
      case ConnectionStateEvent.connectionDisconnect:
        _setState(DeviceConnectionState.disconnected);
        _completeReadyError(
          DeviceException(DeviceErrorCode.disconnectedRemote),
        );
        _close();
    }
  }

  /// 由 [JieliDevicePlugin._onJieliEvent] 转发翻译相关事件（V4.2 新 API）。
  ///
  /// 新 SDK 把 OPUS 解码内化，对外只发 PCM16；通道用字符串 [TranslationStreams]
  /// 标识（`in.uplink` / `out.downlink` 等）。这里把它们翻译为通用的
  /// `feature.<key>`，业务层订阅 [eventStream] 并按 `feature.key` 路由。
  void dispatchTranslationEvent(JieliEvent raw) {
    if (_evt.isClosed) return;
    if (raw is TranslationAudioEvent) {
      _evt.add(DeviceSessionEvent(
        type: DeviceSessionEventType.feature,
        deviceId: deviceId,
        feature: DeviceFeatureEvent(
          key: 'jieli.translation.audio',
          data: {
            'modeId': raw.modeId,
            'streamId': raw.streamId,
            'sampleRate': raw.sampleRate,
            'channels': raw.channels,
            'bitsPerSample': raw.bitsPerSample,
            'seq': raw.seq,
            'tsMs': raw.tsMs,
            'final': raw.isFinal,
            'pcm': raw.pcm,
          },
        ),
      ));
    } else if (raw is TranslationLogEvent) {
      _evt.add(DeviceSessionEvent(
        type: DeviceSessionEventType.feature,
        deviceId: deviceId,
        feature: DeviceFeatureEvent(
          key: 'jieli.translation.log',
          data: {
            'modeId': raw.modeId,
            'content': raw.content,
          },
        ),
      ));
    } else if (raw is TranslationResultEvent) {
      _evt.add(DeviceSessionEvent(
        type: DeviceSessionEventType.feature,
        deviceId: deviceId,
        feature: DeviceFeatureEvent(
          key: 'jieli.translation.result',
          data: {
            'modeId': raw.modeId,
            if (raw.srcLang != null) 'srcLang': raw.srcLang,
            if (raw.srcText != null) 'srcText': raw.srcText,
            if (raw.destLang != null) 'destLang': raw.destLang,
            if (raw.destText != null) 'destText': raw.destText,
            if (raw.requestId != null) 'requestId': raw.requestId,
          },
        ),
      ));
    } else if (raw is TranslationErrorEvent) {
      _evt.add(DeviceSessionEvent(
        type: DeviceSessionEventType.error,
        deviceId: deviceId,
        errorCode: 'device.feature_failed',
        errorMessage: 'jieli.translation: ${raw.code} ${raw.message ?? ''}',
      ));
    }
  }

  /// 由 plugin 转发 RcspInitEvent。
  void updateRcspInit(bool success) {
    if (success) {
      _setState(DeviceConnectionState.ready);
      _completeReady();
    } else {
      _completeReadyError(DeviceException(DeviceErrorCode.handshakeFailed));
      _close();
    }
  }

  // ---------- DeviceSession 接口实现 ----------

  @override
  Future<int> readRssi() async {
    _requireReady();
    throw DeviceException(DeviceErrorCode.notSupported,
        'jieli native bridge does not expose RSSI yet');
  }

  @override
  Future<int?> readBattery() async {
    _requireReady();
    final snapshot = await _method.invokeMethod<Map>(
      'deviceSnapshot',
      {'address': deviceId},
    );
    final pct = snapshot?['battery'];
    return pct is int ? pct : null;
  }

  @override
  Future<DeviceInfo> refreshInfo() async {
    _requireReady();
    final snapshot = await _method.invokeMethod<Map>(
      'deviceSnapshot',
      {'address': deviceId},
    );
    if (snapshot == null) return _info;
    _info = _info.copyWith(
      name: snapshot['name'] as String? ?? _info.name,
      firmwareVersion: snapshot['firmwareVersion'] as String?,
      hardwareVersion: snapshot['hardwareVersion'] as String?,
      serialNumber: snapshot['serialNumber'] as String?,
      manufacturer: snapshot['manufacturer'] as String?,
      model: snapshot['model'] as String?,
      batteryPercent: snapshot['battery'] as int?,
      metadata: Map<String, Object?>.from(snapshot),
    );
    _evt.add(DeviceSessionEvent(
      type: DeviceSessionEventType.deviceInfoUpdated,
      deviceId: deviceId,
      deviceInfo: _info,
    ));
    return _info;
  }

  @override
  Future<Map<String, Object?>> invokeFeature(
    String featureKey, [
    Map<String, Object?> args = const {},
  ]) async {
    _requireReady();
    switch (featureKey) {
      // ── 翻译能力探测（V4.2 新 SDK 只暴露 stereo 支持探测） ──
      case 'jieli.translation.support':
        final stereo = await Jielihome.instance
            .isSupportCallTranslationWithStereo(address: deviceId);
        return {'supportCallStereo': stereo};

      // ── 翻译模式：start / stop / status ─────────────────
      case 'jieli.translation.start':
        final modeId = args['modeId'];
        if (modeId is! int) {
          throw DeviceException(
            DeviceErrorCode.invalidArgument,
            'modeId(int) required',
          );
        }
        final extra = (args['args'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{};
        await Jielihome.instance.startTranslation(modeId: modeId, args: extra);
        return {'ok': true};

      case 'jieli.translation.stop':
        await Jielihome.instance.stopTranslation();
        return {'ok': true};

      case 'jieli.translation.status':
        final s = await Jielihome.instance.translationStatus();
        return s ?? const <String, Object?>{};

      // ── PCM 翻译音频回灌 / 字幕透传（V4.2 新 API） ──────
      case 'jieli.translation.feedTranslatedAudio':
        final pcm = args['pcm'];
        if (pcm is! List<int>) {
          throw DeviceException(
            DeviceErrorCode.invalidArgument,
            'pcm(List<int>) required',
          );
        }
        final streamId = args['streamId'] as String?;
        if (streamId == null) {
          throw DeviceException(
            DeviceErrorCode.invalidArgument,
            'streamId(String) required (e.g. ${TranslationStreams.outUplink})',
          );
        }
        final ok = await Jielihome.instance.feedTranslatedAudio(
          streamId: streamId,
          pcm: pcm,
          sampleRate: (args['sampleRate'] as int?) ?? 16000,
          channels: (args['channels'] as int?) ?? 1,
          bitsPerSample: (args['bitsPerSample'] as int?) ?? 16,
          isFinal: (args['final'] as bool?) ?? false,
        );
        return {'ok': ok};

      case 'jieli.translation.feedTranslationResult':
        await Jielihome.instance.feedTranslationResult(
          srcLang: args['srcLang'] as String?,
          srcText: args['srcText'] as String?,
          destLang: args['destLang'] as String?,
          destText: args['destText'] as String?,
          requestId: args['requestId'] as String?,
        );
        return {'ok': true};

      case 'jieli.translation.feedAudioFilePcm':
        final pcm = args['pcm'];
        if (pcm is! List<int>) {
          throw DeviceException(
            DeviceErrorCode.invalidArgument,
            'pcm(List<int>) required',
          );
        }
        final ok = await Jielihome.instance.feedAudioFilePcm(
          pcm: pcm,
          sampleRate: (args['sampleRate'] as int?) ?? 16000,
        );
        return {'ok': ok};

      // ── 自定义 RCSP 命令 ────────────────────────────────
      case 'jieli.cmd.send':
        final opCode = args['opCode'];
        final payload = args['payload'];
        if (opCode is! int) {
          throw DeviceException(
            DeviceErrorCode.invalidArgument, 'opCode(int) required',
          );
        }
        final resp = await Jielihome.instance.sendCustomCmd(
          deviceId,
          opCode,
          (payload as List?)?.cast<int>() ?? const <int>[],
        );
        return {'response': resp};

      default:
        throw DeviceException(
          DeviceErrorCode.notSupported,
          'unknown feature "$featureKey"',
        );
    }
  }

  @override
  Future<void> disconnect() async {
    if (_state == DeviceConnectionState.disconnected) return;
    _setState(DeviceConnectionState.disconnecting);
    try {
      await _home.disconnect(deviceId);
    } finally {
      _setState(DeviceConnectionState.disconnected);
      _close();
    }
  }

  // ---------- 内部 ----------

  void _requireReady() {
    if (_disposed || _state != DeviceConnectionState.ready) {
      throw DeviceException(DeviceErrorCode.noActiveSession);
    }
  }

  void _setState(DeviceConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (_evt.isClosed) return;
    _evt.add(DeviceSessionEvent(
      type: DeviceSessionEventType.connectionStateChanged,
      deviceId: deviceId,
      connectionState: s,
    ));
  }

  void _completeReady() {
    _readyTimer?.cancel();
    _readyTimer = null;
    final c = _readyCompleter;
    _readyCompleter = null;
    if (c != null && !c.isCompleted) c.complete(this);
  }

  void _completeReadyError(Object err) {
    _readyTimer?.cancel();
    _readyTimer = null;
    final c = _readyCompleter;
    _readyCompleter = null;
    if (c != null && !c.isCompleted) c.completeError(err);
  }

  Future<void> _close({bool silent = false}) async {
    if (_disposed) return;
    _disposed = true;
    if (!silent) onClosed();
    if (!_evt.isClosed) await _evt.close();
  }
}
