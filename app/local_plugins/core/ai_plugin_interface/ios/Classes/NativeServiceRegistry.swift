import Foundation
import os.log

/// Global registry of vendor service factories.
///
/// Each vendor plugin registers itself in `FlutterPlugin.register(with:)`;
/// agents resolve concrete services via `createXxx(vendor:)`.
public final class NativeServiceRegistry {
    public static let shared = NativeServiceRegistry()

    private let logger = OSLog(subsystem: "com.aiagent.plugin_interface", category: "NativeServiceRegistry")
    private let queue = DispatchQueue(label: "NativeServiceRegistry.factories")

    private var sttFactories: [String: () -> NativeSttService] = [:]
    private var ttsFactories: [String: () -> NativeTtsService] = [:]
    private var llmFactories: [String: () -> NativeLlmService] = [:]
    private var stsFactories: [String: () -> NativeStsService] = [:]
    private var astFactories: [String: () -> NativeAstService] = [:]
    private var translationFactories: [String: () -> NativeTranslationService] = [:]
    private var mcpFactories: [String: () -> NativeMcpService] = [:]

    private init() {}

    // ── register ──────────────────────────────────────────────

    public func registerStt(_ vendor: String, factory: @escaping () -> NativeSttService) {
        queue.sync { sttFactories[vendor] = factory }
        os_log("Registered STT vendor: %{public}@", log: logger, type: .debug, vendor)
    }
    public func registerTts(_ vendor: String, factory: @escaping () -> NativeTtsService) {
        queue.sync { ttsFactories[vendor] = factory }
        os_log("Registered TTS vendor: %{public}@", log: logger, type: .debug, vendor)
    }
    public func registerLlm(_ vendor: String, factory: @escaping () -> NativeLlmService) {
        queue.sync { llmFactories[vendor] = factory }
        os_log("Registered LLM vendor: %{public}@", log: logger, type: .debug, vendor)
    }
    public func registerSts(_ vendor: String, factory: @escaping () -> NativeStsService) {
        queue.sync { stsFactories[vendor] = factory }
        os_log("Registered STS vendor: %{public}@", log: logger, type: .debug, vendor)
    }
    public func registerAst(_ vendor: String, factory: @escaping () -> NativeAstService) {
        queue.sync { astFactories[vendor] = factory }
        os_log("Registered AST vendor: %{public}@", log: logger, type: .debug, vendor)
    }
    public func registerTranslation(_ vendor: String, factory: @escaping () -> NativeTranslationService) {
        queue.sync { translationFactories[vendor] = factory }
        os_log("Registered Translation vendor: %{public}@", log: logger, type: .debug, vendor)
    }
    public func registerMcp(_ transport: String, factory: @escaping () -> NativeMcpService) {
        queue.sync { mcpFactories[transport] = factory }
        os_log("Registered MCP transport: %{public}@", log: logger, type: .debug, transport)
    }

    // ── create ────────────────────────────────────────────────

    public func createStt(_ vendor: String) throws -> NativeSttService {
        let (factory, keys) = queue.sync { (sttFactories[vendor], Array(sttFactories.keys)) }
        guard let factory = factory else { throw missing("STT", vendor, keys) }
        return factory()
    }
    public func createTts(_ vendor: String) throws -> NativeTtsService {
        let (factory, keys) = queue.sync { (ttsFactories[vendor], Array(ttsFactories.keys)) }
        guard let factory = factory else { throw missing("TTS", vendor, keys) }
        return factory()
    }
    public func createLlm(_ vendor: String) throws -> NativeLlmService {
        let (factory, keys) = queue.sync { (llmFactories[vendor], Array(llmFactories.keys)) }
        guard let factory = factory else { throw missing("LLM", vendor, keys) }
        return factory()
    }
    public func createSts(_ vendor: String) throws -> NativeStsService {
        let (factory, keys) = queue.sync { (stsFactories[vendor], Array(stsFactories.keys)) }
        guard let factory = factory else { throw missing("STS", vendor, keys) }
        return factory()
    }
    public func createAst(_ vendor: String) throws -> NativeAstService {
        let (factory, keys) = queue.sync { (astFactories[vendor], Array(astFactories.keys)) }
        guard let factory = factory else { throw missing("AST", vendor, keys) }
        return factory()
    }
    public func createTranslation(_ vendor: String) throws -> NativeTranslationService {
        let (factory, keys) = queue.sync { (translationFactories[vendor], Array(translationFactories.keys)) }
        guard let factory = factory else { throw missing("Translation", vendor, keys) }
        return factory()
    }
    public func createMcp(_ transport: String) throws -> NativeMcpService {
        let (factory, keys) = queue.sync { (mcpFactories[transport], Array(mcpFactories.keys)) }
        guard let factory = factory else { throw missing("MCP", transport, keys) }
        return factory()
    }

    // ── query ─────────────────────────────────────────────────

    public func availableSttVendors() -> Set<String> { Set(queue.sync { Array(sttFactories.keys) }) }
    public func availableTtsVendors() -> Set<String> { Set(queue.sync { Array(ttsFactories.keys) }) }
    public func availableLlmVendors() -> Set<String> { Set(queue.sync { Array(llmFactories.keys) }) }
    public func availableStsVendors() -> Set<String> { Set(queue.sync { Array(stsFactories.keys) }) }
    public func availableAstVendors() -> Set<String> { Set(queue.sync { Array(astFactories.keys) }) }
    public func availableTranslationVendors() -> Set<String> { Set(queue.sync { Array(translationFactories.keys) }) }
    public func availableMcpTransports() -> Set<String> { Set(queue.sync { Array(mcpFactories.keys) }) }

    private func missing(_ kind: String, _ vendor: String, _ keys: [String]) -> Error {
        NativeServiceError.invalidConfig(
            "No \(kind) service registered for vendor: \(vendor). Available: \(keys)"
        )
    }
}
