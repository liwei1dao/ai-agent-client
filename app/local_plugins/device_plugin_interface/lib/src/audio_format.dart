import 'package:flutter/foundation.dart';

/// 音频编码。
enum AudioCodec {
  /// Opus 编码（推荐，设备端→app 上行默认）
  opus,

  /// 16-bit 小端 PCM
  pcm16le,
}

/// 设备插件与 agent 容器之间统一的音频格式约束。
///
/// 接口层规定：
/// - 所有 [DeviceAudioSource] 派发的 [AudioFrame] 必须满足 [AudioFormat.standard]；
/// - 所有 [DeviceAudioSink] 接受的 [AudioFrame] 必须满足 [AudioFormat.standard]。
///
/// 厂商插件内部如果拿到的格式不一致（如 8 kHz Opus、PCM、非 20ms 帧长），
/// **必须**在 vendor SDK 出口做重采样 / 转码 / 重新切帧后再送入 Stream。
/// 转换不可行时，在 [DevicePlugin.initialize] 阶段抛出
/// `DeviceException('device.format_unsupported')`，让上层禁用该厂商。
@immutable
class AudioFormat {
  const AudioFormat({
    required this.codec,
    required this.sampleRate,
    required this.channels,
    required this.frameMs,
  });

  /// 接口层规定的统一格式：Opus / 16 kHz / mono / 20 ms 一帧。
  ///
  /// 适用于"app 直接转发设备端 OPUS 帧"的零转码路径（旧版设计）。
  static const AudioFormat standard = AudioFormat(
    codec: AudioCodec.opus,
    sampleRate: 16000,
    channels: 1,
    frameMs: 20,
  );

  /// PCM 16-bit LE / 16 kHz / mono / 20 ms 一帧 = 640 字节。
  ///
  /// 当前 jieli 通话翻译路径已经在 native 端把 OPUS 解码成 PCM 再上推，
  /// translate_server / agent 直接吃这个格式即可（无需自己解码）。
  static const AudioFormat pcm16kMono20ms = AudioFormat(
    codec: AudioCodec.pcm16le,
    sampleRate: 16000,
    channels: 1,
    frameMs: 20,
  );

  final AudioCodec codec;
  final int sampleRate;
  final int channels;

  /// 单帧时长（毫秒）。
  final int frameMs;

  bool isCompatibleWith(AudioFormat other) =>
      codec == other.codec &&
      sampleRate == other.sampleRate &&
      channels == other.channels &&
      frameMs == other.frameMs;

  @override
  String toString() =>
      'AudioFormat(${codec.name}, ${sampleRate}Hz, ${channels}ch, ${frameMs}ms)';
}

/// 单帧音频。
@immutable
class AudioFrame {
  const AudioFrame({
    required this.bytes,
    required this.format,
    required this.sequence,
    required this.timestampUs,
  });

  /// 帧负载。Opus 时为压缩字节；PCM 时为 16-bit 小端样本。
  final Uint8List bytes;

  /// 实际帧格式。理论上等于 [AudioFormat.standard]，
  /// 实现方仍需逐帧附带，便于 agent 容器层防御性校验。
  final AudioFormat format;

  /// 严格单调递增的帧序号；丢帧后**不得**回填。
  final int sequence;

  /// 单调递增的捕获时间戳（微秒）。
  final int timestampUs;
}
