import Foundation
import os.log

/// Global registry of native agent factories.
///
/// Each agent-type plugin (`agent_chat`, `agent_sts_chat`, …) calls
/// `register(type:factory:)` during its iOS `FlutterPlugin.register(with:)`
/// hook. `agents_server` then resolves agent instances by type string.
public final class NativeAgentRegistry {
    public static let shared = NativeAgentRegistry()

    private let logger = OSLog(subsystem: "com.aiagent.plugin_interface", category: "NativeAgentRegistry")
    private let queue = DispatchQueue(label: "NativeAgentRegistry.factories")
    private var factories: [String: () -> NativeAgent] = [:]

    private init() {}

    /// Register an agent factory.
    /// - Parameters:
    ///   - agentType: canonical type string ("chat", "sts-chat", "translate", "ast-translate").
    ///   - factory: closure producing a fresh `NativeAgent` instance.
    public func register(_ agentType: String, factory: @escaping () -> NativeAgent) {
        queue.sync { factories[agentType] = factory }
        os_log("Registered agent type: %{public}@", log: logger, type: .debug, agentType)
    }

    /// Instantiate an agent. Throws if the type is unknown.
    public func create(_ agentType: String) throws -> NativeAgent {
        let factory = queue.sync { factories[agentType] }
        guard let factory = factory else {
            let known = queue.sync { Array(factories.keys) }
            throw NativeServiceError.invalidConfig(
                "No agent registered for type: \(agentType). Available: \(known)"
            )
        }
        return factory()
    }

    public func supportedTypes() -> Set<String> {
        Set(queue.sync { factories.keys })
    }
}
