import Foundation
import AVFoundation
import BackgroundTasks

/// AgentRuntimeManager — iOS 后台保活 + 多会话管理
///
/// 使用 AVAudioSession（Background Audio）使 App 在后台继续运行。
/// 每个 AgentSession 作为独立的 Swift actor 运行。
actor AgentRuntimeManager {
    static let shared = AgentRuntimeManager()

    var eventSink: AgentEventSink?

    private var sessions: [String: AgentSession] = [:]
    private var audioSessionConfigured = false

    // ─────────────────────────────────────────────────
    // Session 管理
    // ─────────────────────────────────────────────────

    func startSession(config: AgentSessionConfig) {
        guard sessions[config.sessionId] == nil else { return }
        configureAudioSessionIfNeeded()

        let db = AppDatabase.shared
        guard let sink = eventSink else { return }

        let session = AgentSession(
            sessionId: config.sessionId,
            config: config,
            db: db,
            eventSink: sink
        )
        sessions[config.sessionId] = session
    }

    func stopSession(sessionId: String) {
        if let session = sessions.removeValue(forKey: sessionId) {
            session.release()
        }
        if sessions.isEmpty {
            deactivateAudioSession()
        }
    }

    func sendText(sessionId: String, requestId: String, text: String) {
        sessions[sessionId]?.sendText(requestId: requestId, text: text)
    }

    func interrupt(sessionId: String) {
        sessions[sessionId]?.interrupt()
    }

    func setInputMode(sessionId: String, mode: String) {
        sessions[sessionId]?.setInputMode(mode)
    }

    // ─────────────────────────────────────────────────
    // AVAudioSession 后台保活
    // ─────────────────────────────────────────────────

    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            audioSessionConfigured = true
        } catch {
            print("[AgentRuntimeManager] AVAudioSession error: \(error)")
        }
    }

    private func deactivateAudioSession() {
        guard audioSessionConfigured else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionConfigured = false
        } catch {
            print("[AgentRuntimeManager] deactivateAudioSession error: \(error)")
        }
    }
}
