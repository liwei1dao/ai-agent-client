import 'dart:async';
import 'package:flutter/services.dart';
import 'agent_event.dart';

/// AgentRuntimeBridge — 封装 MethodChannel + EventChannel 调用
///
/// 所有 Flutter→Native 命令通过此类发出。
/// Native→Flutter 事件通过 [eventStream] 接收。
class AgentRuntimeBridge {
  static const _commandChannel = MethodChannel('agent_runtime/commands');
  static const _eventChannel = EventChannel('agent_runtime/events');

  static final AgentRuntimeBridge _instance = AgentRuntimeBridge._();
  AgentRuntimeBridge._();
  factory AgentRuntimeBridge() => _instance;

  Stream<AgentEvent>? _eventStream;

  /// Native 事件流（广播流，可多处监听）
  Stream<AgentEvent> get eventStream {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) => parseAgentEvent(raw as Map<Object?, Object?>))
        .where((e) => e != null)
        .cast<AgentEvent>();
    return _eventStream!;
  }

  // ─────────────────────────────────────────────────
  // 命令
  // ─────────────────────────────────────────────────

  Future<void> startSession(AgentSessionConfig config) =>
      _commandChannel.invokeMethod('startSession', config.toMap());

  Future<void> stopSession(String sessionId) =>
      _commandChannel.invokeMethod('stopSession', {'sessionId': sessionId});

  /// 文本模式发送（Flutter 生成 requestId）
  Future<void> sendText(String sessionId, String requestId, String text) =>
      _commandChannel.invokeMethod('sendText', {
        'sessionId': sessionId,
        'requestId': requestId,
        'text': text,
      });

  Future<void> interrupt(String sessionId) =>
      _commandChannel.invokeMethod('interrupt', {'sessionId': sessionId});

  Future<void> setInputMode(String sessionId, String mode) =>
      _commandChannel.invokeMethod('setInputMode', {
        'sessionId': sessionId,
        'mode': mode,
      });

  Future<void> notifyAppForeground(bool isForeground) =>
      _commandChannel.invokeMethod('notifyAppForeground', {
        'isForeground': isForeground,
      });
}

/// Flutter 侧会话配置（传给 Native）
class AgentSessionConfig {
  const AgentSessionConfig({
    required this.sessionId,
    required this.agentId,
    required this.inputMode,
    required this.sttPluginName,
    required this.ttsPluginName,
    required this.llmPluginName,
    this.stsPluginName,
    required this.sttConfigJson,
    required this.ttsConfigJson,
    required this.llmConfigJson,
    this.stsConfigJson,
  });

  final String sessionId;
  final String agentId;
  final String inputMode; // 'text' | 'short_voice' | 'call'
  final String sttPluginName;
  final String ttsPluginName;
  final String llmPluginName;
  final String? stsPluginName;
  final String sttConfigJson;
  final String ttsConfigJson;
  final String llmConfigJson;
  final String? stsConfigJson;

  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'agentId': agentId,
        'inputMode': inputMode,
        'sttPluginName': sttPluginName,
        'ttsPluginName': ttsPluginName,
        'llmPluginName': llmPluginName,
        'stsPluginName': stsPluginName,
        'sttConfigJson': sttConfigJson,
        'ttsConfigJson': ttsConfigJson,
        'llmConfigJson': llmConfigJson,
        'stsConfigJson': stsConfigJson,
      };
}
