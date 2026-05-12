import Flutter
import ai_plugin_interface
import os.log

/// iOS counterpart of the Android `ServiceManagerPlugin`.
///
/// Routes Dart commands on `service_manager/commands` to a `ServiceTestRunner`,
/// and fans `ServiceTestEventSink` callbacks back through
/// `service_manager/events`. The event payload schema mirrors the Android
/// side so the Dart bridge stays platform-agnostic.
public final class ServiceManagerPlugin: NSObject, FlutterPlugin, ServiceTestEventSink {
    private static let log = OSLog(subsystem: "com.aiagent.service_manager", category: "Plugin")

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private let streamHandler = SmStreamHandler()
    private var runner: ServiceTestRunner!

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ServiceManagerPlugin()
        instance.runner = ServiceTestRunner(eventSink: instance)
        let messenger = registrar.messenger()

        instance.methodChannel = FlutterMethodChannel(
            name: "service_manager/commands",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "service_manager/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(instance.streamHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = (call.arguments as? [String: Any?]) ?? [:]
        switch call.method {

        // ── LLM ──
        case "testLlmChat":
            guard let testId = args["testId"] as? String,
                  let serviceId = args["serviceId"] as? String,
                  let text = args["text"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "testLlmChat args", details: nil)); return
            }
            runner.testLlmChat(testId: testId, serviceId: serviceId, text: text)
            result(nil)
        case "testLlmCancel":
            guard let testId = args["testId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "testId missing", details: nil)); return
            }
            runner.testLlmCancel(testId: testId)
            result(nil)

        // ── Translation ──
        case "testTranslate":
            guard let testId = args["testId"] as? String,
                  let serviceId = args["serviceId"] as? String,
                  let text = args["text"] as? String,
                  let targetLang = args["targetLang"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "testTranslate args", details: nil)); return
            }
            let sourceLang = args["sourceLang"] as? String
            runner.testTranslate(testId: testId, serviceId: serviceId, text: text,
                                 targetLang: targetLang, sourceLang: sourceLang)
            result(nil)

        // ── Not wired on iOS yet: surface a structured error rather than
        //    silently succeeding so the UI can mark the test as failed. ──
        case "testSttStart":
            guard let testId = args["testId"] as? String else { result(nil); return }
            runner.notImplemented(testId: testId, area: "stt"); result(nil)
        case "testTtsSpeak":
            guard let testId = args["testId"] as? String else { result(nil); return }
            runner.notImplemented(testId: testId, area: "tts"); result(nil)
        case "testStsConnect":
            guard let testId = args["testId"] as? String else { result(nil); return }
            runner.notImplemented(testId: testId, area: "sts"); result(nil)
        case "testAstConnect":
            guard let testId = args["testId"] as? String else { result(nil); return }
            runner.notImplemented(testId: testId, area: "ast"); result(nil)

        // Stop/cancel methods are no-ops while the underlying paths are stubs.
        case "testSttStop", "testTtsStop",
             "testStsStartAudio", "testStsStopAudio", "testStsDisconnect",
             "testAstStartAudio", "testAstStopAudio", "testAstDisconnect":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── ServiceTestEventSink ──────────────────────────────────────

    public func onSttTestEvent(testId: String, kind: String, text: String?, errorCode: String?, errorMessage: String?) {
        push([
            "type": "stt",
            "testId": testId,
            "kind": kind,
            "text": text as Any,
            "errorCode": errorCode as Any,
            "errorMessage": errorMessage as Any,
        ])
    }

    public func onTtsTestEvent(testId: String, kind: String, progressMs: Int?, durationMs: Int?, errorCode: String?, errorMessage: String?) {
        push([
            "type": "tts",
            "testId": testId,
            "kind": kind,
            "progressMs": progressMs as Any,
            "durationMs": durationMs as Any,
            "errorCode": errorCode as Any,
            "errorMessage": errorMessage as Any,
        ])
    }

    public func onLlmTestEvent(
        testId: String,
        kind: String,
        textDelta: String?,
        thinkingDelta: String?,
        toolCallId: String?,
        toolName: String?,
        toolArgumentsDelta: String?,
        toolResult: String?,
        fullText: String?,
        errorCode: String?,
        errorMessage: String?
    ) {
        push([
            "type": "llm",
            "testId": testId,
            "kind": kind,
            "textDelta": textDelta as Any,
            "thinkingDelta": thinkingDelta as Any,
            "toolCallId": toolCallId as Any,
            "toolName": toolName as Any,
            "toolArgumentsDelta": toolArgumentsDelta as Any,
            "toolResult": toolResult as Any,
            "fullText": fullText as Any,
            "errorCode": errorCode as Any,
            "errorMessage": errorMessage as Any,
        ])
    }

    public func onTranslationTestEvent(
        testId: String,
        kind: String,
        sourceText: String?,
        translatedText: String?,
        sourceLanguage: String?,
        targetLanguage: String?,
        errorCode: String?,
        errorMessage: String?
    ) {
        push([
            "type": "translation",
            "testId": testId,
            "kind": kind,
            "sourceText": sourceText as Any,
            "translatedText": translatedText as Any,
            "sourceLanguage": sourceLanguage as Any,
            "targetLanguage": targetLanguage as Any,
            "errorCode": errorCode as Any,
            "errorMessage": errorMessage as Any,
        ])
    }

    public func onStsTestEvent(testId: String, kind: String, text: String?, state: String?, errorCode: String?, errorMessage: String?) {
        push([
            "type": "sts", "testId": testId, "kind": kind,
            "text": text as Any, "state": state as Any,
            "errorCode": errorCode as Any, "errorMessage": errorMessage as Any,
        ])
    }

    public func onAstTestEvent(testId: String, kind: String, text: String?, state: String?, errorCode: String?, errorMessage: String?) {
        push([
            "type": "ast", "testId": testId, "kind": kind,
            "text": text as Any, "state": state as Any,
            "errorCode": errorCode as Any, "errorMessage": errorMessage as Any,
        ])
    }

    public func onTestDone(testId: String, success: Bool, message: String?) {
        push([
            "type": "done",
            "testId": testId,
            "success": success,
            "message": message as Any,
        ])
    }

    private func push(_ payload: [String: Any]) {
        streamHandler.send(payload)
    }
}

/// Local copy of the stream handler — keeps service_manager independent of
/// the agents_server module.
private final class SmStreamHandler: NSObject, FlutterStreamHandler {
    private let lock = NSLock()
    private var sink: FlutterEventSink?

    func send(_ data: [String: Any]) {
        lock.lock(); let s = sink; lock.unlock()
        guard let s = s else { return }
        if Thread.isMainThread { s(data) }
        else { DispatchQueue.main.async { s(data) } }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        lock.lock(); sink = events; lock.unlock(); return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock(); sink = nil; lock.unlock(); return nil
    }
}
