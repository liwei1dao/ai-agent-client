import 'dart:async';

import 'package:flutter/services.dart';

// device_plugin_interface 适配器（让 device_manager 以厂商无关方式驱动 jieli）。
export 'src/jieli_device_plugin.dart';
export 'src/jieli_device_session.dart';

const _methodChannel = MethodChannel('device_jieli/method');
const _eventChannel = EventChannel('device_jieli/event');

class JieliDevice {
  JieliDevice({
    required this.name,
    required this.address,
    this.edrAddr,
    this.deviceType,
    this.connectWay,
    this.rssi,
  });

  final String name;
  final String address;
  final String? edrAddr;
  final int? deviceType;
  final int? connectWay;
  final int? rssi;

  factory JieliDevice.fromMap(Map<dynamic, dynamic> m) => JieliDevice(
        name: (m['name'] as String?) ?? '',
        address: m['address'] as String,
        edrAddr: m['edrAddr'] as String?,
        deviceType: m['deviceType'] as int?,
        connectWay: m['connectWay'] as int?,
        rssi: m['rssi'] as int?,
      );

  @override
  String toString() => 'JieliDevice($name, $address, rssi=$rssi)';
}

abstract class JieliEvent {
  const JieliEvent();
}

class AdapterStatusEvent extends JieliEvent {
  final bool enabled;
  final bool hasBle;
  const AdapterStatusEvent(this.enabled, this.hasBle);
}

class ScanStatusEvent extends JieliEvent {
  final bool ble;
  final bool started;
  const ScanStatusEvent(this.ble, this.started);
}

class DeviceFoundEvent extends JieliEvent {
  final JieliDevice device;
  const DeviceFoundEvent(this.device);
}

class BondStatusEvent extends JieliEvent {
  final String address;
  final int status;
  const BondStatusEvent(this.address, this.status);
}

class RcspInitEvent extends JieliEvent {
  final String address;
  final int code;
  const RcspInitEvent(this.address, this.code);
  bool get success => code == 0;
}

class ConnectionStateEvent extends JieliEvent {
  final String address;
  final int state;
  const ConnectionStateEvent(this.address, this.state);

  static const int connectionOk = 1;
  static const int connectionConnecting = 2;
  static const int connectionDisconnect = 0;
}

class UnknownJieliEvent extends JieliEvent {
  final Map<dynamic, dynamic> raw;
  const UnknownJieliEvent(this.raw);
}

// ───── 设备级事件 ─────

class BatteryEvent extends JieliEvent {
  final String? address;
  final int? level;
  const BatteryEvent(this.address, this.level);
}

class PhoneCallStatusEvent extends JieliEvent {
  final String? address;
  final int status;
  const PhoneCallStatusEvent(this.address, this.status);
}

class ExpandFunctionEvent extends JieliEvent {
  final String? address;
  final int opCode;
  final String? payloadBase64;
  const ExpandFunctionEvent(this.address, this.opCode, this.payloadBase64);
}

// ───── 翻译事件 ─────

class TranslationModeIds {
  static const int idle = 0;
  static const int record = 1;
  static const int recordingTranslation = 2;
  static const int callTranslation = 3;
  static const int audioTranslation = 4;
  static const int faceToFaceTranslation = 5;
  static const int callTranslationWithStereo = 6;
}

class TranslationStreams {
  static const String inMic = 'in.mic';
  static const String inUplink = 'in.uplink';
  static const String inDownlink = 'in.downlink';
  static const String inAudioFile = 'in.audioFile';
  static const String outSpeaker = 'out.speaker';
  static const String outUplink = 'out.uplink';
  static const String outDownlink = 'out.downlink';
  static const String outLocalPlayback = 'out.localPlayback';
}

class TranslationAudioEvent extends JieliEvent {
  final int modeId;
  final String streamId;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int seq;
  final int tsMs;
  final bool isFinal;

  /// 16bit signed PCM 字节流（小端，interleaved 当 channels>1）
  final Uint8List pcm;

  const TranslationAudioEvent({
    required this.modeId,
    required this.streamId,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.seq,
    required this.tsMs,
    required this.isFinal,
    required this.pcm,
  });
}

class TranslationLogEvent extends JieliEvent {
  final int modeId;
  final String content;
  const TranslationLogEvent(this.modeId, this.content);
}

class TranslationResultEvent extends JieliEvent {
  final int modeId;
  final String? srcLang;
  final String? srcText;
  final String? destLang;
  final String? destText;
  /// 由调用方贯穿同一段翻译，便于字幕聚合到具体段落
  final String? requestId;
  const TranslationResultEvent({
    required this.modeId,
    this.srcLang, this.srcText, this.destLang, this.destText,
    this.requestId,
  });
}

class TranslationErrorEvent extends JieliEvent {
  final int modeId;
  final int code;
  final String? message;
  const TranslationErrorEvent(this.modeId, this.code, this.message);
}

// ───── 语音助手 / 唤醒事件 ─────

class SpeechStartEvent extends JieliEvent {
  final String? address;
  /// RecordParam.VOICE_TYPE_PCM=0 / SPEEX=1 / OPUS=2
  final int? voiceType;
  /// 已转换为 Hz（如 16000）
  final int? sampleRate;
  /// VAD_WAY_DEVICE=0 / SDK=1
  final int? vadWay;
  final int tsMs;
  const SpeechStartEvent({
    this.address,
    this.voiceType, this.sampleRate, this.vadWay,
    required this.tsMs,
  });
}

class SpeechAudioEvent extends JieliEvent {
  final String? address;
  /// 'pcm16' / 'speex'（speex 时未解码）
  final String encoding;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int tsMs;
  /// 16bit signed PCM（encoding=='pcm16'）；speex 时为原始帧
  final Uint8List pcm;
  const SpeechAudioEvent({
    this.address,
    required this.encoding,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.tsMs,
    required this.pcm,
  });
}

class SpeechEndEvent extends JieliEvent {
  final String? address;
  final int? reason;
  final String? message;
  final int tsMs;
  const SpeechEndEvent({this.address, this.reason, this.message, required this.tsMs});
}

class SpeechErrorEvent extends JieliEvent {
  final int code;
  final String? message;
  const SpeechErrorEvent(this.code, this.message);
}

class SpeechVoiceType {
  static const int pcm = 0;
  static const int speex = 1;
  static const int opus = 2;
}

class SpeechSampleRate {
  static const int khz8 = 8;
  static const int khz16 = 16;
}

class SpeechVadWay {
  static const int device = 0;
  static const int sdk = 1;
}

class SpeechStopReason {
  static const int normal = 0;
  static const int stop = 1;
}

// ───── OTA 事件 ─────

enum OtaState {
  idle, inquiring, notifyingSize, entering, transferring, verifying, rebooting, done, failed, cancelled,
}

class OtaStateEvent extends JieliEvent {
  final OtaState state;
  final int sent;
  final int total;
  /// -1 表示未知（idle/cancelled 等）
  final int percent;
  final int tsMs;
  const OtaStateEvent({
    required this.state, required this.sent, required this.total,
    required this.percent, required this.tsMs,
  });
}

class OtaErrorEvent extends JieliEvent {
  final int code;
  final String? message;
  const OtaErrorEvent(this.code, this.message);
}

class Jielihome {
  Jielihome._();
  static final Jielihome instance = Jielihome._();

  Stream<JieliEvent>? _events;

  Stream<JieliEvent> get events {
    return _events ??= _eventChannel
        .receiveBroadcastStream()
        .map<JieliEvent>((raw) => _parseEvent(raw as Map));
  }

  JieliEvent _parseEvent(Map raw) {
    switch (raw['type']) {
      case 'adapterStatus':
        return AdapterStatusEvent(raw['enabled'] == true, raw['hasBle'] == true);
      case 'scanStatus':
        return ScanStatusEvent(raw['ble'] == true, raw['started'] == true);
      case 'deviceFound':
        return DeviceFoundEvent(JieliDevice.fromMap(raw));
      case 'bondStatus':
        return BondStatusEvent(raw['address'] as String, raw['status'] as int);
      case 'rcspInit':
        return RcspInitEvent(raw['address'] as String, raw['code'] as int);
      case 'connectionState':
        return ConnectionStateEvent(raw['address'] as String, raw['state'] as int);
      case 'battery':
        return BatteryEvent(raw['address'] as String?, raw['level'] as int?);
      case 'phoneCallStatus':
        return PhoneCallStatusEvent(raw['address'] as String?, (raw['status'] as int?) ?? 0);
      case 'expandFunction':
        return ExpandFunctionEvent(
          raw['address'] as String?,
          (raw['opCode'] as int?) ?? 0,
          raw['payloadBase64'] as String?,
        );
      case 'translationAudio':
        return TranslationAudioEvent(
          modeId: (raw['modeId'] as int?) ?? 0,
          streamId: raw['streamId'] as String,
          sampleRate: (raw['sampleRate'] as int?) ?? 16000,
          channels: (raw['channels'] as int?) ?? 1,
          bitsPerSample: (raw['bitsPerSample'] as int?) ?? 16,
          seq: (raw['seq'] as num?)?.toInt() ?? 0,
          tsMs: (raw['tsMs'] as num?)?.toInt() ?? 0,
          isFinal: raw['final'] == true,
          pcm: raw['pcm'] as Uint8List,
        );
      case 'translationLog':
        return TranslationLogEvent(
          (raw['modeId'] as int?) ?? 0,
          raw['content'] as String? ?? '',
        );
      case 'translationResult':
        return TranslationResultEvent(
          modeId: (raw['modeId'] as int?) ?? 0,
          srcLang: raw['srcLang'] as String?,
          srcText: raw['srcText'] as String?,
          destLang: raw['destLang'] as String?,
          destText: raw['destText'] as String?,
          requestId: raw['requestId'] as String?,
        );
      case 'translationError':
        return TranslationErrorEvent(
          (raw['modeId'] as int?) ?? 0,
          (raw['code'] as int?) ?? 0,
          raw['message'] as String?,
        );
      case 'speechStart':
        return SpeechStartEvent(
          address: raw['address'] as String?,
          voiceType: raw['voiceType'] as int?,
          sampleRate: raw['sampleRate'] as int?,
          vadWay: raw['vadWay'] as int?,
          tsMs: (raw['tsMs'] as num?)?.toInt() ?? 0,
        );
      case 'speechAudio':
        return SpeechAudioEvent(
          address: raw['address'] as String?,
          encoding: (raw['encoding'] as String?) ?? 'pcm16',
          sampleRate: (raw['sampleRate'] as int?) ?? 16000,
          channels: (raw['channels'] as int?) ?? 1,
          bitsPerSample: (raw['bitsPerSample'] as int?) ?? 16,
          tsMs: (raw['tsMs'] as num?)?.toInt() ?? 0,
          pcm: raw['pcm'] as Uint8List,
        );
      case 'speechEnd':
        return SpeechEndEvent(
          address: raw['address'] as String?,
          reason: raw['reason'] as int?,
          message: raw['message'] as String?,
          tsMs: (raw['tsMs'] as num?)?.toInt() ?? 0,
        );
      case 'speechError':
        return SpeechErrorEvent(
          (raw['code'] as int?) ?? 0,
          raw['message'] as String?,
        );
      case 'otaState':
        return OtaStateEvent(
          state: _parseOtaState(raw['state'] as String?),
          sent: (raw['sent'] as num?)?.toInt() ?? -1,
          total: (raw['total'] as num?)?.toInt() ?? 0,
          percent: (raw['percent'] as int?) ?? -1,
          tsMs: (raw['tsMs'] as num?)?.toInt() ?? 0,
        );
      case 'otaError':
        return OtaErrorEvent(
          (raw['code'] as int?) ?? 0,
          raw['message'] as String?,
        );
      default:
        return UnknownJieliEvent(raw);
    }
  }

  OtaState _parseOtaState(String? s) {
    switch (s) {
      case 'INQUIRING':       return OtaState.inquiring;
      case 'NOTIFYING_SIZE':  return OtaState.notifyingSize;
      case 'ENTERING':        return OtaState.entering;
      case 'TRANSFERRING':    return OtaState.transferring;
      case 'VERIFYING':       return OtaState.verifying;
      case 'REBOOTING':       return OtaState.rebooting;
      case 'DONE':            return OtaState.done;
      case 'FAILED':          return OtaState.failed;
      case 'CANCELLED':       return OtaState.cancelled;
      default:                return OtaState.idle;
    }
  }

  Future<String?> getPlatformVersion() async {
    return await _methodChannel.invokeMethod<String>('getPlatformVersion');
  }

  Future<void> initialize({
    bool multiDevice = true,
    bool skipNoNameDev = false,
    bool enableLog = false,
  }) async {
    await _methodChannel.invokeMethod<bool>('initialize', {
      'multiDevice': multiDevice,
      'skipNoNameDev': skipNoNameDev,
      'enableLog': enableLog,
    });
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 30)}) async {
    await _methodChannel.invokeMethod<bool>('startScan', {
      'timeoutMs': timeout.inMilliseconds,
    });
  }

  Future<void> stopScan() => _methodChannel.invokeMethod('stopScan');

  Future<bool> isScanning() async =>
      (await _methodChannel.invokeMethod<bool>('isScanning')) ?? false;

  Future<void> connect(JieliDevice device) async {
    await _methodChannel.invokeMethod<bool>('connect', {
      'address': device.address,
      'edrAddr': device.edrAddr,
      'connectWay': device.connectWay,
      'deviceType': device.deviceType,
    });
  }

  Future<void> disconnect(String address) async {
    await _methodChannel.invokeMethod<bool>('disconnect', {'address': address});
  }

  Future<bool> isConnected(String address) async =>
      (await _methodChannel.invokeMethod<bool>('isConnected', {'address': address})) ??
      false;

  Future<JieliDevice?> connectedDevice() async {
    final raw = await _methodChannel.invokeMethod<Map?>('connectedDevice');
    if (raw == null) return null;
    return JieliDevice(
      name: (raw['name'] as String?) ?? '',
      address: raw['address'] as String,
    );
  }

  // ───── 设备信息查询 ─────

  Future<Map<String, Object?>?> deviceSnapshot(String address) async {
    final raw = await _methodChannel.invokeMethod<Map?>(
      'deviceSnapshot', {'address': address});
    return raw?.cast<String, Object?>();
  }

  Future<Map<String, Object?>?> queryTargetInfo(String address, {int mask = 0x0F}) async {
    final raw = await _methodChannel.invokeMethod<Map?>(
      'queryTargetInfo', {'address': address, 'mask': mask});
    return raw?.cast<String, Object?>();
  }

  // ───── 自定义指令 ─────

  Future<List<int>?> sendCustomCmd(String address, int opCode, List<int> payload) async {
    final raw = await _methodChannel.invokeMethod<List<dynamic>?>(
      'sendCustomCmd',
      {'address': address, 'opCode': opCode, 'payload': payload},
    );
    return raw?.cast<int>();
  }

  // ───── 翻译 ─────

  Future<void> startTranslation({
    required int modeId,
    Map<String, Object?> args = const {},
  }) async {
    await _methodChannel.invokeMethod<bool>('startTranslation', {
      'modeId': modeId,
      'args': args,
    });
  }

  Future<void> stopTranslation() =>
      _methodChannel.invokeMethod('stopTranslation');

  Future<Map<String, Object?>?> translationStatus() async {
    final raw = await _methodChannel.invokeMethod<Map?>('translationStatus');
    return raw?.cast<String, Object?>();
  }

  /// 把外部翻译服务返回的 TTS PCM 喂回插件，由插件根据当前模式回送给耳机或本地播放。
  /// [pcm] 必须是 16bit signed PCM（小端、interleaved when channels>1）。
  /// 推荐传 [Uint8List]；也接受 List&lt;int&gt; 但会触发一次拷贝。
  Future<bool> feedTranslatedAudio({
    required String streamId,
    required List<int> pcm,
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
    bool isFinal = false,
  }) async {
    final bytes = pcm is Uint8List ? pcm : Uint8List.fromList(pcm);
    return (await _methodChannel.invokeMethod<bool>('feedTranslatedAudio', {
          'streamId': streamId,
          'pcm': bytes,
          'sampleRate': sampleRate,
          'channels': channels,
          'bitsPerSample': bitsPerSample,
          'final': isFinal,
        })) ??
        false;
  }

  /// 透传翻译文本（字幕）到 EventChannel，供 UI 订阅 [TranslationResultEvent]。
  /// [requestId] 用于把同一段翻译的多次回调串起来。
  Future<void> feedTranslationResult({
    String? srcLang, String? srcText,
    String? destLang, String? destText,
    String? requestId,
  }) async {
    await _methodChannel.invokeMethod('feedTranslationResult', {
      'srcLang': srcLang,
      'srcText': srcText,
      'destLang': destLang,
      'destText': destText,
      'requestId': requestId,
    });
  }

  /// 探测当前已连耳机是否支持立体声通话翻译方案。
  /// [address] 不传则用当前已连设备。
  Future<bool> isSupportCallTranslationWithStereo({String? address}) async {
    return (await _methodChannel.invokeMethod<bool>(
          'isSupportCallTranslationWithStereo',
          {'address': address},
        )) ??
        false;
  }

  /// 把外部音频文件解码后的 PCM 灌入「音视频翻译」模式（仅 MODE_AUDIO_TRANSLATION 生效）。
  Future<bool> feedAudioFilePcm({
    required List<int> pcm,
    int sampleRate = 16000,
  }) async {
    final bytes = pcm is Uint8List ? pcm : Uint8List.fromList(pcm);
    return (await _methodChannel.invokeMethod<bool>('feedAudioFilePcm', {
          'pcm': bytes,
          'sampleRate': sampleRate,
        })) ??
        false;
  }

  // ───── 语音助手 / 唤醒 ─────
  // 提示：插件初始化时已经常驻订阅了耳机 RECORD 状态回调；
  //   - 耳机本地检测到唤醒词或按键 → 自动收到 SpeechStart/SpeechAudio/SpeechEnd 事件
  //   - 业务层不需要先调任何方法
  // 下面的 speechStart/Stop 仅用于「APP 主动触发/取消」语音助手的场景。

  Future<bool> speechIsRecording({String? address}) async =>
      (await _methodChannel.invokeMethod<bool>('speechIsRecording', {'address': address})) ??
      false;

  Future<void> speechStart({
    String? address,
    int voiceType = SpeechVoiceType.opus,
    int sampleRate = SpeechSampleRate.khz16,
    int vadWay = SpeechVadWay.device,
  }) async {
    await _methodChannel.invokeMethod<bool>('speechStart', {
      'address': address,
      'voiceType': voiceType,
      'sampleRate': sampleRate,
      'vadWay': vadWay,
    });
  }

  Future<void> speechStop({
    String? address,
    int reason = SpeechStopReason.normal,
  }) async {
    await _methodChannel.invokeMethod<bool>('speechStop', {
      'address': address,
      'reason': reason,
    });
  }

  // ───── OTA ─────

  /// 启动 OTA 升级。订阅 [OtaStateEvent] / [OtaErrorEvent] 看进度。
  /// [firmwareFilePath] 必须是手机本地完整路径（你提前下好的固件文件）。
  Future<void> otaStart({
    String? address,
    required String firmwareFilePath,
    int blockSize = 512,
    List<int>? fileFlag,
  }) async {
    await _methodChannel.invokeMethod<bool>('otaStart', {
      'address': address,
      'firmwareFilePath': firmwareFilePath,
      'blockSize': blockSize,
      if (fileFlag != null)
        'fileFlag': fileFlag is Uint8List ? fileFlag : Uint8List.fromList(fileFlag),
    });
  }

  Future<void> otaCancel() => _methodChannel.invokeMethod('otaCancel');

  Future<bool> otaIsRunning() async =>
      (await _methodChannel.invokeMethod<bool>('otaIsRunning')) ?? false;
}
