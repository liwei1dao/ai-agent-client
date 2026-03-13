import Foundation

/// SttPipelineNode — iOS STT 管线节点，推送 7 种 STT 事件
///
/// 短语音/通话模式：在 isFinal=true 时由本节点生成 requestId（UUID），
/// 然后回调 onFinalResult 触发 AgentSession.onUserInput
class SttPipelineNode {
    let sessionId: String
    let config: AgentSessionConfig
    let db: AppDatabase
    weak var eventSink: AgentEventSink?
    let onFinalResult: (String, String) -> Void  // (requestId, text)

    private var isListening = false

    init(
        sessionId: String,
        config: AgentSessionConfig,
        db: AppDatabase,
        eventSink: AgentEventSink,
        onFinalResult: @escaping (String, String) -> Void
    ) {
        self.sessionId = sessionId
        self.config = config
        self.db = db
        self.eventSink = eventSink
        self.onFinalResult = onFinalResult
    }

    func startListening() async {
        isListening = true
        pushEvent(SttEventData(sessionId: sessionId, requestId: "", kind: "listeningStarted"))
        // TODO: 启动 STT 插件
    }

    func stopListening() async {
        isListening = false
        pushEvent(SttEventData(sessionId: sessionId, requestId: "", kind: "listeningStopped"))
        // TODO: 停止 STT 插件
    }

    /// STT SDK 回调（在 SDK 回调线程调用）
    func onSttRawEvent(kind: String, text: String?, isFinal: Bool) {
        switch kind {
        case "vadSpeechStart":
            pushEvent(SttEventData(sessionId: sessionId, requestId: "", kind: "vadSpeechStart"))
        case "vadSpeechEnd":
            pushEvent(SttEventData(sessionId: sessionId, requestId: "", kind: "vadSpeechEnd"))
        case "partial":
            pushEvent(SttEventData(sessionId: sessionId, requestId: "", kind: "partialResult", text: text))
        case "final":
            guard let text = text, !text.isEmpty else { return }
            // ★ 短语音/通话模式：由原生 STT 层生成 requestId
            let requestId = UUID().uuidString
            pushEvent(SttEventData(sessionId: sessionId, requestId: requestId, kind: "finalResult", text: text))
            onFinalResult(requestId, text)
        case "error":
            pushEvent(SttEventData(sessionId: sessionId, requestId: "", kind: "error",
                                   errorCode: "stt_error", errorMessage: text))
        default: break
        }
    }

    private func pushEvent(_ event: SttEventData) {
        eventSink?.onSttEvent(event)
    }
}
