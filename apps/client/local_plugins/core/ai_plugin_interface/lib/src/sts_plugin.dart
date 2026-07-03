import 'package:flutter/foundation.dart';

/// STS（端到端语音）配置
class StsConfig {
  const StsConfig({
    required this.apiKey,
    required this.appId,
    this.voiceName = 'zh_female_tianmei',
    this.extraParams = const {},
  });

  final String apiKey;
  final String appId;
  final String voiceName;
  final Map<String, String> extraParams;
}

/// 识别 / 合成 / 播报 / audioChunk 事件归属的角色
///
/// - [user]：用户语音的识别结果
/// - [bot]：AI 侧的文本与音频（识别结果 + 合成音频 + 播报进度）
enum StsRole {
  user,
  bot,
}

/// 音频格式描述（audioChunk / synthesized 首帧必带）
@immutable
class StsAudioFormat {
  const StsAudioFormat({
    required this.sampleRateHz,
    required this.channels,
    required this.encoding,
  });

  final int sampleRateHz;
  final int channels;

  /// `pcm_s16le` / `opus` / `mp3` …
  final String encoding;
}

/// STS 事件类型。
///
/// 生命周期分三块（都带 `requestId`）：
///
/// - **识别**（user / bot 两侧共用 5 件套 + 1 个错误）：
///   `recognitionStart` → `recognizing`* → `recognized`* → `recognitionDone` →
///   `recognitionEnd`；任一阶段可伴随 `recognitionError`（不关流）。
///   - `recognizing.text` = **累计快照**，上层覆盖
///   - `recognized.text`  = **本段定稿**，上层累加；后续 role 仍可出现新的
///     `recognizing`（同一 `recognitionStart` 内多段落）
///   - `recognitionDone`  = 本 role 的识别链路闭合（用户断句说完 / bot 文本全部
///     送完），后续不会再出现同 `(requestId, role)` 的 recognizing / recognized
///   - `recognitionEnd`   = 整个 `requestId` 回合关闭（所有 role 都 done 之后派发）
///
/// - **合成**（role = bot，4 件套 + 1 个错误）：
///   `synthesisStart` → `synthesizing`* → `synthesized`* → `synthesisEnd`；
///   任一阶段可伴随 `synthesisError`（不关流）。
///
/// - **播报 + 音频**（role = bot）：
///   `playbackStart` → `audioChunk`* → `playbackEnd`；
///   `playbackEnd.interrupted = true` 表示被新 `requestId` 抢占。
enum StsEventType {
  // ── 连接 ───────────────────────
  connected,
  disconnected,

  // ── 识别 ───────────────────────
  recognitionStart,
  recognizing,
  recognized,
  recognitionDone,
  recognitionEnd,
  recognitionError,

  // ── 合成 ───────────────────────
  synthesisStart,
  synthesizing,
  synthesized,
  synthesisEnd,
  synthesisError,

  // ── 播报 + 音频帧 ─────────────
  playbackStart,
  playbackEnd,
  audioChunk,

  /// 非归属错误（连接层 / 未知异常）。识别 / 合成错误请使用
  /// [recognitionError] / [synthesisError]。
  error,
}

/// STS 事件
@immutable
class StsEvent {
  const StsEvent({
    required this.type,
    this.role,
    this.requestId,
    this.text,
    this.audioData,
    this.audioFormat,
    this.durationMs,
    this.interrupted = false,
    this.errorCode,
    this.errorMessage,
  });

  final StsEventType type;

  /// 识别 / 合成 / 播报 / [StsEventType.audioChunk] 事件必带。
  /// [StsEventType.recognitionEnd] 为 `null`（跨 role 的回合级事件）。
  final StsRole? role;

  /// 识别 / 合成 / 播报 / [StsEventType.audioChunk] 事件必带。
  /// 一问一答链路的关联 id，由 user 侧 [StsEventType.recognitionStart] 生成，
  /// 贯穿整个回合的所有事件。
  final String? requestId;

  /// [StsEventType.recognizing]：累计快照（覆盖）
  /// [StsEventType.recognized] ：本段定稿（累加）
  /// 其它识别事件不带文本。
  final String? text;

  /// [StsEventType.audioChunk] 必带（PCM / Opus 帧原始字节）。
  final List<int>? audioData;

  /// [StsEventType.audioChunk] 首帧或 [StsEventType.synthesized] 必带。
  final StsAudioFormat? audioFormat;

  /// [StsEventType.synthesized] 必带（本段音频时长，毫秒）。
  final int? durationMs;

  /// [StsEventType.playbackEnd] 标记是否被打断。
  final bool interrupted;

  final String? errorCode;
  final String? errorMessage;
}

/// STS 插件抽象接口（端到端，agent_sts_chat 直接调度）
abstract class StsPlugin {
  /// 初始化
  Future<void> initialize(StsConfig config);

  /// 建立 WebSocket / WebRTC 连接，开始双向通话
  Future<void> startCall();

  /// 发送音频数据（麦克风录制的 PCM）。web 端可为 no-op（浏览器自己管麦克风）。
  void sendAudio(List<int> pcmData);

  /// 结束通话
  Future<void> stopCall();

  /// STS 事件流
  Stream<StsEvent> get eventStream;

  /// 释放资源
  Future<void> dispose();
}
