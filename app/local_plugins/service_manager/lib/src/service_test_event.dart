// ── STT 测试事件 ────────────────────────────────────────────────

enum SttTestEventKind {
  listeningStarted,
  vadSpeechStart,
  vadSpeechEnd,
  partialResult,
  finalResult,
  listeningStopped,
  error,
}

// ── TTS 测试事件 ────────────────────────────────────────────────

enum TtsTestEventKind {
  synthesisStart,
  synthesisReady,
  playbackStart,
  playbackProgress,
  playbackDone,
  playbackInterrupted,
  error,
}

// ── LLM 测试事件 ────────────────────────────────────────────────

enum LlmTestEventKind {
  firstToken,
  textDelta,
  thinking,
  toolCallStart,
  toolCallArguments,
  toolCallResult,
  done,
  cancelled,
  error,
}

// ── Translation 测试事件 ─────────────────────────────────────────

enum TranslationTestEventKind {
  result,
  error,
}

// ── STS 测试事件 ────────────────────────────────────────────────

enum StsTestRole { user, bot }

enum StsTestEventKind {
  // 连接
  connected,
  disconnected,

  // 识别生命周期（对应 ai_plugin_interface StsEventType 同名事件）
  recognitionStart,
  recognizing,
  recognized,
  recognitionDone,
  recognitionEnd,
  recognitionError,

  // 合成
  synthesisStart,
  synthesizing,
  synthesized,
  synthesisEnd,
  synthesisError,

  // 播报
  playbackStart,
  playbackEnd,

  // 兼容：Android 原生 ServiceTestRunner 仍在下发的旧事件，后续迁移后可删除
  sttPartialResult,
  sttFinalResult,
  sentenceDone,
  speechStart,
  stateChanged,

  error,
}

// ── AST 测试事件 ────────────────────────────────────────────────

enum AstTestEventKind {
  connected,
  sourceSubtitle,
  translatedSubtitle,
  speechStart,
  stateChanged,
  disconnected,
  error,
}

// ── 统一事件基类 ────────────────────────────────────────────────

sealed class ServiceTestEvent {
  final String testId;
  const ServiceTestEvent({required this.testId});
}

final class SttTestEvent extends ServiceTestEvent {
  final SttTestEventKind kind;
  final String? text;
  final String? errorCode;
  final String? errorMessage;

  const SttTestEvent({
    required super.testId,
    required this.kind,
    this.text,
    this.errorCode,
    this.errorMessage,
  });
}

final class TtsTestEvent extends ServiceTestEvent {
  final TtsTestEventKind kind;
  final int? progressMs;
  final int? durationMs;
  final String? errorCode;
  final String? errorMessage;

  const TtsTestEvent({
    required super.testId,
    required this.kind,
    this.progressMs,
    this.durationMs,
    this.errorCode,
    this.errorMessage,
  });
}

final class LlmTestEvent extends ServiceTestEvent {
  final LlmTestEventKind kind;
  final String? textDelta;
  final String? thinkingDelta;
  final String? toolCallId;
  final String? toolName;
  final String? toolArgumentsDelta;
  final String? toolResult;
  final String? fullText;
  final String? errorCode;
  final String? errorMessage;

  const LlmTestEvent({
    required super.testId,
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

final class TranslationTestEvent extends ServiceTestEvent {
  final TranslationTestEventKind kind;
  final String? sourceText;
  final String? translatedText;
  final String? sourceLanguage;
  final String? targetLanguage;
  final String? errorCode;
  final String? errorMessage;

  const TranslationTestEvent({
    required super.testId,
    required this.kind,
    this.sourceText,
    this.translatedText,
    this.sourceLanguage,
    this.targetLanguage,
    this.errorCode,
    this.errorMessage,
  });
}

final class StsTestEvent extends ServiceTestEvent {
  final StsTestEventKind kind;
  final StsTestRole? role;
  final String? requestId;
  final String? text;
  final String? state;
  final bool interrupted;
  final String? errorCode;
  final String? errorMessage;

  const StsTestEvent({
    required super.testId,
    required this.kind,
    this.role,
    this.requestId,
    this.text,
    this.state,
    this.interrupted = false,
    this.errorCode,
    this.errorMessage,
  });
}

final class AstTestEvent extends ServiceTestEvent {
  final AstTestEventKind kind;
  final String? text;
  final String? state;
  final String? errorCode;
  final String? errorMessage;

  const AstTestEvent({
    required super.testId,
    required this.kind,
    this.text,
    this.state,
    this.errorCode,
    this.errorMessage,
  });
}

// ── 服务测试完成事件（通用） ──────────────────────────────────────

final class ServiceTestDoneEvent extends ServiceTestEvent {
  final bool success;
  final String? message;

  const ServiceTestDoneEvent({
    required super.testId,
    required this.success,
    this.message,
  });
}

// ─────────────────────────────────────────────────
// 解析工厂
// ─────────────────────────────────────────────────

ServiceTestEvent? parseServiceTestEvent(Map<Object?, Object?> raw) {
  final type = raw['type'] as String?;
  final testId = raw['testId'] as String? ?? '';

  switch (type) {
    case 'stt':
      return SttTestEvent(
        testId: testId,
        kind: _parseSttKind(raw['kind'] as String?),
        text: raw['text'] as String?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'tts':
      return TtsTestEvent(
        testId: testId,
        kind: _parseTtsKind(raw['kind'] as String?),
        progressMs: raw['progressMs'] as int?,
        durationMs: raw['durationMs'] as int?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'llm':
      return LlmTestEvent(
        testId: testId,
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
    case 'translation':
      return TranslationTestEvent(
        testId: testId,
        kind: _parseTranslationKind(raw['kind'] as String?),
        sourceText: raw['sourceText'] as String?,
        translatedText: raw['translatedText'] as String?,
        sourceLanguage: raw['sourceLanguage'] as String?,
        targetLanguage: raw['targetLanguage'] as String?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'sts':
      return StsTestEvent(
        testId: testId,
        kind: _parseStsKind(raw['kind'] as String?),
        role: _parseStsRole(raw['role'] as String?),
        requestId: raw['requestId'] as String?,
        text: raw['text'] as String?,
        state: raw['state'] as String?,
        interrupted: raw['interrupted'] as bool? ?? false,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'ast':
      return AstTestEvent(
        testId: testId,
        kind: _parseAstKind(raw['kind'] as String?),
        text: raw['text'] as String?,
        state: raw['state'] as String?,
        errorCode: raw['errorCode'] as String?,
        errorMessage: raw['errorMessage'] as String?,
      );
    case 'done':
      return ServiceTestDoneEvent(
        testId: testId,
        success: raw['success'] as bool? ?? false,
        message: raw['message'] as String?,
      );
    default:
      return null;
  }
}

SttTestEventKind _parseSttKind(String? s) => switch (s) {
      'listeningStarted' => SttTestEventKind.listeningStarted,
      'vadSpeechStart' => SttTestEventKind.vadSpeechStart,
      'vadSpeechEnd' => SttTestEventKind.vadSpeechEnd,
      'partialResult' => SttTestEventKind.partialResult,
      'finalResult' => SttTestEventKind.finalResult,
      'listeningStopped' => SttTestEventKind.listeningStopped,
      _ => SttTestEventKind.error,
    };

TtsTestEventKind _parseTtsKind(String? s) => switch (s) {
      'synthesisStart' => TtsTestEventKind.synthesisStart,
      'synthesisReady' => TtsTestEventKind.synthesisReady,
      'playbackStart' => TtsTestEventKind.playbackStart,
      'playbackProgress' => TtsTestEventKind.playbackProgress,
      'playbackDone' => TtsTestEventKind.playbackDone,
      'playbackInterrupted' => TtsTestEventKind.playbackInterrupted,
      _ => TtsTestEventKind.error,
    };

LlmTestEventKind _parseLlmKind(String? s) => switch (s) {
      'firstToken' => LlmTestEventKind.firstToken,
      'textDelta' => LlmTestEventKind.textDelta,
      'thinking' => LlmTestEventKind.thinking,
      'toolCallStart' => LlmTestEventKind.toolCallStart,
      'toolCallArguments' => LlmTestEventKind.toolCallArguments,
      'toolCallResult' => LlmTestEventKind.toolCallResult,
      'done' => LlmTestEventKind.done,
      'cancelled' => LlmTestEventKind.cancelled,
      _ => LlmTestEventKind.error,
    };

TranslationTestEventKind _parseTranslationKind(String? s) => switch (s) {
      'result' => TranslationTestEventKind.result,
      _ => TranslationTestEventKind.error,
    };

StsTestEventKind _parseStsKind(String? s) => switch (s) {
      'connected' => StsTestEventKind.connected,
      'disconnected' => StsTestEventKind.disconnected,
      'recognitionStart' => StsTestEventKind.recognitionStart,
      'recognizing' => StsTestEventKind.recognizing,
      'recognized' => StsTestEventKind.recognized,
      'recognitionDone' => StsTestEventKind.recognitionDone,
      'recognitionEnd' => StsTestEventKind.recognitionEnd,
      'recognitionError' => StsTestEventKind.recognitionError,
      'synthesisStart' => StsTestEventKind.synthesisStart,
      'synthesizing' => StsTestEventKind.synthesizing,
      'synthesized' => StsTestEventKind.synthesized,
      'synthesisEnd' => StsTestEventKind.synthesisEnd,
      'synthesisError' => StsTestEventKind.synthesisError,
      'playbackStart' => StsTestEventKind.playbackStart,
      'playbackEnd' => StsTestEventKind.playbackEnd,
      'sttPartialResult' => StsTestEventKind.sttPartialResult,
      'sttFinalResult' => StsTestEventKind.sttFinalResult,
      'sentenceDone' => StsTestEventKind.sentenceDone,
      'speechStart' => StsTestEventKind.speechStart,
      'stateChanged' => StsTestEventKind.stateChanged,
      _ => StsTestEventKind.error,
    };

StsTestRole? _parseStsRole(String? s) => switch (s) {
      'user' => StsTestRole.user,
      'bot' => StsTestRole.bot,
      _ => null,
    };

AstTestEventKind _parseAstKind(String? s) => switch (s) {
      'connected' => AstTestEventKind.connected,
      'sourceSubtitle' => AstTestEventKind.sourceSubtitle,
      'translatedSubtitle' => AstTestEventKind.translatedSubtitle,
      'speechStart' => AstTestEventKind.speechStart,
      'stateChanged' => AstTestEventKind.stateChanged,
      'disconnected' => AstTestEventKind.disconnected,
      _ => AstTestEventKind.error,
    };
