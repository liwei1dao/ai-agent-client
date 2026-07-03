import Flutter
import Foundation
import ai_plugin_interface
import os.log

/// 一个活跃的通话翻译会话（iOS）—— 与 Android `CallTranslationSession` 对齐。
///
/// 通过 BinaryMessenger 与 device_jieli 通信：
///   - 控制：`device_jieli/method` MethodChannel
///     (callTranslationPortEnter / Exit / ReportTranslated)
///   - 上行：NotificationCenter `JieliCallTranslationPortAudio` / `JieliCallTranslationPortError`
///
/// 两条 leg agent：uplink (用户说→对方听)、downlink (对方说→用户听)。
final class CallTranslationSession {

    private static let log = OSLog(subsystem: "com.aiagent.translate_server", category: "CallSession")
    private static let connectTimeoutSec: TimeInterval = 10

    let sessionId: String
    private let request: CallTranslationRequest
    private let emit: ([String: Any?]) -> Void
    private let deviceMethod: FlutterMethodChannel

    private let scope = DispatchQueue(label: "CallTranslationSession.\(UUID().uuidString)", qos: .userInitiated)

    private var uplinkAgent: NativeAgent?
    private var downlinkAgent: NativeAgent?
    private var uplinkSink: AgentSinkAdapter?
    private var downlinkSink: AgentSinkAdapter?

    private var audioObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?

    private let uplinkTtsSink: TtsSink
    private let downlinkTtsSink: TtsSink

    private enum State { case starting, active, stopping, stopped, error }
    private let stateLock = NSLock()
    private var state: State = .starting

    init(sessionId: String, request: CallTranslationRequest,
         deviceMethod: FlutterMethodChannel,
         emit: @escaping ([String: Any?]) -> Void) {
        self.sessionId = sessionId
        self.request = request
        self.deviceMethod = deviceMethod
        self.emit = emit
        self.uplinkTtsSink = TtsSink(leg: .uplink, deviceMethod: deviceMethod)
        self.downlinkTtsSink = TtsSink(leg: .downlink, deviceMethod: deviceMethod)
    }

    func start() {
        scope.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startBlocking()
            } catch {
                let code: String
                if let err = error as? TranslateSessionError { code = err.code }
                else { code = "translate.start_failed" }
                self.markError(code: code, message: "\(error)")
            }
        }
    }

    private func startBlocking() throws {
        // 1. 创建两条 leg 的 agent
        let up = try NativeAgentRegistry.shared.create(request.uplinkAgentType)
        let down = try NativeAgentRegistry.shared.create(request.downlinkAgentType)
        self.uplinkAgent = up
        self.downlinkAgent = down

        let upSink = AgentSinkAdapter(sessionId: sessionId, leg: .uplink, emit: emit)
        let downSink = AgentSinkAdapter(sessionId: sessionId, leg: .downlink, emit: emit)
        self.uplinkSink = upSink
        self.downlinkSink = downSink

        up.initialize(config: request.uplinkConfig, eventSink: upSink)
        down.initialize(config: request.downlinkConfig, eventSink: downSink)

        // 2. 端到端 agent 需先 connectService 建链 + 等 onAgentReady
        up.connectService()
        down.connectService()
        do {
            try upSink.awaitReady(timeout: Self.connectTimeoutSec)
            try downSink.awaitReady(timeout: Self.connectTimeoutSec)
        } catch {
            throw error
        }

        // 3. 校验外部音频能力
        guard up.externalAudioCapability().acceptsPcm else {
            throw TranslateSessionError.agentUnsupported(message: "uplink agent doesn't accept PCM")
        }
        guard down.externalAudioCapability().acceptsPcm else {
            throw TranslateSessionError.agentUnsupported(message: "downlink agent doesn't accept PCM")
        }

        // 4. 启动外部音频通路 + TTS 反向 sink
        let format = ExternalAudioFormat.pcmS16LE16kMono20ms
        do {
            try up.startExternalAudio(format: format, sink: uplinkTtsSink)
            try down.startExternalAudio(format: format, sink: downlinkTtsSink)
        } catch {
            throw TranslateSessionError.agentUnsupported(message: "startExternalAudio failed: \(error)")
        }

        // 5. 订阅 device 端口上行音频帧 —— NotificationCenter（device_jieli SPM 派发）
        let nc = NotificationCenter.default
        audioObserver = nc.addObserver(forName: Notification.Name("JieliCallTranslationPortAudio"),
                                       object: nil, queue: nil) { [weak self] note in
            guard let self = self, let info = note.userInfo,
                  let pcm = info["pcm"] as? Data,
                  let legStr = info["leg"] as? String else { return }
            let agent = (legStr == "downlink") ? self.downlinkAgent : self.uplinkAgent
            agent?.pushExternalAudioFrame(pcm)
        }
        errorObserver = nc.addObserver(forName: Notification.Name("JieliCallTranslationPortError"),
                                       object: nil, queue: nil) { [weak self] note in
            guard let self = self, let info = note.userInfo else { return }
            let code = (info["code"] as? String) ?? "device.error"
            let msg  = (info["message"] as? String) ?? ""
            self.emit(TranslateEvents.error(sessionId: self.sessionId, code: code, message: msg))
        }

        // 6. 进入设备端 port
        let result = invokeDeviceMethodSync(
            method: "callTranslationPortEnter",
            args: ["sampleRate": NSNumber(value: 16000)]
        )
        if case .failure(let err) = result {
            throw TranslateSessionError.enterFailed(message: err.localizedDescription)
        }

        stateLock.lock(); state = .active; stateLock.unlock()
        emit(TranslateEvents.sessionState(sessionId: sessionId, state: "active"))
        os_log("session=%{public}@ active", log: Self.log, type: .debug, sessionId)
    }

    func stop() {
        stateLock.lock()
        if state == .stopped || state == .stopping {
            stateLock.unlock(); return
        }
        state = .stopping
        stateLock.unlock()

        emit(TranslateEvents.sessionState(sessionId: sessionId, state: "stopping"))

        scope.async { [weak self] in
            guard let self = self else { return }
            if let o = self.audioObserver { NotificationCenter.default.removeObserver(o) }
            if let o = self.errorObserver { NotificationCenter.default.removeObserver(o) }
            self.audioObserver = nil
            self.errorObserver = nil

            _ = self.invokeDeviceMethodSync(method: "callTranslationPortExit", args: [:])

            self.uplinkAgent?.stopExternalAudio()
            self.downlinkAgent?.stopExternalAudio()
            self.uplinkAgent?.disconnectService()
            self.downlinkAgent?.disconnectService()
            self.uplinkAgent?.release()
            self.downlinkAgent?.release()
            self.uplinkAgent = nil
            self.downlinkAgent = nil
            self.uplinkSink = nil
            self.downlinkSink = nil

            self.stateLock.lock(); self.state = .stopped; self.stateLock.unlock()
            self.emit(TranslateEvents.sessionState(sessionId: self.sessionId, state: "stopped"))
            os_log("session=%{public}@ stopped", log: Self.log, type: .debug, self.sessionId)
        }
    }

    func markError(code: String, message: String) {
        stateLock.lock()
        if state == .stopped || state == .error {
            stateLock.unlock(); return
        }
        state = .error
        stateLock.unlock()
        emit(TranslateEvents.error(sessionId: sessionId, code: code, message: message, fatal: true))
        emit(TranslateEvents.sessionState(sessionId: sessionId, state: "error", errorMessage: message))
        stop()
    }

    @discardableResult
    private func invokeDeviceMethodSync(method: String, args: [String: Any]) -> Result<Any?, NSError> {
        let sem = DispatchSemaphore(value: 0)
        var resultBox: Result<Any?, NSError> = .success(nil)
        DispatchQueue.main.async {
            self.deviceMethod.invokeMethod(method, arguments: args) { res in
                if let err = res as? FlutterError {
                    resultBox = .failure(NSError(
                        domain: "device_jieli", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "\(err.code): \(err.message ?? "")"]
                    ))
                } else {
                    resultBox = .success(res)
                }
                sem.signal()
            }
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            return .failure(NSError(domain: "device_jieli", code: -2,
                                    userInfo: [NSLocalizedDescriptionKey: "method \(method) timeout"]))
        }
        return resultBox
    }
}

/// 译文 PCM → device 端口回灌（按 leg）。
private final class TtsSink: ExternalAudioSink {
    private let leg: CallLeg
    private weak var deviceMethod: FlutterMethodChannel?

    init(leg: CallLeg, deviceMethod: FlutterMethodChannel) {
        self.leg = leg
        self.deviceMethod = deviceMethod
    }

    func onTtsFrame(_ frame: ExternalAudioFrame) {
        guard frame.codec == .pcmS16LE else { return }
        let dm = deviceMethod
        let args: [String: Any] = [
            "leg": leg.rawValue,
            "pcm": FlutterStandardTypedData(bytes: frame.bytes),
            "sampleRate": NSNumber(value: frame.sampleRate),
            "channels": NSNumber(value: frame.channels),
            "final": frame.isFinal,
        ]
        DispatchQueue.main.async {
            dm?.invokeMethod("callTranslationPortReportTranslated", arguments: args, result: nil)
        }
    }

    func onError(code: String, message: String) {
        os_log("TtsSink[%{public}@] error: %{public}@ %{public}@",
               log: OSLog.default, type: .error, leg.rawValue, code, message)
    }
}

struct CallTranslationRequest {
    let uplinkAgentType: String
    let uplinkConfig: NativeAgentConfig
    let downlinkAgentType: String
    let downlinkConfig: NativeAgentConfig
    let userLanguage: String
    let peerLanguage: String
}
