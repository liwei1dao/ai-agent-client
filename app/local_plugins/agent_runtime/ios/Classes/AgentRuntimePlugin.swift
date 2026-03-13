import Flutter
import UIKit
import AVFoundation

/// AgentRuntimePlugin — iOS Flutter Plugin 入口
///
/// 命令通道（Flutter→Native）：MethodChannel "agent_runtime/commands"
/// 事件通道（Native→Flutter）：EventChannel  "agent_runtime/events"
public class AgentRuntimePlugin: NSObject, FlutterPlugin, AgentEventSink {

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSinkStream: FlutterEventSink?

    private let manager = AgentRuntimeManager.shared

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AgentRuntimePlugin()

        instance.methodChannel = FlutterMethodChannel(
            name: "agent_runtime/commands",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.eventChannel = FlutterEventChannel(
            name: "agent_runtime/events",
            binaryMessenger: registrar.messenger()
        )
        instance.eventChannel?.setStreamHandler(instance)

        instance.manager.eventSink = instance
    }

    // ─────────────────────────────────────────────────
    // FlutterMethodCallDelegate
    // ─────────────────────────────────────────────────

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "startSession":
            let config = args.toAgentSessionConfig()
            Task { await manager.startSession(config: config) }
            result(nil)
        case "stopSession":
            let sessionId = args["sessionId"] as! String
            Task { await manager.stopSession(sessionId: sessionId) }
            result(nil)
        case "sendText":
            Task {
                await manager.sendText(
                    sessionId: args["sessionId"] as! String,
                    requestId: args["requestId"] as! String,
                    text: args["text"] as! String
                )
            }
            result(nil)
        case "interrupt":
            Task { await manager.interrupt(sessionId: args["sessionId"] as! String) }
            result(nil)
        case "setInputMode":
            Task {
                await manager.setInputMode(
                    sessionId: args["sessionId"] as! String,
                    mode: args["mode"] as! String
                )
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─────────────────────────────────────────────────
    // AgentEventSink 实现
    // ─────────────────────────────────────────────────

    func onSttEvent(_ event: SttEventData) {
        pushEvent([
            "type": "stt", "sessionId": event.sessionId, "requestId": event.requestId,
            "kind": event.kind, "text": event.text as Any,
            "errorCode": event.errorCode as Any, "errorMessage": event.errorMessage as Any,
        ])
    }

    func onLlmEvent(_ event: LlmEventData) {
        pushEvent([
            "type": "llm", "sessionId": event.sessionId, "requestId": event.requestId,
            "kind": event.kind,
            "textDelta": event.textDelta as Any, "thinkingDelta": event.thinkingDelta as Any,
            "toolCallId": event.toolCallId as Any, "toolName": event.toolName as Any,
            "toolArgumentsDelta": event.toolArgumentsDelta as Any,
            "toolResult": event.toolResult as Any, "fullText": event.fullText as Any,
            "errorCode": event.errorCode as Any, "errorMessage": event.errorMessage as Any,
        ])
    }

    func onTtsEvent(_ event: TtsEventData) {
        pushEvent([
            "type": "tts", "sessionId": event.sessionId, "requestId": event.requestId,
            "kind": event.kind,
            "progressMs": event.progressMs as Any, "durationMs": event.durationMs as Any,
            "errorCode": event.errorCode as Any, "errorMessage": event.errorMessage as Any,
        ])
    }

    func onStateChanged(sessionId: String, state: String, requestId: String?) {
        pushEvent([
            "type": "stateChanged", "sessionId": sessionId,
            "state": state, "requestId": requestId as Any,
        ])
    }

    func onError(sessionId: String, errorCode: String, message: String, requestId: String?) {
        pushEvent([
            "type": "error", "sessionId": sessionId,
            "errorCode": errorCode, "message": message, "requestId": requestId as Any,
        ])
    }

    private func pushEvent(_ data: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.eventSinkStream?(data)
        }
    }
}

// ─────────────────────────────────────────────────
// FlutterStreamHandler（EventChannel）
// ─────────────────────────────────────────────────

extension AgentRuntimePlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSinkStream = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSinkStream = nil
        return nil
    }
}

// ─────────────────────────────────────────────────
// 扩展：[String: Any] → AgentSessionConfig
// ─────────────────────────────────────────────────

private extension Dictionary where Key == String, Value == Any {
    func toAgentSessionConfig() -> AgentSessionConfig {
        AgentSessionConfig(
            sessionId: self["sessionId"] as! String,
            agentId: self["agentId"] as! String,
            inputMode: self["inputMode"] as! String,
            sttPluginName: self["sttPluginName"] as! String,
            ttsPluginName: self["ttsPluginName"] as! String,
            llmPluginName: self["llmPluginName"] as! String,
            stsPluginName: self["stsPluginName"] as? String,
            sttConfigJson: self["sttConfigJson"] as! String,
            ttsConfigJson: self["ttsConfigJson"] as! String,
            llmConfigJson: self["llmConfigJson"] as! String,
            stsConfigJson: self["stsConfigJson"] as? String
        )
    }
}
