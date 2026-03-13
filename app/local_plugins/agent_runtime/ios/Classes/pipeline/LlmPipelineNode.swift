import Foundation

/// LlmPipelineNode — iOS LLM 管线节点（URLSession SSE 流式），推送 8 种 LLM 事件
class LlmPipelineNode: NSObject {
    let sessionId: String
    let config: AgentSessionConfig
    let db: AppDatabase
    weak var eventSink: AgentEventSink?

    private var activeDataTask: URLSessionDataTask?

    init(sessionId: String, config: AgentSessionConfig, db: AppDatabase, eventSink: AgentEventSink) {
        self.sessionId = sessionId
        self.config = config
        self.db = db
        self.eventSink = eventSink
    }

    /// 执行 LLM 推理（async/await，支持 Task.isCancelled 打断）
    func run(requestId: String, assistantMessageId: String, userText: String) async -> String {
        guard let llmConfig = try? JSONSerialization.jsonObject(with: config.llmConfigJson.data(using: .utf8)!) as? [String: Any],
              let apiKey = llmConfig["apiKey"] as? String,
              let baseUrl = llmConfig["baseUrl"] as? String,
              let model = llmConfig["model"] as? String else {
            return ""
        }

        // 读取历史消息
        let history = (try? db.getMessages(agentId: config.agentId, limit: 20))?.reversed() ?? []
        let messages = history.map { ["role": $0.role, "content": $0.content] }

        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages,
        ]

        guard let url = URL(string: baseUrl.trimmingCharacters(in: .init(charactersIn: "/")) + "/chat/completions"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return ""
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        try? db.updateMessageStatus(id: assistantMessageId, status: "streaming")

        let fullText = NSMutableString()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let session = URLSession(configuration: .default)
                var buffer = ""

                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        if (error as NSError).code == NSURLErrorCancelled {
                            try? self.db.updateMessageStatus(id: assistantMessageId, status: "cancelled")
                            self.pushLlmEvent(LlmEventData(sessionId: self.sessionId, requestId: requestId, kind: "cancelled"))
                        } else {
                            try? self.db.updateMessageStatus(id: assistantMessageId, status: "error")
                            self.pushLlmEvent(LlmEventData(sessionId: self.sessionId, requestId: requestId,
                                                            kind: "error", errorCode: "io_error", errorMessage: error.localizedDescription))
                        }
                        continuation.resume(returning: fullText as String)
                        return
                    }

                    guard let data = data, let text = String(data: data, encoding: .utf8) else {
                        continuation.resume(returning: fullText as String)
                        return
                    }

                    buffer += text
                    let lines = buffer.components(separatedBy: "\n")
                    buffer = lines.last ?? ""

                    for line in lines.dropLast() {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        if jsonStr == "[DONE]" {
                            try? self.db.updateMessageStatus(id: assistantMessageId, status: "done")
                            self.pushLlmEvent(LlmEventData(sessionId: self.sessionId, requestId: requestId,
                                                            kind: "done", fullText: fullText as String))
                            continuation.resume(returning: fullText as String)
                            return
                        }
                        if let delta = self.parseTextDelta(jsonStr) {
                            fullText.append(delta)
                            try? self.db.appendMessageContent(id: assistantMessageId, delta: delta)
                            self.pushLlmEvent(LlmEventData(sessionId: self.sessionId, requestId: requestId,
                                                            kind: "firstToken", textDelta: delta))
                        }
                    }
                }
                self.activeDataTask = task
                task.resume()
            }
        } onCancel: {
            self.activeDataTask?.cancel()
        }
    }

    private func parseTextDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String else { return nil }
        return content
    }

    private func pushLlmEvent(_ event: LlmEventData) {
        eventSink?.onLlmEvent(event)
    }
}
