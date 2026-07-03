import 'package:flutter/foundation.dart';

/// 通话翻译请求。
///
/// 通话翻译是双向场景：
/// - 用户说 [userLanguage] → 用 uplink agent 翻成 [peerLanguage] 给对方听；
/// - 对方说 [peerLanguage] → 用 downlink agent 翻成 [userLanguage] 给用户听。
///
/// 两条 leg 的 agent **完全独立**——不同实例、不同配置（虽然 agentType 一般相同）。
/// 调用方需要分别提供两份 [NativeAgentConfig] map（agentId / vendor / config JSON 等）。
@immutable
class CallTranslationRequest {
  const CallTranslationRequest({
    required this.uplinkAgentType,
    required this.uplinkConfig,
    required this.downlinkAgentType,
    required this.downlinkConfig,
    required this.userLanguage,
    required this.peerLanguage,
    this.sessionId,
  });

  /// agent 类型：`ast-translate` / `translate`（与 NativeAgentRegistry 注册的 type 对齐）。
  final String uplinkAgentType;

  /// uplink agent 的 native config，shape 与 [NativeAgentConfig.fromMap] 一致：
  /// `{agentId, inputMode, astVendor, astConfigJson, sttVendor, sttConfigJson, ...}`
  final Map<String, Object?> uplinkConfig;

  final String downlinkAgentType;
  final Map<String, Object?> downlinkConfig;

  /// ISO 639-3 / IETF BCP-47 语言标签。
  final String userLanguage;
  final String peerLanguage;

  /// 显式 sessionId；不传则由 native 生成。
  final String? sessionId;
}

// ---------------------------------------------------------------------------
// 占位：面对面翻译 / 音视频翻译
// ---------------------------------------------------------------------------

@immutable
class FaceToFaceTranslationRequest {
  const FaceToFaceTranslationRequest({
    required this.userAgentType,
    required this.userConfig,
    required this.peerAgentType,
    required this.peerConfig,
    required this.userLanguage,
    required this.peerLanguage,
  });

  final String userAgentType;
  final Map<String, Object?> userConfig;
  final String peerAgentType;
  final Map<String, Object?> peerConfig;
  final String userLanguage;
  final String peerLanguage;
}

@immutable
class AudioTranslationRequest {
  const AudioTranslationRequest({
    required this.agentType,
    required this.config,
    required this.sourceLanguage,
    required this.destLanguage,
  });

  final String agentType;
  final Map<String, Object?> config;
  final String sourceLanguage;
  final String destLanguage;
}
