import Flutter
import Foundation
import ai_plugin_interface
import os.log

/// assistant_server Flutter plugin（iOS）—— 与 Android `AssistantServerPlugin` 对齐。
///
/// - MethodChannel `assistant_server/method`:
///     • startAssistant(arg: Map) → sessionId
///     • stopActiveSession()
///     • activeSessionId() → String?
/// - EventChannel `assistant_server/events`:
///     消息 / 状态 / 错误 / 连接状态（详见 [AssistantEvents]）
///
/// 编排逻辑在 [AssistantServerCore] / [AssistantSession]，本类只做调度。
public class AssistantServerPlugin: NSObject, FlutterPlugin {

    private static let log = OSLog(subsystem: "com.aiagent.assistant_server", category: "Plugin")

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private let streamHandler = EventStreamHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = AssistantServerPlugin()
        let messenger = registrar.messenger()

        instance.eventChannel = FlutterEventChannel(
            name: "assistant_server/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(instance.streamHandler)

        instance.methodChannel = FlutterMethodChannel(
            name: "assistant_server/method",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        // 注入 emitter + device_jieli MethodChannel
        AssistantServerCore.shared.bindContext(messenger: messenger) { payload in
            instance.streamHandler.send(payload)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            try dispatch(call, result: result)
        } catch {
            result(FlutterError(code: "AssistantServer", message: error.localizedDescription, details: nil))
        }
    }

    private func dispatch(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        switch call.method {
        case "startAssistant":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "InvalidArgument", message: "arguments must be a map", details: nil))
                return
            }
            let req = try parseRequest(args)
            let sessionId = (args["sessionId"] as? String)
                ?? "as_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))"
            do {
                let id = try AssistantServerCore.shared.startAssistant(sessionId: sessionId, request: req)
                result(id)
            } catch let nsErr as NSError {
                result(FlutterError(
                    code: codeFromMessage(nsErr.localizedDescription, defaultCode: "assistant.start_failed"),
                    message: nsErr.localizedDescription,
                    details: nil
                ))
            }

        case "stopActiveSession":
            AssistantServerCore.shared.stopActive()
            result(nil)

        case "activeSessionId":
            result(AssistantServerCore.shared.activeSessionId())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func parseRequest(_ args: [String: Any]) throws -> AssistantRequest {
        guard let agentType = args["agentType"] as? String, !agentType.isEmpty else {
            throw NSError(domain: "AssistantServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "agentType required"])
        }
        guard let agentConfigMap = args["agentConfig"] as? [String: Any] else {
            throw NSError(domain: "AssistantServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "agentConfig required"])
        }
        let userLanguage = (args["userLanguage"] as? String) ?? ""
        return AssistantRequest(
            agentType: agentType,
            agentConfig: NativeAgentConfig.fromMap(agentConfigMap),
            userLanguage: userLanguage
        )
    }

    private func codeFromMessage(_ msg: String, defaultCode: String) -> String {
        let prefix = msg.split(separator: ":").first.map(String.init) ?? ""
        return prefix.hasPrefix("assistant.") ? prefix : defaultCode
    }
}

/// 把核心层 emit 出来的事件回灌 FlutterEventChannel。
final class EventStreamHandler: NSObject, FlutterStreamHandler {
    private let lock = NSLock()
    private var sink: FlutterEventSink?

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        lock.lock(); sink = events; lock.unlock()
        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        lock.lock(); sink = nil; lock.unlock()
        return nil
    }

    func send(_ payload: [String: Any?]) {
        let s: FlutterEventSink?
        lock.lock(); s = sink; lock.unlock()
        guard let s = s else { return }
        let cleaned = payload.reduce(into: [String: Any]()) { acc, kv in
            if let v = kv.value { acc[kv.key] = v }
        }
        if Thread.isMainThread {
            s(cleaned)
        } else {
            DispatchQueue.main.async { s(cleaned) }
        }
    }
}
