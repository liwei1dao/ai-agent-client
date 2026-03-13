// ignore_for_file: avoid_classes_with_only_static_members
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/agent_runtime_api.g.dart',
    kotlinOut:
        'android/src/main/kotlin/com/aiagent/agent_runtime/AgentRuntimeApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.aiagent.agent_runtime'),
    swiftOut: 'ios/Classes/AgentRuntimeApi.g.swift',
    dartPackageName: 'agent_runtime',
  ),
)

// ─────────────────────────────────────────────────
// 数据类
// ─────────────────────────────────────────────────

class AgentSessionConfig {
  AgentSessionConfig({
    required this.sessionId,
    required this.agentId,
    required this.inputMode, // 'text' | 'short_voice' | 'call'
    required this.sttPluginName,
    required this.ttsPluginName,
    required this.llmPluginName,
    this.stsPluginName,
    required this.sttConfigJson,
    required this.ttsConfigJson,
    required this.llmConfigJson,
    this.stsConfigJson,
  });

  late String sessionId;
  late String agentId;
  late String inputMode;
  late String sttPluginName;
  late String ttsPluginName;
  late String llmPluginName;
  late String? stsPluginName;
  late String sttConfigJson;
  late String ttsConfigJson;
  late String llmConfigJson;
  late String? stsConfigJson;
}

// ── STT 事件 ──────────────────────────────────────

/// STT 事件类型
enum SttEventKind {
  listeningStarted,
  vadSpeechStart,
  vadSpeechEnd,
  partialResult,
  finalResult,
  listeningStopped,
  error,
}

class SttEventMessage {
  SttEventMessage({
    required this.sessionId,
    required this.requestId,
    required this.kind,
    this.text,
    this.errorCode,
    this.errorMessage,
  });

  late String sessionId;

  /// 短语音/通话模式：由原生 STT 层在 finalResult 时生成；文本模式无 STT 事件
  late String requestId;
  late SttEventKind kind;
  late String? text;
  late String? errorCode;
  late String? errorMessage;
}

// ── LLM 事件 ──────────────────────────────────────

enum LlmEventKind {
  thinking,
  firstToken,
  toolCallStart,
  toolCallArguments,
  toolCallResult,
  done,
  cancelled,
  error,
}

class LlmEventMessage {
  LlmEventMessage({
    required this.sessionId,
    required this.requestId,
    required this.kind,
    this.textDelta,
    this.thinkingDelta,
    this.toolCallId,
    this.toolName,
    this.toolArgumentsDelta,
    this.toolResult,
    this.fullText,
    this.errorCode,
    this.errorMessage,
  });

  late String sessionId;
  late String requestId;
  late LlmEventKind kind;
  late String? textDelta;
  late String? thinkingDelta;
  late String? toolCallId;
  late String? toolName;
  late String? toolArgumentsDelta;
  late String? toolResult;
  late String? fullText;
  late String? errorCode;
  late String? errorMessage;
}

// ── TTS 事件 ──────────────────────────────────────

enum TtsEventKind {
  synthesisStart,
  synthesisReady,
  playbackStart,
  playbackProgress,
  playbackDone,
  playbackInterrupted,
  error,
}

class TtsEventMessage {
  TtsEventMessage({
    required this.sessionId,
    required this.requestId,
    required this.kind,
    this.progressMs,
    this.durationMs,
    this.errorCode,
    this.errorMessage,
  });

  late String sessionId;
  late String requestId;
  late TtsEventKind kind;
  late int? progressMs;
  late int? durationMs;
  late String? errorCode;
  late String? errorMessage;
}

// ── 会话状态 ──────────────────────────────────────

enum AgentSessionState {
  idle,
  listening,
  stt,
  llm,
  tts,
  playing,
  error,
}

class SessionStateMessage {
  SessionStateMessage({
    required this.sessionId,
    required this.state,
    this.requestId,
  });

  late String sessionId;
  late AgentSessionState state;
  late String? requestId;
}

class ErrorMessage {
  ErrorMessage({
    required this.sessionId,
    required this.errorCode,
    required this.message,
    this.requestId,
  });

  late String sessionId;
  late String errorCode;
  late String message;
  late String? requestId;
}

// ─────────────────────────────────────────────────
// 命令接口（Flutter → Native）
// ─────────────────────────────────────────────────

@HostApi()
abstract class AgentRuntimeApi {
  /// 启动一个 AgentSession（开启后台 Service）
  void startSession(AgentSessionConfig config);

  /// 停止并销毁 AgentSession
  void stopSession(String sessionId);

  /// 文本模式发送输入（requestId 由 Flutter 生成）
  void sendText(String sessionId, String requestId, String text);

  /// 打断当前 LLM/TTS（最新输入抢占，短语音/通话模式由 STT 自动触发）
  void interrupt(String sessionId);

  /// 切换输入模式（text / short_voice / call）
  void setInputMode(String sessionId, String mode);

  /// App 前/后台切换通知
  void notifyAppForeground(bool isForeground);
}

// ─────────────────────────────────────────────────
// 事件接口（Native → Flutter）
// ─────────────────────────────────────────────────

@FlutterApi()
abstract class AgentRuntimeEventApi {
  void onSttEvent(SttEventMessage event);
  void onLlmEvent(LlmEventMessage event);
  void onTtsEvent(TtsEventMessage event);
  void onStateChanged(SessionStateMessage state);
  void onError(ErrorMessage error);
}
