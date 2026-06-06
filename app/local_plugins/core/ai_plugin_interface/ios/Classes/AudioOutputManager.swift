import Foundation
import AVFoundation
import os.log

/// Global audio-routing manager (iOS counterpart of the Android Kotlin
/// `AudioOutputManager`).
///
/// On iOS routing is done via `AVAudioSession.overrideOutputAudioPort` and
/// preferred-input selection — no equivalent of Android's
/// `setCommunicationDevice` exists. We map the three logical modes as:
///   - `earpiece`: do nothing extra; the receiver is the default route for
///     `.playAndRecord` / `.voiceChat`.
///   - `speaker`:  `overrideOutputAudioPort(.speaker)`.
///   - `auto`:     keep the system route — if a wired/Bluetooth headset is
///     present iOS already routes through it, otherwise we promote to speaker
///     so chat without a headset is usable.
public final class AudioOutputManager {
    public static let shared = AudioOutputManager()

    public enum Mode {
        case earpiece
        case speaker
        case auto
    }

    private let logger = OSLog(subsystem: "com.aiagent.plugin_interface", category: "AudioOutputManager")
    private let lock = NSLock()
    private var mode: Mode = .auto

    private init() {
        // 监听音频中断（来电 / 被其它 app 抢占）。中断结束后必须重新激活会话，
        // 否则后台保活依赖的"音频会话持续 active"被打断 → app 在后台被挂起、AI 对话中断。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            os_log("audio interruption began (session deactivated by system)",
                   log: logger, type: .info)
        case .ended:
            // 中断结束：系统已停用会话，重新 applyMode() 恢复 category + setActive(true)，
            // 保住后台保活所需的活跃音频会话。失败由 applyMode 内部 catch 记录。
            os_log("audio interruption ended → re-activating session",
                   log: logger, type: .info)
            DispatchQueue.main.async { [weak self] in self?.applyMode() }
        @unknown default:
            break
        }
    }

    public var currentMode: Mode {
        lock.lock(); defer { lock.unlock() }
        return mode
    }

    /// Set the desired mode and apply it immediately.
    public func setMode(_ mode: Mode) {
        lock.lock(); self.mode = mode; lock.unlock()
        os_log("setMode: %{public}@", log: logger, type: .debug, String(describing: mode))
        applyMode()
    }

    /// Apply the active mode using a "communication" category (chat/voice).
    public func applyMode() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true, options: [])
        } catch {
            os_log("setCategory failed: %{public}@",
                   log: logger, type: .error, error.localizedDescription)
        }

        switch currentMode {
        case .earpiece:
            do {
                try session.overrideOutputAudioPort(.none)
                os_log("Applied: earpiece", log: logger, type: .debug)
            } catch {
                os_log("overrideOutputAudioPort(none) failed: %{public}@",
                       log: logger, type: .error, error.localizedDescription)
            }
        case .speaker:
            do {
                try session.overrideOutputAudioPort(.speaker)
                os_log("Applied: speaker", log: logger, type: .debug)
            } catch {
                os_log("overrideOutputAudioPort(speaker) failed: %{public}@",
                       log: logger, type: .error, error.localizedDescription)
            }
        case .auto:
            if isHeadsetConnected() {
                do {
                    try session.overrideOutputAudioPort(.none)
                    os_log("Applied: auto → headset (none override)",
                           log: logger, type: .debug)
                } catch {
                    os_log("auto/headset override failed: %{public}@",
                           log: logger, type: .error, error.localizedDescription)
                }
            } else {
                do {
                    try session.overrideOutputAudioPort(.speaker)
                    os_log("Applied: auto → speaker (no headset)",
                           log: logger, type: .debug)
                } catch {
                    os_log("auto/speaker override failed: %{public}@",
                           log: logger, type: .error, error.localizedDescription)
                }
            }
        }
    }

    /// WebRTC-only variant. On Android it bypasses `setCommunicationDevice`
    /// to avoid resetting the engine's `AudioRecord`. iOS has no equivalent
    /// of that pitfall, so we just delegate to `applyMode()`.
    public func applyModeForWebRtc() {
        applyMode()
    }

    private func isHeadsetConnected() -> Bool {
        let route = AVAudioSession.sharedInstance().currentRoute
        for output in route.outputs {
            switch output.portType {
            case .headphones,
                 .bluetoothA2DP,
                 .bluetoothLE,
                 .bluetoothHFP,
                 .usbAudio,
                 .lineOut:
                return true
            default:
                continue
            }
        }
        return false
    }
}
