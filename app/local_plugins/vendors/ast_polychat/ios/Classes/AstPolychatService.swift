import Foundation
import ai_plugin_interface
import os.log

/// PolyChat speech translation service (WebRTC transport).
///
/// Ports the Android `AstPolychatService`. Maps DataChannel
/// `trans_original` / `trans_translated` frames onto the AST 5-piece
/// recognition lifecycle, sharing a `requestId` across the two roles so the
/// orchestrator can pair source ↔ translation.
public final class AstPolychatService: NativeAstService {

    private static let log = OSLog(subsystem: "com.aiagent.ast_polychat", category: "Service")

    private let session = VoitransWebRtcSession()
    private weak var callback: AstCallback?

    private var currentRequestId: String?
    private var sourceRoleOpen = false
    private var translatedRoleOpen = false

    public init() {}

    deinit {
        session.release()
    }

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            os_log("initialize: invalid config json", log: Self.log, type: .error)
            return
        }
        let baseUrl = (cfg["baseUrl"] as? String) ?? ""
        VoitransWebRtcSession.warmupHttp(baseUrl: baseUrl)
        session.initialize(
            baseUrl: baseUrl,
            appId: (cfg["appId"] as? String) ?? "",
            appSecret: (cfg["appSecret"] as? String) ?? "",
            agentId: (cfg["agentId"] as? String) ?? ""
        )
    }

    public func connect(callback: AstCallback) {
        self.callback = callback
        resetRoundState()
        session.connect(handler: VoitransWebRtcSession.EventHandler(
            onConnected: {
                callback.onConnected()
            },
            onMessage: { [weak self] json in
                self?.handleDataChannelMessage(json)
            },
            onDisconnected: { [weak self] in
                self?.forceEndRound()
                callback.onDisconnected()
            },
            onError: { code, message in
                callback.onError(code: code, message: message)
            }
        ))
    }

    public func startAudio() {
        session.startAudio()
    }

    public func stopAudio() {
        session.stopAudio()
    }

    public func interrupt() {
        // WebRTC mode: server-side VAD handles barge-in.
    }

    public func release() {
        forceEndRound()
        session.release()
        callback = nil
    }

    // MARK: - DataChannel event mapping

    private func handleDataChannelMessage(_ json: [String: Any]) {
        guard let cb = callback else { return }
        let type = (json["type"] as? String) ?? ""
        switch type {
        case "user_speaking":
            beginRound(cb, force: true)
            openRole(cb, role: .source)

        case "trans_original":
            beginRound(cb)
            openRole(cb, role: .source)
            let text = (json["text"] as? String) ?? ""
            let done = (json["done"] as? Bool) ?? false
            if !text.isEmpty, let rid = currentRequestId {
                if done {
                    cb.onRecognized(role: .source, requestId: rid, text: text)
                    closeRole(cb, role: .source)
                    maybeEndRound(cb)
                } else {
                    cb.onRecognizing(role: .source, requestId: rid, text: text)
                }
            }

        case "trans_translated":
            beginRound(cb)
            openRole(cb, role: .translated)
            let text = (json["text"] as? String) ?? ""
            let done = (json["done"] as? Bool) ?? false
            if !text.isEmpty, let rid = currentRequestId {
                if done {
                    cb.onRecognized(role: .translated, requestId: rid, text: text)
                    closeRole(cb, role: .translated)
                    maybeEndRound(cb)
                } else {
                    cb.onRecognizing(role: .translated, requestId: rid, text: text)
                }
            }

        case "error":
            let message = (json["message"] as? String) ?? "Unknown error"
            let fatal = (json["fatal"] as? Bool) ?? false
            if fatal {
                cb.onError(code: "ast.fatal", message: message)
            } else {
                cb.onRecognitionError(requestId: currentRequestId, role: nil,
                                       code: "ast.error", message: message)
            }

        default:
            // session_state / mcp_tool_* / bot_response_* — not surfaced
            // through AstCallback.
            break
        }
    }

    // MARK: - Round state machine

    private func beginRound(_ cb: AstCallback, force: Bool = false) {
        if currentRequestId != nil {
            if !force { return }
            if sourceRoleOpen { closeRole(cb, role: .source) }
            if translatedRoleOpen { closeRole(cb, role: .translated) }
            endRound(cb)
        }
        currentRequestId = newRequestId()
    }

    private func openRole(_ cb: AstCallback, role: AstRole) {
        guard let rid = currentRequestId else { return }
        switch role {
        case .source:
            if !sourceRoleOpen {
                sourceRoleOpen = true
                cb.onRecognitionStart(role: role, requestId: rid)
            }
        case .translated:
            if !translatedRoleOpen {
                translatedRoleOpen = true
                cb.onRecognitionStart(role: role, requestId: rid)
            }
        }
    }

    private func closeRole(_ cb: AstCallback, role: AstRole) {
        guard let rid = currentRequestId else { return }
        switch role {
        case .source:
            if sourceRoleOpen {
                sourceRoleOpen = false
                cb.onRecognitionDone(role: role, requestId: rid)
            }
        case .translated:
            if translatedRoleOpen {
                translatedRoleOpen = false
                cb.onRecognitionDone(role: role, requestId: rid)
            }
        }
    }

    private func maybeEndRound(_ cb: AstCallback) {
        if sourceRoleOpen || translatedRoleOpen { return }
        if currentRequestId == nil { return }
        endRound(cb)
    }

    private func endRound(_ cb: AstCallback) {
        guard let rid = currentRequestId else { return }
        cb.onRecognitionEnd(requestId: rid)
        resetRoundState()
    }

    private func forceEndRound() {
        guard let cb = callback else {
            resetRoundState()
            return
        }
        if currentRequestId == nil { return }
        if sourceRoleOpen { closeRole(cb, role: .source) }
        if translatedRoleOpen { closeRole(cb, role: .translated) }
        endRound(cb)
    }

    private func resetRoundState() {
        currentRequestId = nil
        sourceRoleOpen = false
        translatedRoleOpen = false
    }

    private func newRequestId() -> String {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        let rand = String(UInt32.random(in: 0..<UInt32(1 << 30)), radix: 36)
        let padded = String(repeating: "0", count: max(0, 6 - rand.count)) + rand
        return "ast_polychat_\(ms)_\(padded)"
    }
}
