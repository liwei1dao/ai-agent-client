import Foundation

/// STT event payload propagated from a vendor service to the agent layer
/// and on to Flutter via the AgentsServer event channel.
public struct SttEventData {
    public let sessionId: String
    public let requestId: String
    /// listeningStarted | vadSpeechStart | vadSpeechEnd |
    /// partialResult | finalResult | listeningStopped | error
    public let kind: String
    public let text: String?
    /// BCP-47 language tag, only set when the vendor advertises language detection.
    public let detectedLang: String?
    public let errorCode: String?
    public let errorMessage: String?

    public init(
        sessionId: String,
        requestId: String,
        kind: String,
        text: String? = nil,
        detectedLang: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.sessionId = sessionId
        self.requestId = requestId
        self.kind = kind
        self.text = text
        self.detectedLang = detectedLang
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

/// LLM event payload (streaming text + tool calls).
public struct LlmEventData {
    public let sessionId: String
    public let requestId: String
    /// thinking | firstToken | toolCallStart | toolCallArguments |
    /// toolCallResult | done | cancelled | error
    public let kind: String
    public let textDelta: String?
    public let thinkingDelta: String?
    public let toolCallId: String?
    public let toolName: String?
    public let toolArgumentsDelta: String?
    public let toolResult: String?
    public let fullText: String?
    public let errorCode: String?
    public let errorMessage: String?

    public init(
        sessionId: String,
        requestId: String,
        kind: String,
        textDelta: String? = nil,
        thinkingDelta: String? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        toolArgumentsDelta: String? = nil,
        toolResult: String? = nil,
        fullText: String? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.sessionId = sessionId
        self.requestId = requestId
        self.kind = kind
        self.textDelta = textDelta
        self.thinkingDelta = thinkingDelta
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.toolArgumentsDelta = toolArgumentsDelta
        self.toolResult = toolResult
        self.fullText = fullText
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

/// TTS event payload.
public struct TtsEventData {
    public let sessionId: String
    public let requestId: String
    /// synthesisStart | synthesisReady | playbackStart |
    /// playbackProgress | playbackDone | playbackInterrupted | error
    public let kind: String
    public let progressMs: Int?
    public let durationMs: Int?
    public let errorCode: String?
    public let errorMessage: String?

    public init(
        sessionId: String,
        requestId: String,
        kind: String,
        progressMs: Int? = nil,
        durationMs: Int? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil
    ) {
        self.sessionId = sessionId
        self.requestId = requestId
        self.kind = kind
        self.progressMs = progressMs
        self.durationMs = durationMs
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
}

/// Result of a one-shot translation request.
public struct NativeTranslationResult {
    public let sourceText: String
    public let translatedText: String
    public let sourceLanguage: String
    public let targetLanguage: String

    public init(sourceText: String, translatedText: String, sourceLanguage: String, targetLanguage: String) {
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }
}
