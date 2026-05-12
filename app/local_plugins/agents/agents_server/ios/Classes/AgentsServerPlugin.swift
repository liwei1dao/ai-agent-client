import Flutter
import ai_plugin_interface
import os.log

/// iOS counterpart of the Android `AgentsServerPlugin + AgentsServerService`.
///
/// Android needs a separate `Service` to survive backgrounding via the
/// foreground-service mechanism. iOS keeps agents alive only while the app
/// process is alive, so both responsibilities fold into a single Swift class.
///
/// Wire layout (matches Android, identical channel/event payloads):
///   - MethodChannel "agents_server/commands"
///   - EventChannel  "agents_server/events"
public final class AgentsServerPlugin: NSObject, FlutterPlugin {

    private static let log = OSLog(subsystem: "com.aiagent.agents_server", category: "Plugin")

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private let streamHandler = EventChannelStreamHandler()

    /// Active agents keyed by agentId.
    private let agentsLock = NSLock()
    private var agents: [String: NativeAgent] = [:]

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AgentsServerPlugin()
        let messenger = registrar.messenger()

        instance.methodChannel = FlutterMethodChannel(
            name: "agents_server/commands",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "agents_server/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(instance.streamHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = (call.arguments as? [String: Any?]) ?? [:]

        // Audio routing is independent of agent state; honour it eagerly.
        if call.method == "setAudioOutputMode" {
            let mode: AudioOutputManager.Mode = {
                switch args["mode"] as? String {
                case "earpiece": return .earpiece
                case "speaker":  return .speaker
                default:         return .auto
                }
            }()
            AudioOutputManager.shared.setMode(mode)
            result(nil)
            return
        }

        switch call.method {
        case "createAgent":
            guard let agentType = args["agentType"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "agentType missing", details: nil))
                return
            }
            let config = NativeAgentConfig.fromMap(args)
            createAgent(agentType: agentType, config: config, result: result)

        case "stopAgent", "deleteAgent":
            guard let agentId = args["agentId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT",
                                    message: "agentId missing", details: nil)); return
            }
            stopAgent(agentId)
            result(nil)

        case "sendText":
            guard let agentId = args["agentId"] as? String,
                  let requestId = args["requestId"] as? String,
                  let text = args["text"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "sendText args", details: nil)); return
            }
            agent(by: agentId)?.sendText(requestId: requestId, text: text)
            result(nil)

        case "setInputMode":
            guard let agentId = args["agentId"] as? String,
                  let mode = args["mode"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "setInputMode args", details: nil)); return
            }
            agent(by: agentId)?.setInputMode(mode)
            result(nil)

        case "setAgentOption":
            guard let agentId = args["agentId"] as? String,
                  let key = args["key"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "setAgentOption args", details: nil)); return
            }
            let value = (args["value"] as? String) ?? ""
            agent(by: agentId)?.setOption(key: key, value: value)
            result(nil)

        case "startListening":
            guard let agentId = args["agentId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "agentId missing", details: nil)); return
            }
            agent(by: agentId)?.startListening()
            result(nil)

        case "stopListening":
            guard let agentId = args["agentId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "agentId missing", details: nil)); return
            }
            agent(by: agentId)?.stopListening()
            result(nil)

        case "interrupt":
            guard let agentId = args["agentId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "agentId missing", details: nil)); return
            }
            agent(by: agentId)?.interrupt()
            result(nil)

        case "connectService":
            guard let agentId = args["agentId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "agentId missing", details: nil)); return
            }
            agent(by: agentId)?.connectService()
            result(nil)

        case "disconnectService":
            guard let agentId = args["agentId"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENT", message: "agentId missing", details: nil)); return
            }
            agent(by: agentId)?.disconnectService()
            result(nil)

        case "pauseAudio":
            if let agentId = args["agentId"] as? String { agent(by: agentId)?.stopListening() }
            result(nil)
        case "resumeAudio":
            if let agentId = args["agentId"] as? String { agent(by: agentId)?.startListening() }
            result(nil)
        case "notifyAppForeground":
            // Android uses this to keep its foreground service alive — no-op on iOS.
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ── Agent lifecycle ───────────────────────────────────────────

    private func createAgent(agentType: String, config: NativeAgentConfig, result: @escaping FlutterResult) {
        let agentId = config.agentId
        agentsLock.lock()
        if let existing = agents.removeValue(forKey: agentId) {
            agentsLock.unlock()
            os_log("Agent %{public}@ already exists; releasing previous instance",
                   log: Self.log, type: .info, agentId)
            existing.release()
            agentsLock.lock()
        }
        agentsLock.unlock()

        do {
            let agent = try NativeAgentRegistry.shared.create(agentType)
            agent.initialize(config: config, eventSink: self)
            agentsLock.lock(); agents[agentId] = agent; agentsLock.unlock()
            os_log("Created agent type=%{public}@ id=%{public}@",
                   log: Self.log, type: .debug, agentType, agentId)
            result(nil)
        } catch {
            os_log("createAgent failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
            onError(sessionId: agentId,
                    errorCode: "create_error",
                    message: error.localizedDescription,
                    requestId: nil)
            result(FlutterError(code: "CREATE_AGENT_ERROR",
                                message: error.localizedDescription,
                                details: nil))
        }
    }

    private func stopAgent(_ agentId: String) {
        agentsLock.lock()
        let agent = agents.removeValue(forKey: agentId)
        agentsLock.unlock()
        agent?.release()
    }

    private func agent(by id: String) -> NativeAgent? {
        agentsLock.lock(); defer { agentsLock.unlock() }
        return agents[id]
    }
}

// MARK: - AgentEventSink

extension AgentsServerPlugin: AgentEventSink {

    public func onSttEvent(_ event: SttEventData) {
        pushEvent([
            "type": "stt",
            "sessionId": event.sessionId,
            "requestId": event.requestId,
            "kind": event.kind,
            "text": event.text as Any,
            "detectedLang": event.detectedLang as Any,
            "errorCode": event.errorCode as Any,
            "errorMessage": event.errorMessage as Any,
        ])
    }

    public func onLlmEvent(_ event: LlmEventData) {
        pushEvent([
            "type": "llm",
            "sessionId": event.sessionId,
            "requestId": event.requestId,
            "kind": event.kind,
            "textDelta": event.textDelta as Any,
            "thinkingDelta": event.thinkingDelta as Any,
            "toolCallId": event.toolCallId as Any,
            "toolName": event.toolName as Any,
            "toolArgumentsDelta": event.toolArgumentsDelta as Any,
            "toolResult": event.toolResult as Any,
            "fullText": event.fullText as Any,
            "errorCode": event.errorCode as Any,
            "errorMessage": event.errorMessage as Any,
        ])
    }

    public func onTtsEvent(_ event: TtsEventData) {
        pushEvent([
            "type": "tts",
            "sessionId": event.sessionId,
            "requestId": event.requestId,
            "kind": event.kind,
            "progressMs": event.progressMs as Any,
            "durationMs": event.durationMs as Any,
            "errorCode": event.errorCode as Any,
            "errorMessage": event.errorMessage as Any,
        ])
    }

    public func onStateChanged(sessionId: String, state: String, requestId: String?) {
        pushEvent([
            "type": "stateChanged",
            "sessionId": sessionId,
            "state": state,
            "requestId": requestId as Any,
        ])
    }

    public func onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        pushEvent([
            "type": "error",
            "sessionId": sessionId,
            "errorCode": errorCode,
            "message": message,
            "requestId": requestId as Any,
        ])
    }

    public func onConnectionStateChanged(sessionId: String, state: String, errorMessage: String?) {
        pushEvent([
            "type": "connectionState",
            "sessionId": sessionId,
            "state": state,
            "errorMessage": errorMessage as Any,
        ])
    }

    public func onAgentReady(sessionId: String, ready: Bool, errorCode: String?, errorMessage: String?) {
        pushEvent([
            "type": "agentReady",
            "sessionId": sessionId,
            "ready": ready,
            "errorCode": errorCode as Any,
            "errorMessage": errorMessage as Any,
        ])
    }

    private func pushEvent(_ data: [String: Any]) {
        streamHandler.send(data)
    }
}

// MARK: - EventChannel stream handler

/// Holds the current FlutterEventSink and delivers events on the main thread.
final class EventChannelStreamHandler: NSObject, FlutterStreamHandler {
    private let lock = NSLock()
    private var sink: FlutterEventSink?

    func send(_ data: [String: Any]) {
        lock.lock(); let snapshot = sink; lock.unlock()
        guard let snapshot = snapshot else { return }
        if Thread.isMainThread {
            snapshot(data)
        } else {
            DispatchQueue.main.async { snapshot(data) }
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        lock.lock(); sink = events; lock.unlock()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        lock.lock(); sink = nil; lock.unlock()
        return nil
    }
}
