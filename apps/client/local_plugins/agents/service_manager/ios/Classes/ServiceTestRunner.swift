import Foundation
import ai_plugin_interface
import local_db
import os.log

/// iOS port of the Android `ServiceTestRunner`.
///
/// Loads service configs from `local_db` (mirrors the Android path of
/// resolving `serviceId → DB → vendor/configJson`), instantiates the right
/// `Native*Service` via the registry, drives the test, and forwards events
/// through `ServiceTestEventSink`.
///
/// The MVP covers LLM + Translation. STT / TTS / STS / AST follow once their
/// iOS native services land — they need mic/speaker plumbing that doesn't
/// exist on iOS yet (only MethodChannel facades).
final class ServiceTestRunner {
    private static let log = OSLog(subsystem: "com.aiagent.service_manager", category: "Runner")

    private let eventSink: ServiceTestEventSink
    private let queue = DispatchQueue(label: "ServiceTestRunner")
    private var sessions: [String: Session] = [:]

    init(eventSink: ServiceTestEventSink) {
        self.eventSink = eventSink
    }

    // ── Session bookkeeping ───────────────────────────────────────

    private enum Session {
        case llm(NativeLlmService, Task<Void, Never>?)
        case translation(NativeTranslationService, Task<Void, Never>?)
        case stt(NativeSttService)
        case tts(NativeTtsService, Task<Void, Never>?)
        case sts(NativeStsService)
        case ast(NativeAstService)

        func release() {
            switch self {
            case .llm(let s, let task):
                task?.cancel(); s.cancel()
            case .translation(_, let task):
                task?.cancel()
            case .stt(let s):
                s.stopListening(); s.release()
            case .tts(let s, let task):
                task?.cancel(); s.stop(); s.release()
            case .sts(let s):
                s.release()
            case .ast(let s):
                s.release()
            }
        }
    }

    private func storeSession(_ testId: String, _ session: Session) {
        queue.sync {
            sessions[testId]?.release()
            sessions[testId] = session
        }
    }

    private func releaseSession(_ testId: String) {
        let session: Session? = queue.sync {
            let s = sessions.removeValue(forKey: testId)
            return s
        }
        session?.release()
    }

    func releaseAll() {
        queue.sync {
            for (_, s) in sessions { s.release() }
            sessions.removeAll()
        }
    }

    // ── Config lookup ─────────────────────────────────────────────

    private func loadServiceConfig(_ serviceId: String) -> ServiceConfigRecord? {
        do {
            return try AppDatabase.shared.getServiceConfig(id: serviceId)
        } catch {
            os_log("loadServiceConfig %{public}@ failed: %{public}@",
                   log: Self.log, type: .error, serviceId, error.localizedDescription)
            return nil
        }
    }

    // ── LLM test ──────────────────────────────────────────────────

    func testLlmChat(testId: String, serviceId: String, text: String) {
        guard let cfg = loadServiceConfig(serviceId) else {
            eventSink.onLlmTestEvent(testId: testId, kind: "error",
                                     textDelta: nil, thinkingDelta: nil,
                                     toolCallId: nil, toolName: nil,
                                     toolArgumentsDelta: nil, toolResult: nil,
                                     fullText: nil,
                                     errorCode: "service_not_found",
                                     errorMessage: "no service config for id=\(serviceId)")
            return
        }
        let service: NativeLlmService
        do {
            service = try NativeServiceRegistry.shared.createLlm(cfg.vendor)
            service.initialize(configJson: cfg.configJson)
        } catch {
            eventSink.onLlmTestEvent(testId: testId, kind: "error",
                                     textDelta: nil, thinkingDelta: nil,
                                     toolCallId: nil, toolName: nil,
                                     toolArgumentsDelta: nil, toolResult: nil,
                                     fullText: nil,
                                     errorCode: "init_error",
                                     errorMessage: error.localizedDescription)
            return
        }

        let callback = LlmTestCallback(testId: testId, sink: eventSink)
        let task = Task<Void, Never> { [weak self] in
            do {
                _ = try await service.chat(
                    requestId: testId,
                    messages: [["role": "user", "content": text]],
                    tools: [],
                    callback: callback
                )
                self?.eventSink.onTestDone(testId: testId, success: true, message: nil)
            } catch is CancellationError {
                self?.eventSink.onLlmTestEvent(testId: testId, kind: "cancelled",
                                               textDelta: nil, thinkingDelta: nil,
                                               toolCallId: nil, toolName: nil,
                                               toolArgumentsDelta: nil, toolResult: nil,
                                               fullText: nil,
                                               errorCode: nil, errorMessage: nil)
            } catch {
                self?.eventSink.onLlmTestEvent(testId: testId, kind: "error",
                                               textDelta: nil, thinkingDelta: nil,
                                               toolCallId: nil, toolName: nil,
                                               toolArgumentsDelta: nil, toolResult: nil,
                                               fullText: nil,
                                               errorCode: "llm_error",
                                               errorMessage: error.localizedDescription)
            }
        }
        storeSession(testId, .llm(service, task))
    }

    func testLlmCancel(testId: String) {
        let session: Session? = queue.sync { sessions[testId] }
        if case .llm(let svc, let task) = session {
            task?.cancel()
            svc.cancel()
        }
    }

    // ── Translation test ──────────────────────────────────────────

    func testTranslate(testId: String, serviceId: String, text: String,
                       targetLang: String, sourceLang: String?) {
        guard let cfg = loadServiceConfig(serviceId) else {
            eventSink.onTranslationTestEvent(testId: testId, kind: "error",
                                             sourceText: nil, translatedText: nil,
                                             sourceLanguage: nil, targetLanguage: nil,
                                             errorCode: "service_not_found",
                                             errorMessage: "no service config for id=\(serviceId)")
            return
        }

        let service: NativeTranslationService
        do {
            service = try NativeServiceRegistry.shared.createTranslation(cfg.vendor)
            service.initialize(configJson: cfg.configJson)
        } catch {
            eventSink.onTranslationTestEvent(testId: testId, kind: "error",
                                             sourceText: nil, translatedText: nil,
                                             sourceLanguage: nil, targetLanguage: nil,
                                             errorCode: "init_error",
                                             errorMessage: error.localizedDescription)
            return
        }

        let task = Task<Void, Never> { [weak self] in
            do {
                let result = try await service.translate(text: text, targetLang: targetLang,
                                                         sourceLang: sourceLang)
                self?.eventSink.onTranslationTestEvent(testId: testId, kind: "result",
                                                       sourceText: result.sourceText,
                                                       translatedText: result.translatedText,
                                                       sourceLanguage: result.sourceLanguage,
                                                       targetLanguage: result.targetLanguage,
                                                       errorCode: nil, errorMessage: nil)
                self?.eventSink.onTestDone(testId: testId, success: true, message: nil)
            } catch {
                self?.eventSink.onTranslationTestEvent(testId: testId, kind: "error",
                                                       sourceText: nil, translatedText: nil,
                                                       sourceLanguage: nil, targetLanguage: nil,
                                                       errorCode: "translate_error",
                                                       errorMessage: error.localizedDescription)
            }
        }
        storeSession(testId, .translation(service, task))
    }

    // ── STT / TTS / STS / AST: not wired on iOS yet ───────────────

    func notImplemented(testId: String, area: String) {
        switch area {
        case "stt":
            eventSink.onSttTestEvent(testId: testId, kind: "error",
                                     text: nil,
                                     errorCode: "not_implemented",
                                     errorMessage: "STT testing is not supported on iOS yet.")
        case "tts":
            eventSink.onTtsTestEvent(testId: testId, kind: "error",
                                     progressMs: nil, durationMs: nil,
                                     errorCode: "not_implemented",
                                     errorMessage: "TTS testing is not supported on iOS yet.")
        case "sts":
            eventSink.onStsTestEvent(testId: testId, kind: "error",
                                     text: nil, state: nil,
                                     errorCode: "not_implemented",
                                     errorMessage: "STS testing is not supported on iOS yet.")
        case "ast":
            eventSink.onAstTestEvent(testId: testId, kind: "error",
                                     text: nil, state: nil,
                                     errorCode: "not_implemented",
                                     errorMessage: "AST testing is not supported on iOS yet.")
        default:
            break
        }
    }
}

// MARK: - LLM callback adapter

private final class LlmTestCallback: LlmCallback {
    private let testId: String
    private weak var sink: ServiceTestEventSink?

    init(testId: String, sink: ServiceTestEventSink) {
        self.testId = testId
        self.sink = sink
    }

    func onFirstToken(textDelta: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "firstToken",
                             textDelta: textDelta, thinkingDelta: nil,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: nil, toolResult: nil,
                             fullText: nil, errorCode: nil, errorMessage: nil)
    }

    func onTextDelta(_ textDelta: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "textDelta",
                             textDelta: textDelta, thinkingDelta: nil,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: nil, toolResult: nil,
                             fullText: nil, errorCode: nil, errorMessage: nil)
    }

    func onThinkingDelta(_ delta: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "thinking",
                             textDelta: nil, thinkingDelta: delta,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: nil, toolResult: nil,
                             fullText: nil, errorCode: nil, errorMessage: nil)
    }

    func onToolCallStart(id: String, name: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "toolCallStart",
                             textDelta: nil, thinkingDelta: nil,
                             toolCallId: id, toolName: name,
                             toolArgumentsDelta: nil, toolResult: nil,
                             fullText: nil, errorCode: nil, errorMessage: nil)
    }

    func onToolCallArguments(_ delta: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "toolCallArguments",
                             textDelta: nil, thinkingDelta: nil,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: delta, toolResult: nil,
                             fullText: nil, errorCode: nil, errorMessage: nil)
    }

    func onToolCallResult(_ result: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "toolCallResult",
                             textDelta: nil, thinkingDelta: nil,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: nil, toolResult: result,
                             fullText: nil, errorCode: nil, errorMessage: nil)
    }

    func onDone(fullText: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "done",
                             textDelta: nil, thinkingDelta: nil,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: nil, toolResult: nil,
                             fullText: fullText, errorCode: nil, errorMessage: nil)
    }

    func onError(code: String, message: String) {
        sink?.onLlmTestEvent(testId: testId, kind: "error",
                             textDelta: nil, thinkingDelta: nil,
                             toolCallId: nil, toolName: nil,
                             toolArgumentsDelta: nil, toolResult: nil,
                             fullText: nil, errorCode: code, errorMessage: message)
    }
}
