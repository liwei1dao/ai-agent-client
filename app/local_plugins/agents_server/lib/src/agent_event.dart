// Dart 侧 Agent 事件镜像（与 Native 推送的 Map 结构对应）
// 从原 agent_runtime/agent_event.dart 演进

enum AgentSessionState {
  idle,
  listening,
  stt,
  llm,
  tts,
  playing,
  error,
}

enum SttEventKind {
  listeningStarted,
  vadSpeechStart,
  vadSpeechEnd,
  partialResult,
  finalResult,
  listeningStopped,
  error,
}

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

enum TtsEventKind {
  synthesisStart,
  synthesisReady,
  playbackStart,
  playbackProgress,
  playbackDone,
  playbackInterrupted,
  error,
}

sealed class AgentEvent {
  final String sessionId;
  const AgentEvent({required this.sessionId});
}

final class SttEvent extends AgentEvent {
  final String requestId;
  final SttEventKind kind;
  final String? text;
  final String? errorCode;
  final String? errorMessage;

  const SttEvent({
    required super.sessionId,
    required this.requestId,
    required this.kind,
    this.text,
    this.errorCode,
    this.errorMessage,
  });
}

final class LlmEvent extends AgentEvent {
  final String requestId;
  final LlmEventKind kind;
  final String? textDelta;
  final String? thinkingDelta;
  final String? toolCallId;
  final String? toolName;
  final String? toolArgumentsDelta;
  final String? toolResult;
  final String? fullText;
  final String? errorCode;
  final String? errorMessage;

  const LlmEvent({
    required super.sessionId,
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
}

final class TtsEvent extends AgentEvent {
  final String requestId;
  final TtsEventKind kind;
  final int? progressMs;
  final int? durationMs;
  final String? errorCode;
  final String? errorMessage;

  const TtsEvent({
    required super.sessionId,
    required this.requestId,
    required this.kind,
    this.progressMs,
    this.durationMs,
    this.errorCode,
    this.errorMessage,
  });
}

final class SessionStateEvent extends AgentEvent {
  final AgentSessionState state;
  final String? requestId;

  const SessionStateEvent({
    required super.sessionId,
    required this.state,
    this.requestId,
  });
}

final class AgentErrorEvent extends AgentEvent {
  final String errorCode;
  final String message;
  final String? requestId;

  const AgentErrorEvent({
    required super.sessionId,
    required this.errorCode,
    required this.message,
    this.requestId,
  });
}

enum ServiceConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

final class ServiceConnectionStateEvent extends AgentEvent {
  final ServiceConnectionState connectionState;
  final String? errorMessage;

  const ServiceConnectionStateEvent({
    required super.sessionId,
    required this.connectionState,
    this.errorMessage,
  });
}

// ─────────────────────────────────────────────────
// 解析工厂
// ─────────────────────────────────────────────────

AgentEvent? parseAgentEvent(Map<Object?, Object?> raw) {
  final type = raw['type'] as String?;
  final sessionId = raw['sessionId'] as String? ?? '';

  switch (type) {
    case 'stt':
      return SttEvent(
        sessionId: sessionId,
        requestId: raw['requestId'] as String? ?? '',
        kind: _parseSttKind(raw['kind'] as String?),
        text: raw['text'] as String?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'llm':
      return LlmEvent(
        sessionId: sessionId,
        requestId: raw['requestId'] as String? ?? '',
        kind: _parseLlmKind(raw['kind'] as String?),
        textDelta: raw['textDelta'] as String?,
        thinkingDelta: raw['thinkingDelta'] as String?,
        toolCallId: raw['toolCallId'] as String?,
        toolName: raw['toolName'] as String?,
        toolArgumentsDelta: raw['toolArgumentsDelta'] as String?,
        toolResult: raw['toolResult'] as String?,
        fullText: raw['fullText'] as String?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'tts':
      return TtsEvent(
        sessionId: sessionId,
        requestId: raw['requestId'] as String? ?? '',
        kind: _parseTtsKind(raw['kind'] as String?),
        progressMs: raw['progressMs'] as int?,
        durationMs: raw['durationMs'] as int?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'stateChanged':
      return SessionStateEvent(
        sessionId: sessionId,
        state: _parseState(raw['state'] as String?),
        requestId: raw['requestId'] as String?,
      );
    case 'error':
      return AgentErrorEvent(
        sessionId: sessionId,
        errorCode: raw['errorCode'] as String? ?? 'unknown',
        message: raw['message'] as String? ?? '',
        requestId: raw['requestId'] as String?,
      );
    case 'connectionState':
      return ServiceConnectionStateEvent(
        sessionId: sessionId,
        connectionState: _parseServiceConnectionState(raw['state'] as String?),
        errorMessage: raw['errorMessage'] as String?,
      );
    default:
      return null;
  }
}

SttEventKind _parseSttKind(String? s) => switch (s) {
      'listeningStarted' => SttEventKind.listeningStarted,
      'vadSpeechStart' => SttEventKind.vadSpeechStart,
      'vadSpeechEnd' => SttEventKind.vadSpeechEnd,
      'partialResult' => SttEventKind.partialResult,
      'finalResult' => SttEventKind.finalResult,
      'listeningStopped' => SttEventKind.listeningStopped,
      _ => SttEventKind.error,
    };

LlmEventKind _parseLlmKind(String? s) => switch (s) {
      'thinking' => LlmEventKind.thinking,
      'firstToken' => LlmEventKind.firstToken,
      'toolCallStart' => LlmEventKind.toolCallStart,
      'toolCallArguments' => LlmEventKind.toolCallArguments,
      'toolCallResult' => LlmEventKind.toolCallResult,
      'done' => LlmEventKind.done,
      'cancelled' => LlmEventKind.cancelled,
      _ => LlmEventKind.error,
    };

TtsEventKind _parseTtsKind(String? s) => switch (s) {
      'synthesisStart' => TtsEventKind.synthesisStart,
      'synthesisReady' => TtsEventKind.synthesisReady,
      'playbackStart' => TtsEventKind.playbackStart,
      'playbackProgress' => TtsEventKind.playbackProgress,
      'playbackDone' => TtsEventKind.playbackDone,
      'playbackInterrupted' => TtsEventKind.playbackInterrupted,
      _ => TtsEventKind.error,
    };

ServiceConnectionState _parseServiceConnectionState(String? s) => switch (s) {
      'connecting' => ServiceConnectionState.connecting,
      'connected' => ServiceConnectionState.connected,
      'error' => ServiceConnectionState.error,
      _ => ServiceConnectionState.disconnected,
    };

AgentSessionState _parseState(String? s) => switch (s) {
      'listening' => AgentSessionState.listening,
      'stt' => AgentSessionState.stt,
      'llm' => AgentSessionState.llm,
      'tts' => AgentSessionState.tts,
      'playing' => AgentSessionState.playing,
      'error' => AgentSessionState.error,
      _ => AgentSessionState.idle,
    };
