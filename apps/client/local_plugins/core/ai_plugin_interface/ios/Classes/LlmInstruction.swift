import Foundation

/// A LLM-visible "instruction" placeholder registered through the service
/// config UI. Carries no execution logic itself — concrete side-effects are
/// produced by handlers registered with `InstructionHandlerRegistry`.
public struct LlmInstructionDef {
    public let name: String
    public let description: String
    /// Optional JSON Schema. `nil` means "no arguments".
    public let parameters: [String: Any]?

    public init(name: String, description: String, parameters: [String: Any]? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    /// Render as an OpenAI-compatible function-tool definition.
    public func toOpenAiTool() -> [String: Any] {
        let params: [String: Any] = parameters ?? [
            "type": "object",
            "properties": [String: Any](),
        ]
        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": params,
            ],
        ]
    }

    /// Parse the `instructions` array off the top-level llmConfig JSON.
    /// Returns an empty list when the JSON is missing/malformed.
    public static func list(fromLlmConfigJson llmConfigJson: String?) -> [LlmInstructionDef] {
        guard let json = llmConfigJson,
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = root["instructions"] as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { obj in
            let name = (obj["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty else { return nil }
            let params = obj["parameters"] as? [String: Any]
            return LlmInstructionDef(
                name: name,
                description: (obj["description"] as? String) ?? "",
                parameters: params
            )
        }
    }
}

/// Instruction handler signature. Receives args as a JSON string, returns the
/// "tool call result" the LLM should consume. Returning `nil` means "no
/// handler" — the orchestrator fills in a default ok-response so the dialog
/// can continue.
public typealias InstructionHandler = (_ name: String, _ argsJson: String) async -> String?

/// Global instruction handler registry. Thread-safe.
public final class InstructionHandlerRegistry {
    public static let shared = InstructionHandlerRegistry()

    private let queue = DispatchQueue(label: "InstructionHandlerRegistry")
    private var handlers: [String: InstructionHandler] = [:]

    private init() {}

    public func register(_ name: String, handler: @escaping InstructionHandler) {
        queue.sync { handlers[name] = handler }
    }

    public func unregister(_ name: String) {
        queue.sync { _ = handlers.removeValue(forKey: name) }
    }

    public func has(_ name: String) -> Bool {
        queue.sync { handlers[name] != nil }
    }

    /// Dispatch by name. Returns `nil` when no handler matched. Exceptions
    /// from the handler are turned into a `"Error: …"` payload.
    public func dispatch(_ name: String, argsJson: String) async -> String? {
        let handler = queue.sync { handlers[name] }
        guard let handler = handler else { return nil }
        return await handler(name, argsJson)
    }
}
