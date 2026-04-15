import 'dart:async';
import 'package:flutter/services.dart';
import 'agent_event.dart';

/// AgentsServerBridge — agents_server 的 Dart 薄桥接
///
/// 所有 Flutter→Native 命令通过此类发出。
/// Native→Flutter 事件通过 [eventStream] 接收。
class AgentsServerBridge {
  static const _commandChannel = MethodChannel('agents_server/commands');
  static const _eventChannel = EventChannel('agents_server/events');

  static final AgentsServerBridge _instance = AgentsServerBridge._();
  AgentsServerBridge._();
  factory AgentsServerBridge() => _instance;

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
  // Agent 生命周期
  // ─────────────────────────────────────────────────

  /// 创建并初始化一个 Agent
  Future<void> createAgent({
    required String agentId,
    required String agentType,
    String inputMode = 'text',
    String? sttVendor,
    String? ttsVendor,
    String? llmVendor,
    String? stsVendor,
    String? astVendor,
    String? translationVendor,
    String? sttConfigJson,
    String? ttsConfigJson,
    String? llmConfigJson,
    String? stsConfigJson,
    String? astConfigJson,
    String? translationConfigJson,
    Map<String, String> extraParams = const {},
  }) =>
      _commandChannel.invokeMethod('createAgent', {
        'agentId': agentId,
        'agentType': agentType,
        'inputMode': inputMode,
        'sttVendor': sttVendor,
        'ttsVendor': ttsVendor,
        'llmVendor': llmVendor,
        'stsVendor': stsVendor,
        'astVendor': astVendor,
        'translationVendor': translationVendor,
        'sttConfigJson': sttConfigJson,
        'ttsConfigJson': ttsConfigJson,
        'llmConfigJson': llmConfigJson,
        'stsConfigJson': stsConfigJson,
        'astConfigJson': astConfigJson,
        'translationConfigJson': translationConfigJson,
        'extraParams': extraParams,
      });

  /// 停止并释放一个 Agent
  Future<void> stopAgent(String agentId) =>
      _commandChannel.invokeMethod('stopAgent', {'agentId': agentId});

  /// 删除一个 Agent（等同于 stopAgent）
  Future<void> deleteAgent(String agentId) =>
      _commandChannel.invokeMethod('deleteAgent', {'agentId': agentId});

  // ─────────────────────────────────────────────────
  // Agent 命令
  // ─────────────────────────────────────────────────

  /// 发送文本消息
  Future<void> sendText(String agentId, String requestId, String text) =>
      _commandChannel.invokeMethod('sendText', {
        'agentId': agentId,
        'requestId': requestId,
        'text': text,
      });

  /// 切换输入模式
  Future<void> setInputMode(String agentId, String mode) =>
      _commandChannel.invokeMethod('setInputMode', {
        'agentId': agentId,
        'mode': mode,
      });

  /// 开始语音监听
  Future<void> startListening(String agentId) =>
      _commandChannel.invokeMethod('startListening', {'agentId': agentId});

  /// 停止语音监听
  Future<void> stopListening(String agentId) =>
      _commandChannel.invokeMethod('stopListening', {'agentId': agentId});

  /// 打断当前处理
  Future<void> interrupt(String agentId) =>
      _commandChannel.invokeMethod('interrupt', {'agentId': agentId});

  /// 暂停音频传输（端到端模式：挂断/push-to-talk 松开）
  Future<void> pauseAudio(String agentId) =>
      _commandChannel.invokeMethod('pauseAudio', {'agentId': agentId});

  /// 恢复音频传输（端到端模式：恢复通话/push-to-talk 按住）
  Future<void> resumeAudio(String agentId) =>
      _commandChannel.invokeMethod('resumeAudio', {'agentId': agentId});

  /// 连接端到端服务（STS/AST WebSocket）
  Future<void> connectService(String agentId) =>
      _commandChannel.invokeMethod('connectService', {'agentId': agentId});

  /// 断开端到端服务
  Future<void> disconnectService(String agentId) =>
      _commandChannel.invokeMethod('disconnectService', {'agentId': agentId});

  /// 通知 App 前后台状态
  Future<void> notifyAppForeground(bool isForeground) =>
      _commandChannel.invokeMethod('notifyAppForeground', {
        'isForeground': isForeground,
      });

  /// 设置音频输出模式：earpiece / speaker / auto
  Future<void> setAudioOutputMode(String mode) =>
      _commandChannel.invokeMethod('setAudioOutputMode', {'mode': mode});
}
