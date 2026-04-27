import Flutter
import Foundation
import OSLog

/// EventChannel (`ai_agent_client/log/native`) producer for iOS.
///
/// Two sources merged into one stream:
///   1. `OSLogStore` polling (iOS 15+) — captures `os_log` / `Logger` from app & linked SDKs
///   2. `stderr` redirect via `dup2` — captures `NSLog` / `print` fallbacks
///
/// Each event is a `[String: Any]`:
///   { source: "ios", subsystem?, category?, level, message, time }
final class NativeLogBridge: NSObject, FlutterStreamHandler {
    static let channel = "ai_agent_client/log/native"

    private var sink: FlutterEventSink?
    private var pollTimer: DispatchSourceTimer?
    private var lastStorePosition: Date = Date(timeIntervalSinceNow: -1)
    private var stderrReadSource: DispatchSourceRead?
    private var originalStderr: Int32 = -1

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        startOSLogPolling()
        startStderrCapture()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopOSLogPolling()
        stopStderrCapture()
        sink = nil
        return nil
    }

    // MARK: - OSLogStore polling

    private func startOSLogPolling() {
        guard #available(iOS 15.0, *) else { return }
        let queue = DispatchQueue(label: "native-log-bridge.oslog")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.drainOSLog()
        }
        pollTimer = timer
        timer.resume()
    }

    private func stopOSLogPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    @available(iOS 15.0, *)
    private func drainOSLog() {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = lastStorePosition
            let position = store.position(date: since)
            let predicate = NSPredicate(format: "composedMessage != nil")
            let entries = try store.getEntries(at: position, matching: predicate)
            var latest = since
            for raw in entries {
                guard let e = raw as? OSLogEntryLog else { continue }
                if e.date <= since { continue }
                if e.date > latest { latest = e.date }
                let payload: [String: Any] = [
                    "source": "ios",
                    "subsystem": e.subsystem,
                    "category": e.category,
                    "level": mapLevel(e.level),
                    "message": e.composedMessage,
                    "time": iso8601(e.date),
                ]
                emit(payload)
            }
            lastStorePosition = latest
        } catch {
            emit([
                "source": "ios",
                "level": "e",
                "message": "OSLogStore read failed: \(error.localizedDescription)",
            ])
            // Back off — stop polling to avoid flooding
            stopOSLogPolling()
        }
    }

    @available(iOS 15.0, *)
    private func mapLevel(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "d"
        case .info: return "i"
        case .notice: return "i"
        case .error: return "e"
        case .fault: return "f"
        case .undefined: return "i"
        @unknown default: return "i"
        }
    }

    // MARK: - stderr redirect

    private func startStderrCapture() {
        // Never redirect when a debugger is attached — lldb reads stderr itself.
        if isDebuggerAttached() { return }

        var pipeFds: [Int32] = [0, 0]
        guard pipe(&pipeFds) == 0 else { return }
        let readEnd = pipeFds[0]
        let writeEnd = pipeFds[1]

        // Duplicate original stderr so we can still print to Xcode console.
        originalStderr = dup(fileno(stderr))
        dup2(writeEnd, fileno(stderr))
        close(writeEnd)

        let src = DispatchSource.makeReadSource(fileDescriptor: readEnd, queue: .global(qos: .utility))
        src.setEventHandler { [weak self] in
            let available = Int(src.data)
            guard available > 0 else { return }
            var buffer = [UInt8](repeating: 0, count: available)
            let n = read(readEnd, &buffer, available)
            guard n > 0 else { return }
            let data = Data(buffer[0..<n])
            // Mirror to original stderr so Xcode still shows it
            if self?.originalStderr != -1 {
                _ = data.withUnsafeBytes { ptr in
                    write(self!.originalStderr, ptr.baseAddress, n)
                }
            }
            if let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    self?.emit([
                        "source": "ios",
                        "category": "stderr",
                        "level": "i",
                        "message": String(line),
                    ])
                }
            }
        }
        src.setCancelHandler {
            close(readEnd)
        }
        src.resume()
        stderrReadSource = src
    }

    private func stopStderrCapture() {
        stderrReadSource?.cancel()
        stderrReadSource = nil
        if originalStderr != -1 {
            dup2(originalStderr, fileno(stderr))
            close(originalStderr)
            originalStderr = -1
        }
    }

    private func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout.stride(ofValue: info)
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        if result != 0 { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }

    // MARK: - helpers

    private func emit(_ payload: [String: Any]) {
        guard let sink = sink else { return }
        DispatchQueue.main.async {
            sink(payload)
        }
    }

    private func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
