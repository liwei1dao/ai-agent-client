import 'dart:async';
import 'package:flutter/services.dart';
import 'service_test_event.dart';

/// ServiceManagerBridge — 服务管理插件的 Dart 薄桥接
///
/// 职责：
/// 1. 服务测试：传入 serviceId，底层从 DB 加载配置 → 通过 NativeServiceRegistry
///    创建对应服务实例 → 执行测试 → 通过 EventChannel 推送标准化事件
/// 2. 服务测试生命周期管理（启动/停止/释放）
///
/// Flutter UI 只需要：选择服务 → 调用 testXxx → 监听 eventStream
class ServiceManagerBridge {
  static const _commandChannel = MethodChannel('service_manager/commands');
  static const _eventChannel = EventChannel('service_manager/events');

  static final ServiceManagerBridge _instance = ServiceManagerBridge._();
  ServiceManagerBridge._();
  factory ServiceManagerBridge() => _instance;

  Stream<ServiceTestEvent>? _eventStream;

  /// 服务测试事件流（广播流，可多处监听）
  Stream<ServiceTestEvent> get eventStream {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) => parseServiceTestEvent(raw as Map<Object?, Object?>))
        .where((e) => e != null)
        .cast<ServiceTestEvent>();
    return _eventStream!;
  }

  // ─────────────────────────────────────────────────
  // STT 测试
  // ─────────────────────────────────────────────────

  /// 启动 STT 测试（底层自动加载 serviceId 对应的配置）
  Future<void> testSttStart({
    required String testId,
    required String serviceId,
  }) =>
      _commandChannel.invokeMethod('testSttStart', {
        'testId': testId,
        'serviceId': serviceId,
      });

  /// 停止 STT 测试
  Future<void> testSttStop(String testId) =>
      _commandChannel.invokeMethod('testSttStop', {'testId': testId});

  // ─────────────────────────────────────────────────
  // TTS 测试
  // ─────────────────────────────────────────────────

  /// 启动 TTS 测试
  Future<void> testTtsSpeak({
    required String testId,
    required String serviceId,
    required String text,
    String? voiceName,
    double speed = 1.0,
    double pitch = 1.0,
  }) =>
      _commandChannel.invokeMethod('testTtsSpeak', {
        'testId': testId,
        'serviceId': serviceId,
        'text': text,
        'voiceName': voiceName,
        'speed': speed,
        'pitch': pitch,
      });

  /// 停止 TTS 测试
  Future<void> testTtsStop(String testId) =>
      _commandChannel.invokeMethod('testTtsStop', {'testId': testId});

  // ─────────────────────────────────────────────────
  // LLM 测试
  // ─────────────────────────────────────────────────

  /// 发送 LLM 测试请求
  Future<void> testLlmChat({
    required String testId,
    required String serviceId,
    required String text,
  }) =>
      _commandChannel.invokeMethod('testLlmChat', {
        'testId': testId,
        'serviceId': serviceId,
        'text': text,
      });

  /// 取消 LLM 测试
  Future<void> testLlmCancel(String testId) =>
      _commandChannel.invokeMethod('testLlmCancel', {'testId': testId});

  // ─────────────────────────────────────────────────
  // Translation 测试
  // ─────────────────────────────────────────────────

  /// 翻译测试
  Future<void> testTranslate({
    required String testId,
    required String serviceId,
    required String text,
    required String targetLang,
    String? sourceLang,
  }) =>
      _commandChannel.invokeMethod('testTranslate', {
        'testId': testId,
        'serviceId': serviceId,
        'text': text,
        'targetLang': targetLang,
        'sourceLang': sourceLang,
      });

  // ─────────────────────────────────────────────────
  // STS 测试
  // ─────────────────────────────────────────────────

  /// 连接 STS 测试
  Future<void> testStsConnect({
    required String testId,
    required String serviceId,
  }) =>
      _commandChannel.invokeMethod('testStsConnect', {
        'testId': testId,
        'serviceId': serviceId,
      });

  /// 开始 STS 音频发送
  Future<void> testStsStartAudio(String testId) =>
      _commandChannel.invokeMethod('testStsStartAudio', {'testId': testId});

  /// 停止 STS 音频发送
  Future<void> testStsStopAudio(String testId) =>
      _commandChannel.invokeMethod('testStsStopAudio', {'testId': testId});

  /// 断开 STS 测试
  Future<void> testStsDisconnect(String testId) =>
      _commandChannel.invokeMethod('testStsDisconnect', {'testId': testId});

  // ─────────────────────────────────────────────────
  // AST 测试
  // ─────────────────────────────────────────────────

  /// 连接 AST 测试
  ///
  /// [extraConfigJson] 可选；JSON 对象字符串，会**覆盖式**合并到从 DB 加载的
  /// service config 之上（用于测试面板临时覆盖 srcLang / dstLang / agentId 等）。
  Future<void> testAstConnect({
    required String testId,
    required String serviceId,
    String? extraConfigJson,
  }) =>
      _commandChannel.invokeMethod('testAstConnect', {
        'testId': testId,
        'serviceId': serviceId,
        if (extraConfigJson != null) 'extraConfigJson': extraConfigJson,
      });

  /// 开始 AST 音频发送
  Future<void> testAstStartAudio(String testId) =>
      _commandChannel.invokeMethod('testAstStartAudio', {'testId': testId});

  /// 停止 AST 音频发送
  Future<void> testAstStopAudio(String testId) =>
      _commandChannel.invokeMethod('testAstStopAudio', {'testId': testId});

  /// 断开 AST 测试
  Future<void> testAstDisconnect(String testId) =>
      _commandChannel.invokeMethod('testAstDisconnect', {'testId': testId});

  // ─────────────────────────────────────────────────
  // 自动化测试
  // ─────────────────────────────────────────────────

  /// 一键自动化测试：传入 serviceId，底层根据服务类型自动执行完整测试流程。
  ///
  /// - STT:  打开麦克风 → 录 5 秒 → 停止 → 检查识别结果
  /// - TTS:  合成预设文本 → 等待播放完成
  /// - LLM:  发送预设问题 → 等待回复
  /// - Translation: 翻译预设文本 → 等待结果
  /// - STS:  连接 → 通话 5 秒 → 断开
  /// - AST:  连接 → 通话 5 秒 → 断开
  ///
  /// 测试过程中推送中间事件，最终推送 [ServiceTestDoneEvent]。
  Future<void> autoTest({
    required String testId,
    required String serviceId,
  }) =>
      _commandChannel.invokeMethod('autoTest', {
        'testId': testId,
        'serviceId': serviceId,
      });

  // ─────────────────────────────────────────────────
  // 通用
  // ─────────────────────────────────────────────────

  /// 释放指定测试会话的所有资源
  Future<void> releaseTest(String testId) =>
      _commandChannel.invokeMethod('releaseTest', {'testId': testId});
}
