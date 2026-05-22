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
        session.connect(handler: VoitransWebRtcSession.EventHandler(
            onConnected: {
                callback.onConnected()
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
            cb.onStateChanged(state: "llm")

        case "bot_response":
            let text = (json["text"] as? String) ?? ""
            let done = (json["done"] as? Bool) ?? false
            // `bot_response.text` is a cumulative snapshot per round (both the
            // done=false interim frames and the done=true final frame). That
            // is exactly the `onChatPartialResult` contract, so forward it
            // as-is — the STS chat agent diffs against its own lastSentLength
            // and appends into a single assistant message (one bubble).
            //
            // Forwarding per-frame deltas through `onSentenceDone` (the old
            // behaviour) made every frame look like a finished sentence, so
            // one reply was split across many bubbles.
            if !text.isEmpty {
                cb.onChatPartialResult(cumulativeText: text)
            }
            // done=true: the reply is complete — close the current bubble.
            if done {
                cb.onSentenceDone(text: text)
            }

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
