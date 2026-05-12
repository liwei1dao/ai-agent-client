import Foundation

/// LLM (chat-style) service contract.
///
/// Implementations stream SSE responses, surface tool calls, and obey
/// per-request cancellation.
public protocol NativeLlmService: AnyObject {
    /// `configJson` carries apiKey / baseUrl / model / temperature / …
    func initialize(configJson: String)

    /// Stream a chat completion.
    ///
    /// - Parameter messages: history `[{role, content}, …]`.
    /// - Parameter tools: tool/function-calling definitions.
    /// - Parameter callback: streaming hooks; the final value is also returned.
    /// - Returns: the full assistant text (post-tool-call fold-in).
    func chat(
        requestId: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        callback: LlmCallback
    ) async throws -> String

    /// Best-effort cancel of the in-flight request.
    func cancel()
}

public extension NativeLlmService {
    func chat(
        requestId: String,
        messages: [[String: Any]],
        callback: LlmCallback
    ) async throws -> String {
        try await chat(requestId: requestId, messages: messages, tools: [], callback: callback)
    }
}

public protocol LlmCallback: AnyObject {
    /// First text token has arrived.
    func onFirstToken(textDelta: String)

    /// Subsequent text deltas.
    func onTextDelta(_ textDelta: String)

    /// Reasoning/thinking deltas (supported by some providers).
    func onThinkingDelta(_ delta: String)

    /// A tool call has been opened by the model.
    func onToolCallStart(id: String, name: String)

    /// Streamed arguments JSON delta for the current tool call.
    func onToolCallArguments(_ delta: String)

    /// Tool execution result; sent before the model resumes its reply.
    func onToolCallResult(_ result: String)

    /// Streaming finished cleanly.
    func onDone(fullText: String)

    /// Streaming failed.
    func onError(code: String, message: String)
}
