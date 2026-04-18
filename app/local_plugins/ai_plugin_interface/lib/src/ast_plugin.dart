import 'package:flutter/foundation.dart';

/// AST（端到端语音翻译）配置
class AstConfig {
  const AstConfig({
    required this.apiKey,
    required this.appId,
    this.srcLang = 'zh',
    this.dstLang = 'en',
    this.extraParams = const {},
  });

  final String apiKey;
  final String appId;
  final String srcLang;
  final String dstLang;
  final Map<String, String> extraParams;
}

/// 识别事件归属的角色
///
/// - [source]：原文（用户语音识别结果）
/// - [translated]：译文（服务端翻译结果）
enum AstRole {
  source,
  translated,
}

/// AST 事件类型。
///
/// 与 STS 协议对齐，识别 5 件套（每事件携带 [requestId] 与 [AstRole]，
/// [recognitionEnd] 的 role 为 null）：
///
///   `recognitionStart` → `recognizing`* → `recognized`* → `recognitionDone`
///   → `recognitionEnd`
///
/// 任一阶段可伴随 `recognitionError`（不关闭流）。
///
/// 文本语义：
/// - `recognizing.text` = **累计快照**（覆盖语义）
/// - `recognized.text`  = **本段定稿**（累加语义）
///
/// AST 端无独立的合成 / 播报事件流（Web 浏览器自播 remote audio，
/// Android 由 SDK 内部播放），需要时上层从 [recognitionEnd] 推断回合结束。
enum AstEventType {
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

  /// 非归属错误（连接层 / 未知异常）。识别错误请使用 [recognitionError]。
  error,
}

/// AST 事件
@immutable
class AstEvent {
  const AstEvent({
    required this.type,
    this.role,
    this.requestId,
    this.text,
    this.errorCode,
    this.errorMessage,
  });

  final AstEventType type;

  /// 识别 5 件套必带；[AstEventType.recognitionEnd] 为 `null`（跨 role 的回合级事件）。
  final AstRole? role;

  /// 识别 5 件套必带。一问一答链路的关联 id，由 source 侧
  /// [AstEventType.recognitionStart] 生成，贯穿整个回合。
  final String? requestId;

  /// [AstEventType.recognizing]：累计快照（覆盖）
  /// [AstEventType.recognized] ：本段定稿（累加）
  /// 其它识别事件不带文本。
  final String? text;

  final String? errorCode;
  final String? errorMessage;
}

/// AST 插件抽象接口（端到端语音翻译）
abstract class AstPlugin {
  /// 初始化
  Future<void> initialize(AstConfig config);

  /// 建立连接（WebSocket / WebRTC）
  Future<void> startCall();

  /// 发送音频数据（麦克风录制的 PCM）。Web 端浏览器自驱麦克风时为 no-op。
  void sendAudio(List<int> pcmData);

  /// 结束通话
  Future<void> stopCall();

  /// AST 事件流
  Stream<AstEvent> get eventStream;

  /// 释放资源
  Future<void> dispose();
}
