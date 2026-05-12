import Foundation
import ai_plugin_interface
import os.log

/// OpenAI-compatible streaming chat completion (HTTP + SSE).
///
/// Mirrors the Android `LlmOpenaiService`:
///   - one in-flight request per service instance (newer cancels older).
///   - text deltas dispatched as they arrive (`firstToken` → `textDelta*`).
///   - `tool_calls` deltas accumulated by `index`; once the stream closes
///     the buffered tool calls are emitted as
///     `toolCallStart` + `toolCallArguments(complete JSON)` pairs.
///   - the function returns the full assistant text (also surfaced via
///     `onDone(fullText:)`).
public final class LlmOpenaiService: NativeLlmService {

    private static let log = OSLog(subsystem: "com.aiagent.llm_openai", category: "Service")

    private let session: URLSession
    private let stateLock = NSLock()
    private var activeTask: URLSessionDataTask?

    private var apiKey: String = ""
    private var baseUrl: String = ""
    private var model: String = ""
    private var temperature: Double = 0.7
    private var maxTokens: Int = 2048
    private var systemPrompt: String?

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        // SSE streams produce small chunks frequently — disable any cellular
        // bandwidth heuristics that delay delivery.
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
        let rawBase = (cfg["baseUrl"] as? String) ?? ""
        baseUrl = stripTrailingSlash(rawBase)
        model = (cfg["model"] as? String) ?? ""
        if let t = cfg["temperature"] as? Double { temperature = t }
        else if let t = cfg["temperature"] as? Int { temperature = Double(t) }
        if let m = cfg["maxTokens"] as? Int { maxTokens = m }
        let sp = (cfg["systemPrompt"] as? String) ?? ""
        systemPrompt = sp.isEmpty ? nil : sp
        os_log("initialize: baseUrl=%{public}@ model=%{public}@",
               log: Self.log, type: .debug, baseUrl, model)
    }

    public func chat(
        requestId: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        callback: LlmCallback
    ) async throws -> String {
        guard !apiKey.isEmpty, !baseUrl.isEmpty, !model.isEmpty else {
            let msg = "LLM config incomplete: apiKey=\(!apiKey.isEmpty) baseUrl=\(!baseUrl.isEmpty) model=\(!model.isEmpty)"
            os_log("%{public}@", log: Self.log, type: .error, msg)
            callback.onError(code: "config_error", message: msg)
            return ""
        }

        // ── Build request ────────────────────────────────────────────
        var finalMessages: [[String: Any]] = []
        if let sp = systemPrompt, !sp.isEmpty {
            finalMessages.append(["role": "system", "content": sp])
        }
        finalMessages.append(contentsOf: messages)

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": finalMessages,
        ]
        if abs(temperature - 0.7) > .ulpOfOne { body["temperature"] = temperature }
        if maxTokens != 2048 { body["max_tokens"] = maxTokens }
        if !tools.isEmpty { body["tools"] = tools }

        let url = baseUrl.hasSuffix("/chat/completions")
            ? baseUrl
            : "\(baseUrl)/chat/completions"
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

        // ── Stream ────────────────────────────────────────────────────
        let stream = SseHttpStream(session: session, request: request)
        defer {
            stateLock.lock()
            if activeTask === stream.task { activeTask = nil }
            stateLock.unlock()
        }

        // Accumulators
        var fullText = ""
        var firstToken = true
        var toolBuilders: [Int: ToolCallBuilder] = [:]

        do {
            try await stream.start()
        } catch {
            callback.onError(code: "io_error", message: error.localizedDescription)
            return ""
        }
        stateLock.lock(); activeTask = stream.task; stateLock.unlock()

        // Validate HTTP status before consuming the body.
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

                if let delta = parsed.contentDelta, !delta.isEmpty {
                    fullText.append(delta)
                    if firstToken {
                        firstToken = false
                        callback.onFirstToken(textDelta: delta)
                    } else {
                        callback.onTextDelta(delta)
                    }
                }

                for tc in parsed.toolCallDeltas {
                    let builder = toolBuilders[tc.index] ?? ToolCallBuilder()
                    if let id = tc.id { builder.id = id }
                    if let name = tc.name { builder.name = name }
                    if let args = tc.argumentsDelta { builder.arguments.append(args) }
                    toolBuilders[tc.index] = builder
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

        // Emit buffered tool calls (Android-side parity: one shot per call).
        for (_, builder) in toolBuilders {
            guard let name = builder.name, !name.isEmpty else { continue }
            callback.onToolCallStart(id: builder.id ?? "", name: name)
            callback.onToolCallArguments(builder.arguments)
        }

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
        let toolCallDeltas: [ToolCallDelta]
    }

    private struct ToolCallDelta {
        let index: Int
        let id: String?
        let name: String?
        let argumentsDelta: String?
    }

    private final class ToolCallBuilder {
        var id: String?
        var name: String?
        var arguments: String = ""
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

        var toolDeltas: [ToolCallDelta] = []
        if let tcs = delta["tool_calls"] as? [[String: Any]] {
            for tc in tcs {
                let fn = tc["function"] as? [String: Any]
                let id = (tc["id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let name = (fn?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let args = (fn?["arguments"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                toolDeltas.append(ToolCallDelta(
                    index: (tc["index"] as? Int) ?? 0,
                    id: id,
                    name: name,
                    argumentsDelta: args
                ))
            }
        }
        return DeltaParsed(contentDelta: content, toolCallDeltas: toolDeltas)
    }

    private func stripTrailingSlash(_ s: String) -> String {
        var out = s
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }
}

