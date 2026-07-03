import Foundation
import ai_plugin_interface
import os.log

/// Volcengine Ark streaming chat completion (HTTP + SSE).
///
/// Mirrors the Android `LlmVolcengineService`. Differences from the
/// OpenAI-compatible base:
///   - Default `baseUrl` falls back to `https://ark.cn-beijing.volces.com/api/v3`
///     when the user leaves it blank.
///   - Adds a `thinking` switch (`{type: "enabled"|"disabled"}`) — defaults to
///     disabled so doubao thinking models do not stall on first token.
///   - Parses `delta.reasoning_content` and forwards it as `onThinkingDelta`.
///   - Tool-call deltas are emitted incrementally (`onToolCallStart` at the
///     first frame carrying both id and name, then `onToolCallArguments` for
///     each subsequent arguments chunk) — also matching Kotlin parity.
public final class LlmVolcengineService: NativeLlmService {

    private static let log = OSLog(subsystem: "com.aiagent.llm_volcengine", category: "Service")
    private static let defaultBaseUrl = "https://ark.cn-beijing.volces.com/api/v3"

    private let session: URLSession
    private let stateLock = NSLock()
    private var activeTask: URLSessionDataTask?

    private var apiKey: String = ""
    private var baseUrl: String = defaultBaseUrl
    private var model: String = ""
    private var temperature: Double = 0.7
    private var maxTokens: Int = 2048
    private var systemPrompt: String?
    private var enableThinking: Bool = false

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        self.session = URLSession(configuration: cfg)
    }

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            os_log("initialize: invalid config json", log: Self.log, type: .error)
            return
        }
        apiKey = (cfg["apiKey"] as? String) ?? ""
        baseUrl = normalizeBaseUrl((cfg["baseUrl"] as? String) ?? "")
        model = (cfg["model"] as? String) ?? ""
        if let t = cfg["temperature"] as? Double { temperature = t }
        else if let t = cfg["temperature"] as? Int { temperature = Double(t) }
        if let m = cfg["maxTokens"] as? Int { maxTokens = m }
        let sp = (cfg["systemPrompt"] as? String) ?? ""
        systemPrompt = sp.isEmpty ? nil : sp
        enableThinking = (cfg["enableThinking"] as? Bool) ?? false
        os_log("initialize: baseUrl=%{public}@ model=%{public}@ thinking=%{public}@",
               log: Self.log, type: .debug, baseUrl, model, String(describing: enableThinking))
    }

    public func chat(
        requestId: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        callback: LlmCallback
    ) async throws -> String {
        guard !apiKey.isEmpty, !model.isEmpty else {
            let msg = "LLM config incomplete: apiKey=\(!apiKey.isEmpty) model=\(!model.isEmpty)"
            os_log("%{public}@", log: Self.log, type: .error, msg)
            callback.onError(code: "config_error", message: msg)
            return ""
        }

        var finalMessages: [[String: Any]] = []
        if let sp = systemPrompt, !sp.isEmpty {
            finalMessages.append(["role": "system", "content": sp])
        }
        finalMessages.append(contentsOf: messages)

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": finalMessages,
            "thinking": ["type": enableThinking ? "enabled" : "disabled"],
        ]
        if abs(temperature - 0.7) > .ulpOfOne { body["temperature"] = temperature }
        if maxTokens != 2048 { body["max_tokens"] = maxTokens }
        if !tools.isEmpty { body["tools"] = tools }

        let url = "\(baseUrl)/chat/completions"
        guard let endpoint = URL(string: url) else {
            callback.onError(code: "config_error", message: "invalid baseUrl: \(url)")
            return ""
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        os_log("POST %{public}@ model=%{public}@ messages=%d tools=%d",
               log: Self.log, type: .debug, url, model, messages.count, tools.count)

        let stream = SseHttpStream(session: session, request: request)
        defer {
            stateLock.lock()
            if activeTask === stream.task { activeTask = nil }
            stateLock.unlock()
        }

        var fullText = ""
        var firstToken = true
        // Track which tool-call indices already emitted `onToolCallStart`.
        // Ark/OpenAI streams reuse a `tool_calls[].index`; the first frame
        // carries `id` + `function.name`, subsequent frames carry only
        // `function.arguments` deltas.
        var toolStarted: [Int: Bool] = [:]

        do {
            try await stream.start()
        } catch {
            callback.onError(code: "io_error", message: error.localizedDescription)
            return ""
        }
        stateLock.lock(); activeTask = stream.task; stateLock.unlock()

        if let http = stream.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyPreview = await stream.drainBodyPreview(limit: 300)
            let msg = "HTTP \(http.statusCode): \(bodyPreview)"
            os_log("LLM request failed: %{public}@", log: Self.log, type: .error, msg)
            callback.onError(code: "http_\(http.statusCode)", message: msg)
            return ""
        }

        do {
            for try await line in stream.lines() {
                try Task.checkCancellation()
                guard line.hasPrefix("data: ") else { continue }
                let data = line.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                if data == "[DONE]" { break }

                guard let parsed = parseDelta(data) else { continue }

                if let content = parsed.contentDelta, !content.isEmpty {
                    fullText.append(content)
                    if firstToken {
                        firstToken = false
                        callback.onFirstToken(textDelta: content)
                    } else {
                        callback.onTextDelta(content)
                    }
                }

                if let thinking = parsed.thinkingDelta, !thinking.isEmpty {
                    callback.onThinkingDelta(thinking)
                }

                for tc in parsed.toolCallDeltas {
                    let already = toolStarted[tc.index] == true
                    if !already, let id = tc.id, !id.isEmpty, let name = tc.name, !name.isEmpty {
                        callback.onToolCallStart(id: id, name: name)
                        toolStarted[tc.index] = true
                    }
                    if let args = tc.argumentsDelta, !args.isEmpty {
                        callback.onToolCallArguments(args)
                    }
                }
            }
        } catch is CancellationError {
            stream.cancel()
            return ""
        } catch {
            os_log("IO error: %{public}@", log: Self.log, type: .error, error.localizedDescription)
            callback.onError(code: "io_error", message: error.localizedDescription)
            return ""
        }

        os_log("stream done: textLen=%d toolCalls=%d",
               log: Self.log, type: .debug, fullText.count, toolStarted.count)
        callback.onDone(fullText: fullText)
        return fullText
    }

    public func cancel() {
        stateLock.lock()
        let task = activeTask
        activeTask = nil
        stateLock.unlock()
        task?.cancel()
    }

    // ── Parsing helpers ─────────────────────────────────────────────

    private struct DeltaParsed {
        let contentDelta: String?
        let thinkingDelta: String?
        let toolCallDeltas: [ToolCallDelta]
    }

    private struct ToolCallDelta {
        let index: Int
        let id: String?
        let name: String?
        let argumentsDelta: String?
    }

    private func parseDelta(_ jsonString: String) -> DeltaParsed? {
        guard let data = jsonString.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first else {
            return nil
        }
        let delta = (first["delta"] as? [String: Any]) ?? [:]
        let content: String? = {
            let s = (delta["content"] as? String) ?? ""
            return s.isEmpty ? nil : s
        }()
        let thinking: String? = {
            let s = (delta["reasoning_content"] as? String) ?? ""
            return s.isEmpty ? nil : s
        }()

        var toolDeltas: [ToolCallDelta] = []
        if let tcs = delta["tool_calls"] as? [[String: Any]] {
            for (i, tc) in tcs.enumerated() {
                let fn = tc["function"] as? [String: Any]
                let id = (tc["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let name = (fn?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let args = (fn?["arguments"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                toolDeltas.append(ToolCallDelta(
                    index: (tc["index"] as? Int) ?? i,
                    id: id,
                    name: name,
                    argumentsDelta: args
                ))
            }
        }
        return DeltaParsed(contentDelta: content, thinkingDelta: thinking, toolCallDeltas: toolDeltas)
    }

    private func normalizeBaseUrl(_ raw: String) -> String {
        var u = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return Self.defaultBaseUrl }
        while u.hasSuffix("/") { u.removeLast() }
        if u.hasSuffix("/chat/completions") {
            u = String(u.dropLast("/chat/completions".count))
            while u.hasSuffix("/") { u.removeLast() }
        }
        return u
    }
}
