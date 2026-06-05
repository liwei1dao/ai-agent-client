import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import 'agent_event.dart';
import 'agents_server_api.dart';
import 'dart_agent_runtime.dart';
import 'desktop/desktop_service_factory.dart';

/// AgentsServerBridge — agents_server 的统一门面（default / 非 web 分支）。
///
/// 条件导入无法区分 mobile 与 desktop（都满足 `dart.library.io`），故在此用运行时
/// [defaultTargetPlatform] 选择后端：
/// - **移动端（Android / iOS）**：[_MethodChannelAgentsServer] —— Flutter→Native
///   命令走 MethodChannel，原生 agent 运行时执行管线。
/// - **桌面（macOS / Windows / Linux）**：[DartAgentRuntime] + [DesktopServiceFactory]
///   —— 纯 Dart 运行时（与 web 同一套编排），避免调用桌面侧不存在的
///   `agents_server/*` 原生 handler。
///
/// 公开 API 见 [AgentsServerApi]，与 web 分支 `agents_server_bridge_web.dart` 一致。
class AgentsServerBridge implements AgentsServerApi {
  static final AgentsServerBridge _instance = AgentsServerBridge._();
  AgentsServerBridge._() : _impl = _pickImpl();
  factory AgentsServerBridge() => _instance;

  final AgentsServerApi _impl;

  static AgentsServerApi _pickImpl() {
    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    return isDesktop
        ? DartAgentRuntime(const DesktopServiceFactory())
        : _MethodChannelAgentsServer();
  }

  @override
  Stream<AgentEvent> get eventStream => _impl.eventStream;

  @override
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
    String? mcpServersJson,
    Map<String, String> extraParams = const {},
  }) =>
      _impl.createAgent(
        agentId: agentId,
        agentType: agentType,
        inputMode: inputMode,
        sttVendor: sttVendor,
        ttsVendor: ttsVendor,
        llmVendor: llmVendor,
        stsVendor: stsVendor,
        astVendor: astVendor,
        translationVendor: translationVendor,
        sttConfigJson: sttConfigJson,
        ttsConfigJson: ttsConfigJson,
        llmConfigJson: llmConfigJson,
        stsConfigJson: stsConfigJson,
        astConfigJson: astConfigJson,
        translationConfigJson: translationConfigJson,
        mcpServersJson: mcpServersJson,
        extraParams: extraParams,
      );

  @override
  Future<void> stopAgent(String agentId) => _impl.stopAgent(agentId);

  @override
  Future<void> deleteAgent(String agentId) => _impl.deleteAgent(agentId);

  @override
  Future<void> sendText(String agentId, String requestId, String text) =>
      _impl.sendText(agentId, requestId, text);

  @override
  Future<void> setInputMode(String agentId, String mode) =>
      _impl.setInputMode(agentId, mode);

  @override
  Future<void> setAgentOption(String agentId, String key, String value) =>
      _impl.setAgentOption(agentId, key, value);

  @override
  Future<void> startListening(String agentId) => _impl.startListening(agentId);

  @override
  Future<void> stopListening(String agentId) => _impl.stopListening(agentId);

  @override
  Future<void> interrupt(String agentId) => _impl.interrupt(agentId);

  @override
  Future<void> pauseAudio(String agentId) => _impl.pauseAudio(agentId);

  @override
  Future<void> resumeAudio(String agentId) => _impl.resumeAudio(agentId);

  @override
  Future<void> connectService(String agentId) => _impl.connectService(agentId);

  @override
  Future<void> disconnectService(String agentId) =>
      _impl.disconnectService(agentId);

  @override
  Future<void> notifyAppForeground(bool isForeground) =>
      _impl.notifyAppForeground(isForeground);

  @override
  Future<void> setAudioOutputMode(String mode) =>
      _impl.setAudioOutputMode(mode);
}

/// 移动端实现：所有 Flutter→Native 命令通过 MethodChannel 发出，
/// Native→Flutter 事件通过 [eventStream] 接收。
class _MethodChannelAgentsServer implements AgentsServerApi {
  static const _commandChannel = MethodChannel('agents_server/commands');
  static const _eventChannel = EventChannel('agents_server/events');

  Stream<AgentEvent>? _eventStream;

  @override
  Stream<AgentEvent> get eventStream {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) => parseAgentEvent(raw as Map<Object?, Object?>))
        .where((e) => e != null)
        .cast<AgentEvent>();
    return _eventStream!;
  }

  @override
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
    String? mcpServersJson,
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
        'mcpServersJson': mcpServersJson,
        'extraParams': extraParams,
      });

  @override
  Future<void> stopAgent(String agentId) =>
      _commandChannel.invokeMethod('stopAgent', {'agentId': agentId});

  @override
  Future<void> deleteAgent(String agentId) =>
      _commandChannel.invokeMethod('deleteAgent', {'agentId': agentId});

  @override
  Future<void> sendText(String agentId, String requestId, String text) =>
      _commandChannel.invokeMethod('sendText', {
        'agentId': agentId,
        'requestId': requestId,
        'text': text,
      });

  @override
  Future<void> setInputMode(String agentId, String mode) =>
      _commandChannel.invokeMethod('setInputMode', {
        'agentId': agentId,
        'mode': mode,
      });

  @override
  Future<void> setAgentOption(String agentId, String key, String value) =>
      _commandChannel.invokeMethod('setAgentOption', {
        'agentId': agentId,
        'key': key,
        'value': value,
      });

  @override
  Future<void> startListening(String agentId) =>
      _commandChannel.invokeMethod('startListening', {'agentId': agentId});

  @override
  Future<void> stopListening(String agentId) =>
      _commandChannel.invokeMethod('stopListening', {'agentId': agentId});

  @override
  Future<void> interrupt(String agentId) =>
      _commandChannel.invokeMethod('interrupt', {'agentId': agentId});

  @override
  Future<void> pauseAudio(String agentId) =>
      _commandChannel.invokeMethod('pauseAudio', {'agentId': agentId});

  @override
  Future<void> resumeAudio(String agentId) =>
      _commandChannel.invokeMethod('resumeAudio', {'agentId': agentId});

  @override
  Future<void> connectService(String agentId) =>
      _commandChannel.invokeMethod('connectService', {'agentId': agentId});

  @override
  Future<void> disconnectService(String agentId) =>
      _commandChannel.invokeMethod('disconnectService', {'agentId': agentId});

  @override
  Future<void> notifyAppForeground(bool isForeground) =>
      _commandChannel.invokeMethod('notifyAppForeground', {
        'isForeground': isForeground,
      });

  @override
  Future<void> setAudioOutputMode(String mode) =>
      _commandChannel.invokeMethod('setAudioOutputMode', {'mode': mode});
}
