import Flutter
import Foundation
import ai_plugin_interface
import os.log

/// 一个活跃的 AI 助理会话（iOS）—— 与 Android `AssistantSession` 对齐。
///
/// 通过 BinaryMessenger 与 device_jieli 通信：
///   - 控制：`device_jieli/method` MethodChannel（assistantPortEnter / Exit / ReportPlayback）
///   - 上行：NotificationCenter `JieliAssistantPortAudio` / `JieliAssistantPortError`
///
/// 这样避免了 Pod↔SPM 的 Swift 模块导入问题。
final class AssistantSession {

    private static let log = OSLog(subsystem: "com.aiagent.assistant_server", category: "Session")
    private static let connectTimeoutSec: TimeInterval = 10

    let sessionId: String
    private let request: AssistantRequest
    private let emit: ([String: Any?]) -> Void
    private let deviceMethod: FlutterMethodChannel

    private let scope = DispatchQueue(label: "AssistantSession.\(UUID().uuidString)", qos: .userInitiated)

    private var agent: NativeAgent?
    private var sink: AssistantSinkAdapter?
    private var audioObserver: NSObjectProtocol?
    private var errorObserver: NSObjectProtocol?
    private let ttsSink: TtsSink

    private enum State { case starting, active, stopping, stopped, error }
    private let stateLock = NSLock()
    private var state: State = .starting

    init(sessionId: String, request: AssistantRequest,
         deviceMethod: FlutterMethodChannel,
         emit: @escaping ([String: Any?]) -> Void) {
        self.sessionId = sessionId
        self.request = request
        self.deviceMethod = deviceMethod
        self.emit = emit
        self.ttsSink = TtsSink(deviceMethod: deviceMethod)
    }

    /// 启动会话；失败抛 AssistantSessionError，Core 负责 emit error。
    func start() {
        scope.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.startBlocking()
            } catch {
                let code: String
                if let err = error as? AssistantSessionError { code = err.code }
                else { code = "assistant.start_failed" }
                self.markError(code: code, message: "\(error)")
            }
        }
    }

    private func startBlocking() throws {
        // 1. 创建 agent 实例（agents_server 同等机制，按 agentType 工厂创建）
        let a = try NativeAgentRegistry.shared.create(request.agentType)
        self.agent = a

        // 2. SinkAdapter 把 agent 事件路由到 assistant_server EventChannel
        let s = AssistantSinkAdapter(sessionId: sessionId, emit: emit)
        self.sink = s
        a.initialize(config: request.agentConfig, eventSink: s)

        // 3. connectService（云端建链）+ 等 onAgentReady
        a.connectService()
        do {
            try s.awaitReady(timeout: Self.connectTimeoutSec)
        } catch {
            throw error
        }

        // 4. 校验 agent 外部音频能力（必须 acceptsPcm）
        let cap = a.externalAudioCapability()
        guard cap.acceptsPcm else {
            throw AssistantSessionError.agentUnsupported(message: "agent doesn't accept PCM external audio")
        }

        // 5. 注册 NotificationCenter observer —— 接 device_jieli 端口推上来的音频帧
        let nc = NotificationCenter.default
        audioObserver = nc.addObserver(forName: Notification.Name("JieliAssistantPortAudio"),
                                       object: nil, queue: nil) { [weak self] note in
            guard let self = self, let info = note.userInfo,
                  let pcm = info["pcm"] as? Data,
                  let agent = self.agent else { return }
            agent.pushExternalAudioFrame(pcm)
        }
        errorObserver = nc.addObserver(forName: Notification.Name("JieliAssistantPortError"),
                                       object: nil, queue: nil) { [weak self] note in
            guard let self = self, let info = note.userInfo else { return }
            let code = (info["code"] as? String) ?? "device.error"
            let msg  = (info["message"] as? String) ?? ""
            self.emit(AssistantEvents.error(sessionId: self.sessionId, code: code, message: msg))
        }

        // 6. 启动 agent 的外部音频通路 + TTS 反向 sink
        let format = ExternalAudioFormat.pcmS16LE16kMono20ms
        do {
            try a.startExternalAudio(format: format, sink: ttsSink)
        } catch {
            throw AssistantSessionError.agentUnsupported(message: "startExternalAudio failed: \(error)")
        }

        // 7. 进入设备端 port —— 此后耳机帧会通过 Notification 派发到我们的 observer
        let result = invokeDeviceMethodSync(
            method: "assistantPortEnter",
            args: ["sampleRate": NSNumber(value: 16000)]
        )
        if case .failure(let err) = result {
            throw AssistantSessionError.enterFailed(message: err.localizedDescription)
        }

        stateLock.lock(); state = .active; stateLock.unlock()
        emit(AssistantEvents.sessionState(sessionId: sessionId, state: "active"))
        os_log("session=%{public}@ active", log: Self.log, type: .debug, sessionId)
    }

    /// 停止会话；幂等。
    func stop() {
        stateLock.lock()
        if state == .stopped || state == .stopping {
            stateLock.unlock(); return
        }
        state = .stopping
        stateLock.unlock()

        emit(AssistantEvents.sessionState(sessionId: sessionId, state: "stopping"))

        scope.async { [weak self] in
            guard let self = self else { return }
            // 反注册 NotificationCenter
            if let o = self.audioObserver { NotificationCenter.default.removeObserver(o) }
            if let o = self.errorObserver { NotificationCenter.default.removeObserver(o) }
            self.audioObserver = nil
            self.errorObserver = nil

            // 退出 device port
            _ = self.invokeDeviceMethodSync(method: "assistantPortExit", args: [:])

            // 释放 agent
            self.agent?.stopExternalAudio()
            self.agent?.disconnectService()
            self.agent?.release()
            self.agent = nil
            self.sink = nil

            self.stateLock.lock(); self.state = .stopped; self.stateLock.unlock()
            self.emit(AssistantEvents.sessionState(sessionId: self.sessionId, state: "stopped"))
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
        emit(AssistantEvents.error(sessionId: sessionId, code: code, message: message, fatal: true))
        emit(AssistantEvents.sessionState(sessionId: sessionId, state: "error", errorMessage: message))
        stop()
    }

    // MARK: - Device MethodChannel sync invocation

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

/// AI agent 的 TTS PCM → device_jieli 端口回灌 sink。
private final class TtsSink: ExternalAudioSink {
    private weak var deviceMethod: FlutterMethodChannel?

    init(deviceMethod: FlutterMethodChannel) {
        self.deviceMethod = deviceMethod
    }

    func onTtsFrame(_ frame: ExternalAudioFrame) {
        guard frame.codec == .pcmS16LE else { return }
        let dm = deviceMethod
        // 投递到主线程（FlutterMethodChannel 要求 main）
        let args: [String: Any] = [
            "pcm": FlutterStandardTypedData(bytes: frame.bytes),
            "sampleRate": NSNumber(value: frame.sampleRate),
            "channels": NSNumber(value: frame.channels),
            "final": frame.isFinal,
        ]
        DispatchQueue.main.async {
            dm?.invokeMethod("assistantPortReportPlayback", arguments: args, result: nil)
        }
    }

    func onError(code: String, message: String) {
        // 暴露给上层的 error 由 SinkAdapter 处理；这里只记日志。
        os_log("TtsSink error: %{public}@ %{public}@", log: OSLog.default, type: .error, code, message)
    }
}

/// startAssistant 入参。
struct AssistantRequest {
    let agentType: String
    let agentConfig: NativeAgentConfig
    let userLanguage: String
}
