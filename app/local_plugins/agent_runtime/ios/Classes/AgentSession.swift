import Foundation

/// AgentSession — iOS 会话状态机（Swift actor 保证线程安全）
///
/// requestId 生成策略：
///   - 文本模式：由 Flutter 生成，通过 sendText() 传入
///   - 短语音/通话模式：由 SttPipelineNode 在 isFinal=true 时生成 UUID
actor AgentSession {

    enum State: String {
        case idle, listening, stt, llm, tts, playing, error
    }

    let sessionId: String
    let config: AgentSessionConfig
    let db: AppDatabase
    let eventSink: AgentEventSink

    private(set) var state: State = .idle
    private(set) var activeRequestId: String? = nil

    private var activeTask: Task<Void, Never>?

    // Pipeline 节点
    private lazy var vadEngine = VadEngine(sessionId: sessionId, eventSink: eventSink)
    private lazy var sttNode = SttPipelineNode(
        sessionId: sessionId,
        config: config,
        db: db,
        eventSink: eventSink,
        onFinalResult: { [weak self] reqId, text in
            Task { await self?.onUserInput(requestId: reqId, text: text) }
        }
    )
    private lazy var llmNode = LlmPipelineNode(sessionId: sessionId, config: config, db: db, eventSink: eventSink)
    private lazy var ttsNode = TtsPipelineNode(sessionId: sessionId, config: config, eventSink: eventSink)

    init(sessionId: String, config: AgentSessionConfig, db: AppDatabase, eventSink: AgentEventSink) {
        self.sessionId = sessionId
        self.config = config
        self.db = db
        self.eventSink = eventSink
    }

    // ─────────────────────────────────────────────────
    // 公开命令
    // ─────────────────────────────────────────────────

    /// 文本模式：Flutter 生成 requestId
    func sendText(requestId: String, text: String) {
        Task { await onUserInput(requestId: requestId, text: text) }
    }

    func interrupt() {
        cancelActiveTask(reason: "manual_interrupt")
        transitionTo(.idle)
    }

    func setInputMode(_ mode: String) {
        switch mode {
        case "call": startContinuousListening()
        case "short_voice": break // 按钮控制
        default: Task { await sttNode.stopListening() }
        }
    }

    func startListening() {
        transitionTo(.listening)
        Task { await sttNode.startListening() }
    }

    func stopListening() {
        Task { await sttNode.stopListening() }
    }

    func release() {
        cancelActiveTask(reason: "release")
    }

    // ─────────────────────────────────────────────────
    // 内部：用户输入触发 LLM 管线
    // ─────────────────────────────────────────────────

    private func onUserInput(requestId: String, text: String) async {
        let previousId = activeRequestId
        cancelActiveTask(reason: "new_input")
        activeRequestId = requestId

        activeTask = Task {
            // 标记旧消息为 cancelled
            if let prevId = previousId {
                try? db.updateMessageStatus(id: prevId, status: "cancelled")
            }

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            // 写入用户消息
            try? db.insertMessage(MessageRecord(
                id: requestId, agentId: config.agentId, role: "user",
                content: text, status: "done", createdAt: now, updatedAt: now
            ))

            // 写入占位 assistant 消息
            let assistantId = UUID().uuidString
            try? db.insertMessage(MessageRecord(
                id: assistantId, agentId: config.agentId, role: "assistant",
                content: "", status: "pending", createdAt: now + 1, updatedAt: now + 1
            ))

            guard !Task.isCancelled else { return }

            transitionTo(.llm)
            let llmText = await llmNode.run(requestId: requestId, assistantMessageId: assistantId, userText: text)

            guard !Task.isCancelled && activeRequestId == requestId else { return }

            transitionTo(.tts)
            await ttsNode.speak(requestId: requestId, text: llmText)

            guard !Task.isCancelled && activeRequestId == requestId else { return }

            transitionTo(.idle)
            if config.inputMode == "call" { startContinuousListening() }
        }
    }

    private func cancelActiveTask(reason: String) {
        activeTask?.cancel()
        activeTask = nil
    }

    private func startContinuousListening() {
        transitionTo(.listening)
        Task { await sttNode.startListening() }
    }

    private func transitionTo(_ newState: State) {
        state = newState
        eventSink.onStateChanged(sessionId: sessionId, state: newState.rawValue, requestId: activeRequestId)
    }
}

// ─────────────────────────────────────────────────
// 配置 & 事件协议
// ─────────────────────────────────────────────────

struct AgentSessionConfig {
    let sessionId: String
    let agentId: String
    let inputMode: String
    let sttPluginName: String
    let ttsPluginName: String
    let llmPluginName: String
    let stsPluginName: String?
    let sttConfigJson: String
    let ttsConfigJson: String
    let llmConfigJson: String
    let stsConfigJson: String?
}

protocol AgentEventSink: AnyObject {
    func onSttEvent(_ event: SttEventData)
    func onLlmEvent(_ event: LlmEventData)
    func onTtsEvent(_ event: TtsEventData)
    func onStateChanged(sessionId: String, state: String, requestId: String?)
    func onError(sessionId: String, errorCode: String, message: String, requestId: String?)
}

struct SttEventData {
    let sessionId: String; let requestId: String; let kind: String
    var text: String? = nil; var errorCode: String? = nil; var errorMessage: String? = nil
}

struct LlmEventData {
    let sessionId: String; let requestId: String; let kind: String
    var textDelta: String? = nil; var thinkingDelta: String? = nil
    var toolCallId: String? = nil; var toolName: String? = nil
    var toolArgumentsDelta: String? = nil; var toolResult: String? = nil
    var fullText: String? = nil; var errorCode: String? = nil; var errorMessage: String? = nil
}

struct TtsEventData {
    let sessionId: String; let requestId: String; let kind: String
    var progressMs: Int? = nil; var durationMs: Int? = nil
    var errorCode: String? = nil; var errorMessage: String? = nil
}
