import Flutter
import Foundation
import ai_plugin_interface
import os.log

/// translate_server Flutter plugin（iOS）—— 与 Android `TranslateServerPlugin` 对齐。
public class TranslateServerPlugin: NSObject, FlutterPlugin {

    private static let log = OSLog(subsystem: "com.aiagent.translate_server", category: "Plugin")

    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private let streamHandler = TranslateEventStreamHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TranslateServerPlugin()
        let messenger = registrar.messenger()

        instance.eventChannel = FlutterEventChannel(
            name: "translate_server/events",
            binaryMessenger: messenger
        )
        instance.eventChannel?.setStreamHandler(instance.streamHandler)

        instance.methodChannel = FlutterMethodChannel(
            name: "translate_server/method",
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        TranslateServerCore.shared.bindContext(messenger: messenger) { payload in
            instance.streamHandler.send(payload)
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            try dispatch(call, result: result)
        } catch {
            result(FlutterError(code: "TranslateServer", message: error.localizedDescription, details: nil))
        }
    }

    private func dispatch(_ call: FlutterMethodCall, result: @escaping FlutterResult) throws {
        switch call.method {
        case "startCallTranslation":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "InvalidArgument", message: "arguments must be a map", details: nil))
                return
            }
            let req = try parseCallRequest(args)
            let sessionId = (args["sessionId"] as? String)
                ?? "ts_\(Int64(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.prefix(6))"
            do {
                let id = try TranslateServerCore.shared.startCallTranslation(sessionId: sessionId, request: req)
                result(id)
            } catch let nsErr as NSError {
                result(FlutterError(
                    code: codeFromMessage(nsErr.localizedDescription, defaultCode: "translate.start_failed"),
                    message: nsErr.localizedDescription,
                    details: nil
                ))
            }

        case "stopActiveSession":
            TranslateServerCore.shared.stopActive()
            result(nil)

        case "activeSessionId":
            result(TranslateServerCore.shared.activeSessionId())

        case "startFaceToFaceTranslation", "startAudioTranslation":
            result(FlutterError(code: "translate.not_implemented",
                                message: "\(call.method) not implemented yet", details: nil))

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func parseCallRequest(_ args: [String: Any]) throws -> CallTranslationRequest {
        guard let uplinkAgentType = args["uplinkAgentType"] as? String, !uplinkAgentType.isEmpty else {
            throw NSError(domain: "TranslateServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "uplinkAgentType required"])
        }
        guard let downlinkAgentType = args["downlinkAgentType"] as? String, !downlinkAgentType.isEmpty else {
            throw NSError(domain: "TranslateServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "downlinkAgentType required"])
        }
        guard let uplinkConfigMap = args["uplinkConfig"] as? [String: Any] else {
            throw NSError(domain: "TranslateServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "uplinkConfig required"])
        }
        guard let downlinkConfigMap = args["downlinkConfig"] as? [String: Any] else {
            throw NSError(domain: "TranslateServer", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "downlinkConfig required"])
        }
        let userLanguage = (args["userLanguage"] as? String) ?? ""
        let peerLanguage = (args["peerLanguage"] as? String) ?? ""
        return CallTranslationRequest(
            uplinkAgentType: uplinkAgentType,
            uplinkConfig: NativeAgentConfig.fromMap(uplinkConfigMap),
            downlinkAgentType: downlinkAgentType,
            downlinkConfig: NativeAgentConfig.fromMap(downlinkConfigMap),
            userLanguage: userLanguage,
            peerLanguage: peerLanguage
        )
    }

    private func codeFromMessage(_ msg: String, defaultCode: String) -> String {
        let prefix = msg.split(separator: ":").first.map(String.init) ?? ""
        return prefix.hasPrefix("translate.") ? prefix : defaultCode
    }
}

final class TranslateEventStreamHandler: NSObject, FlutterStreamHandler {
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
