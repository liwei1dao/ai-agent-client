import Foundation
import ai_plugin_interface
import os.log

/// PolyChat speech-to-speech service (WebRTC transport).
///
/// Ports the Android `StsPolychatService`. The session itself lives in
/// `VoitransWebRtcSession`; this class only maps DataChannel JSON events
/// onto `StsCallback`.
public final class StsPolychatService: NativeStsService {

    private static let log = OSLog(subsystem: "com.aiagent.sts_polychat", category: "Service")

    private let session = VoitransWebRtcSession()
    private weak var callback: StsCallback?

    /// Bot response cumulative text. Cleared at each `bot_response_start`.
    /// The server pushes `bot_response.text` as a *cumulative snapshot*
    /// rather than a delta — we must compute the diff before forwarding.
    private var botBuffer = ""

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

    public func connect(callback: StsCallback) {
        self.callback = callback
        botBuffer = ""
        session.connect(handler: VoitransWebRtcSession.EventHandler(
            onConnected: { [weak self] in
                callback.onConnected()
                self?.botBuffer = ""
            },
            onMessage: { [weak self] json in
                self?.handleDataChannelMessage(json)
            },
            onDisconnected: {
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
        // WebRTC mode: the bot audio is played by the remote audio track.
        // Barge-in is driven by `user_speaking` server-side, so nothing to
        // do here.
    }

    public func release() {
        session.release()
        callback = nil
    }

    // MARK: - DataChannel event mapping

    private func handleDataChannelMessage(_ json: [String: Any]) {
        guard let cb = callback else { return }
        let type = (json["type"] as? String) ?? ""
        switch type {
        case "user_speaking":
            cb.onSpeechStart()

        case "user_transcription":
            let text = (json["text"] as? String) ?? ""
            let done = (json["done"] as? Bool) ?? false
            if done {
                cb.onSttFinalResult(text: text)
            } else {
                cb.onSttPartialResult(text: text)
            }

        case "bot_response_start":
            botBuffer = ""
            cb.onStateChanged(state: "llm")

        case "bot_response":
            let text = (json["text"] as? String) ?? ""
            let done = (json["done"] as? Bool) ?? false
            // Server-sent text is *cumulative* per round. Convert to a
            // delta before forwarding; the upstream `firstToken` handler
            // appends, not overwrites.
            if !text.isEmpty {
                let delta: String
                if text.hasPrefix(botBuffer) {
                    delta = String(text.dropFirst(botBuffer.count))
                } else {
                    delta = text
                }
                if !delta.isEmpty {
                    botBuffer = text
                    cb.onSentenceDone(text: delta)
                }
            }
            if done { botBuffer = "" }

        case "ai_response_done", "ai_speaking":
            cb.onStateChanged(state: "playing")

        case "ai_stopped":
            cb.onStateChanged(state: "idle")

        case "session_state":
            let state = (json["state"] as? String) ?? ""
            cb.onStateChanged(state: state)

        case "error":
            let message = (json["message"] as? String) ?? "Unknown error"
            let fatal = (json["fatal"] as? Bool) ?? false
            cb.onError(code: fatal ? "fatal" : "error", message: message)

        case "disconnect_warning":
            os_log("Disconnect warning: %{public}@",
                   log: Self.log, type: .info,
                   (json["reason"] as? String) ?? "")

        default:
            break
        }
    }
}
