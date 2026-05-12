import Foundation
import ai_plugin_interface
import os.log

/// Volcengine realtime speech-to-speech (dialogue) service.
///
/// Ports the Android `StsVolcengineService`. Protocol summary:
///   - WebSocket  `wss://openspeech.bytedance.com/api/v3/realtime/dialogue`
///   - Each WS frame = 4-byte header + variable body (event [+ sessionId]
///     + gzip(payload))
///   - Handshake: `StartConnection` (1) → `ConnectionStarted` (50) →
///     `StartSession` (100, carries client-generated UUID) →
///     `SessionStarted` (150) → audio frames (200) flow.
///   - TTS PCM arrives as `TYPE_AUDIO_SERVER` frames at 24 kHz mono S16LE.
///
/// External-audio mode (call translation / AI assistant): the orchestrator
/// pushes 16 kHz mono S16LE frames in via `pushExternalAudioFrame(_:)`; this
/// service downsamples server TTS (24 → 16 kHz) and pipes it to the supplied
/// `ExternalAudioSink` instead of the local speaker.
public final class StsVolcengineService: NativeStsService {

    private static let log = OSLog(subsystem: "com.aiagent.sts_volcengine", category: "Service")

    // MARK: Constants

    private static let micSampleRate = 16_000
    private static let ttsSampleRate = 24_000
    private static let wsUrl =
        "wss://openspeech.bytedance.com/api/v3/realtime/dialogue"

    // Fixed SDK platform identifiers (not user-configurable).
    private static let fixedResourceId = "volc.speech.dialog"
    private static let fixedAppKey     = "PlgvMymc7f3tQnJ6"

    // Binary frame layout.
    private static let headerB0: UInt8 = 0x11
    private static let typeFullClient:  UInt8 = 0x10
    private static let typeAudioClient: UInt8 = 0x20
    private static let typeFullServer:  UInt8 = 0x90
    private static let typeAudioServer: UInt8 = 0xB0
    private static let typeError:       UInt8 = 0xF0
    private static let flagWithEvent:   UInt8 = 0x04
    private static let flagNegSequence: UInt8 = 0x02
    private static let serJson:         UInt8 = 0x10
    private static let compressGzip:    UInt8 = 0x01
    private static let hdr2JsonGzip:    UInt8 = 0x11  // SER_JSON | COMPRESS_GZIP
    private static let hdr2RawGzip:     UInt8 = 0x01  // SER_NONE | COMPRESS_GZIP

    // Client event codes.
    private static let evtStartConnection  = 1
    private static let evtFinishConnection = 2
    private static let evtStartSession     = 100
    private static let evtFinishSession    = 102
    private static let evtSendAudio        = 200

    // Server event codes.
    private static let evtConnectionStarted  = 50
    private static let evtConnectionFailed   = 51
    private static let evtConnectionFinished = 52
    private static let evtSessionStarted     = 150
    private static let evtSessionFinOk       = 152
    private static let evtSessionFinErr      = 153
    private static let evtTtsType            = 350
    private static let evtTtsEnded           = 359
    private static let evtClearAudio         = 450
    private static let evtAsrResponse        = 451
    private static let evtUserQueryEnded     = 459
    private static let evtChatResponse       = 550
    private static let evtChatEnded          = 559

    private static let noSessionEvents: Set<Int> = [evtStartConnection, evtFinishConnection]

    // MARK: Configuration

    private var appId: String = ""
    private var accessToken: String = ""
    private var speaker: String = "zh_female_vv_jupiter_bigtts"
    private var systemPrompt: String =
        "你是一个友好、专业的 AI 语音助手，请用简洁的语言回答用户的问题。"

    // MARK: State

    private weak var callback: StsCallback?
    private let stateLock = NSLock()
    private let urlSession: URLSession
    private var wsTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    private var isRunning = false
    private var isConnected = false
    private var isAudioRunning = false
    private var remoteSessionId = ""

    private var externalMode = false
    private weak var externalSink: ExternalAudioSink?

    private var chatResponseBuffer = ""

    // Handshake signals.
    private var connectionStartedContinuation: CheckedContinuation<Void, Error>?
    private var sessionStartedContinuation: CheckedContinuation<Void, Error>?

    private let audioIO = PcmAudioIO()

    // MARK: - Lifecycle

    public init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 0
        self.urlSession = URLSession(configuration: cfg)
    }

    deinit {
        release()
    }

    public func initialize(configJson: String) {
        guard let data = configJson.data(using: .utf8),
              let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            os_log("initialize: invalid config json", log: Self.log, type: .error)
            return
        }
        appId = (cfg["appId"] as? String) ?? ""
        accessToken = (cfg["accessToken"] as? String) ?? ""
        let voice = (cfg["voiceType"] as? String) ?? ""
        speaker = voice.isEmpty ? "zh_female_vv_jupiter_bigtts" : voice
        let sp = (cfg["systemPrompt"] as? String) ?? ""
        if !sp.isEmpty { systemPrompt = sp }
        os_log("initialize: appId=%{public}@ speaker=%{public}@",
               log: Self.log, type: .debug, appId, speaker)
    }

    public func connect(callback: StsCallback) {
        self.callback = callback
        guard !appId.isEmpty, !accessToken.isEmpty else {
            os_log("STS config missing: appId=%{public}@ token=%{public}@",
                   log: Self.log, type: .error,
                   String(appId.isEmpty), String(accessToken.isEmpty))
            callback.onError(code: "config_error", message: "appId or accessToken missing")
            return
        }

        Task { await runConnect(callback: callback) }
    }

    private func runConnect(callback: StsCallback) async {
        os_log("connect(): appId=%{public}@ speaker=%{public}@ externalMode=%{public}@",
               log: Self.log, type: .debug, appId, speaker,
               String(describing: externalMode))
        isRunning = true
        remoteSessionId = UUID().uuidString

        guard let url = URL(string: Self.wsUrl) else {
            callback.onError(code: "config_error", message: "invalid ws url")
            return
        }
        var request = URLRequest(url: url)
        request.setValue(Self.fixedResourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(Self.fixedAppKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(appId, forHTTPHeaderField: "X-Api-App-ID")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Api-Connect-Id")

        let task = urlSession.webSocketTask(with: request)
        wsTask = task
        task.resume()

        receiveLoopTask = Task { [weak self] in await self?.runReceiveLoop(task: task) }

        do {
            try await withTimeout(seconds: 10) { [weak self] in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self?.stateLock.lock()
                    self?.connectionStartedContinuation = cont
                    self?.stateLock.unlock()
                    self?.sendJsonFrame(event: Self.evtStartConnection, jsonPayload: "{}")
                }
            }
            os_log("ConnectionStarted, sending StartSession sid=%{public}@",
                   log: Self.log, type: .debug, remoteSessionId)

            try await withTimeout(seconds: 10) { [weak self] in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self?.stateLock.lock()
                    self?.sessionStartedContinuation = cont
                    self?.stateLock.unlock()
                    self?.sendJsonFrame(event: Self.evtStartSession, jsonPayload: self?.buildSessionPayload() ?? "{}")
                }
            }
            isConnected = true
            callback.onConnected()
            callback.onStateChanged(state: "idle")
        } catch {
            isRunning = false
            isConnected = false
            os_log("STS connect failed: %{public}@", log: Self.log, type: .error,
                   error.localizedDescription)
            callback.onError(code: "sts_error", message: error.localizedDescription)
        }
    }

    public func startAudio() {
        guard isConnected, !isAudioRunning else {
            os_log("startAudio: skip (connected=%{public}@ audioRunning=%{public}@)",
                   log: Self.log, type: .debug,
                   String(isConnected), String(isAudioRunning))
            return
        }
        if externalMode {
            os_log("startAudio: skip (externalMode active)", log: Self.log, type: .info)
            return
        }
        AudioOutputManager.shared.applyMode()
        isAudioRunning = true
        audioIO.startMic { [weak self] frame in
            self?.sendAudioFrame(frame)
        }
        callback?.onStateChanged(state: "listening")
    }

    public func stopAudio() {
        os_log("stopAudio()", log: Self.log, type: .debug)
        isAudioRunning = false
        audioIO.stopMic()
        audioIO.flushTts()
        callback?.onStateChanged(state: "idle")
    }

    public func interrupt() {
        os_log("interrupt() — flush TTS", log: Self.log, type: .debug)
        audioIO.flushTts()
    }

    public func release() {
        os_log("release()", log: Self.log, type: .debug)
        stopAudio()
        stopExternalAudio()
        isRunning = false
        isConnected = false

        let sid = remoteSessionId
        if !sid.isEmpty {
            sendJsonFrame(event: Self.evtFinishSession, jsonPayload: "{}")
        }
        remoteSessionId = ""
        sendJsonFrame(event: Self.evtFinishConnection, jsonPayload: "{}")
        wsTask?.cancel(with: .normalClosure, reason: nil)
        wsTask = nil
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        audioIO.release()

        callback?.onDisconnected()
        callback = nil
    }

    // MARK: - External audio

    public func externalAudioCapability() -> ExternalAudioCapability {
        ExternalAudioCapability(
            acceptsOpus: false,
            acceptsPcm: true,
            preferredSampleRate: Self.micSampleRate,
            preferredChannels: 1,
            preferredFrameMs: 20
        )
    }

    public func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        if format.codec != .pcmS16LE {
            throw NativeServiceError.unsupported(
                "sts_volcengine accepts only PCM_S16LE (got \(format.codec))")
        }
        if format.sampleRate != Self.micSampleRate || format.channels != 1 {
            throw NativeServiceError.unsupported(
                "sts_volcengine requires \(Self.micSampleRate)Hz mono " +
                "(got \(format.sampleRate)Hz/\(format.channels)ch)")
        }
        if !isConnected {
            throw NativeServiceError.invalidConfig(
                "sts_volcengine not connected; call connect() first")
        }
        if isAudioRunning {
            os_log("startExternalAudio: stopping self-mic before takeover",
                   log: Self.log, type: .debug)
            stopAudio()
        }
        externalSink = sink
        externalMode = true
        os_log("startExternalAudio: PCM_S16LE %dHz mono %dms",
               log: Self.log, type: .debug,
               format.sampleRate, format.frameMs)
    }

    public func pushExternalAudioFrame(_ frame: Data) {
        if !externalMode || !isConnected || frame.isEmpty { return }
        sendAudioFrame(frame)
    }

    public func stopExternalAudio() {
        if !externalMode { return }
        externalMode = false
        externalSink = nil
        os_log("stopExternalAudio", log: Self.log, type: .debug)
    }

    // MARK: - Frame encode

    private func sendJsonFrame(event: Int, jsonPayload: String) {
        guard let bodyRaw = jsonPayload.data(using: .utf8),
              let body = try? Gzip.compress(bodyRaw) else { return }
        let skipSession = Self.noSessionEvents.contains(event)
        let sidBytes = remoteSessionId.data(using: .utf8) ?? Data()

        var buf = Data()
        buf.append(Self.headerB0)
        buf.append(Self.typeFullClient | Self.flagWithEvent)
        buf.append(Self.hdr2JsonGzip)
        buf.append(0x00)
        buf.append(u32be(UInt32(event)))
        if !skipSession {
            buf.append(u32be(UInt32(sidBytes.count)))
            buf.append(sidBytes)
        }
        buf.append(u32be(UInt32(body.count)))
        buf.append(body)

        os_log("TX event=%d size=%d payload=%{public}@",
               log: Self.log, type: .debug,
               event, buf.count, String(jsonPayload.prefix(120)))
        wsTask?.send(.data(buf)) { error in
            if let error = error {
                os_log("send failed: %{public}@", log: Self.log, type: .error,
                       error.localizedDescription)
            }
        }
    }

    private func sendAudioFrame(_ pcm: Data) {
        guard !pcm.isEmpty, let body = try? Gzip.compress(pcm) else { return }
        let sidBytes = remoteSessionId.data(using: .utf8) ?? Data()

        var buf = Data()
        buf.append(Self.headerB0)
        buf.append(Self.typeAudioClient | Self.flagWithEvent)
        buf.append(Self.hdr2RawGzip)
        buf.append(0x00)
        buf.append(u32be(UInt32(Self.evtSendAudio)))
        buf.append(u32be(UInt32(sidBytes.count)))
        buf.append(sidBytes)
        buf.append(u32be(UInt32(body.count)))
        buf.append(body)
        wsTask?.send(.data(buf)) { _ in }
    }

    // MARK: - Receive loop & parse

    private func runReceiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                switch msg {
                case .data(let bytes):
                    parseServerFrame(bytes)
                case .string(let text):
                    os_log("WS ← unexpected text: %{public}@",
                           log: Self.log, type: .error, String(text.prefix(200)))
                @unknown default:
                    break
                }
            } catch {
                if isRunning {
                    os_log("WS receive failed: %{public}@", log: Self.log, type: .error,
                           error.localizedDescription)
                    callback?.onError(code: "ws_error", message: error.localizedDescription)
                    failHandshakeIfPending(error: error)
                }
                isRunning = false
                isConnected = false
                isAudioRunning = false
                callback?.onDisconnected()
                return
            }
        }
    }

    private func failHandshakeIfPending(error: Error) {
        stateLock.lock()
        let conn = connectionStartedContinuation
        connectionStartedContinuation = nil
        let sess = sessionStartedContinuation
        sessionStartedContinuation = nil
        stateLock.unlock()
        conn?.resume(throwing: error)
        sess?.resume(throwing: error)
    }

    private func parseServerFrame(_ data: Data) {
        guard data.count >= 4 else { return }
        let b1 = data[1]
        let b2 = data[2]
        let msgType = b1 & 0xF0
        let flags   = b1 & 0x0F
        let compress = b2 & 0x0F
        let serType  = b2 & 0xF0
        let hasNegSeq = (flags & Self.flagNegSequence) != 0
        let hasEvent  = (flags & Self.flagWithEvent) != 0

        var pos = 4
        if hasNegSeq, pos + 4 <= data.count { pos += 4 }
        var event = -1
        if hasEvent, pos + 4 <= data.count {
            event = Int(readU32BE(data, at: pos))
            pos += 4
        }

        switch msgType {
        case Self.typeFullServer, Self.typeAudioServer:
            guard pos + 4 <= data.count else { return }
            let sidLen = Int(readU32BE(data, at: pos)); pos += 4
            if sidLen > 0 {
                guard pos + sidLen <= data.count else { return }
                pos += sidLen
            }
            guard pos + 4 <= data.count else { return }
            let payloadLen = Int(readU32BE(data, at: pos)); pos += 4
            guard payloadLen > 0, pos + payloadLen <= data.count else {
                if msgType == Self.typeFullServer {
                    handleServerEvent(event: event, payload: Data(),
                                      serType: serType, compress: compress)
                }
                return
            }
            var payload = data.subdata(in: pos..<(pos + payloadLen))
            if compress == Self.compressGzip {
                if let decompressed = try? Gzip.decompress(payload) {
                    payload = decompressed
                }
            }
            if msgType == Self.typeFullServer {
                handleServerEvent(event: event, payload: payload,
                                  serType: serType, compress: compress)
            } else {
                if !payload.isEmpty { writeTtsAudio(payload) }
            }

        case Self.typeError:
            var detail = "unknown"
            if data.count >= 12 {
                let code = readU32BE(data, at: 4)
                let pLen = Int(readU32BE(data, at: 8))
                if pLen > 0, 12 + pLen <= data.count {
                    var raw = data.subdata(in: 12..<(12 + pLen))
                    if compress == Self.compressGzip,
                       let decompressed = try? Gzip.decompress(raw) {
                        raw = decompressed
                    }
                    let body = String(data: raw, encoding: .utf8) ?? ""
                    detail = "code=\(code) \(body)"
                } else {
                    detail = "code=\(code)"
                }
            }
            os_log("Server error: %{public}@", log: Self.log, type: .error, detail)
            callback?.onError(code: "sts_server_error", message: detail)

        default:
            break
        }
    }

    private func handleServerEvent(event: Int, payload: Data, serType: UInt8, compress: UInt8) {
        let json: [String: Any]? = {
            guard serType == Self.serJson, !payload.isEmpty else { return nil }
            return try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        }()
        let jsonStr = (serType == Self.serJson) ? (String(data: payload, encoding: .utf8) ?? "") : ""
        os_log("Server event=%d json=%{public}@",
               log: Self.log, type: .debug, event, String(jsonStr.prefix(200)))

        switch event {
        case Self.evtConnectionStarted:
            stateLock.lock()
            let cont = connectionStartedContinuation
            connectionStartedContinuation = nil
            stateLock.unlock()
            cont?.resume()
        case Self.evtConnectionFailed:
            let msg = (json?["message"] as? String) ?? "connection failed"
            stateLock.lock()
            let cont = connectionStartedContinuation
            connectionStartedContinuation = nil
            stateLock.unlock()
            cont?.resume(throwing: NativeServiceError.invalidConfig(msg))
        case Self.evtConnectionFinished:
            callback?.onDisconnected()
        case Self.evtSessionStarted:
            stateLock.lock()
            let cont = sessionStartedContinuation
            sessionStartedContinuation = nil
            stateLock.unlock()
            cont?.resume()
        case Self.evtSessionFinOk, Self.evtSessionFinErr:
            os_log("SessionFinished event=%d", log: Self.log, type: .debug, event)
        case Self.evtClearAudio:
            os_log("ClearAudio (user speaking)", log: Self.log, type: .debug)
            audioIO.flushTts()
            chatResponseBuffer = ""
            callback?.onSpeechStart()
            callback?.onStateChanged(state: "listening")
        case Self.evtAsrResponse:
            let extra = json?["extra"] as? [String: Any]
            let text = (extra?["origin_text"] as? String) ?? ""
            let isFinal = (extra?["endpoint"] as? Bool) ?? false
            if !text.isEmpty {
                if isFinal {
                    callback?.onSttFinalResult(text: text)
                } else {
                    callback?.onSttPartialResult(text: text)
                }
            }
        case Self.evtUserQueryEnded:
            callback?.onStateChanged(state: "llm")
        case Self.evtChatResponse:
            let content = (json?["content"] as? String) ?? ""
            if !content.isEmpty {
                chatResponseBuffer.append(content)
                callback?.onChatPartialResult(cumulativeText: chatResponseBuffer)
                callback?.onStateChanged(state: "playing")
            }
        case Self.evtChatEnded:
            let direct = (json?["content"] as? String) ?? ""
            let full = direct.isEmpty ? chatResponseBuffer : direct
            chatResponseBuffer = ""
            if !full.isEmpty { callback?.onSentenceDone(text: full) }
        case Self.evtTtsEnded:
            callback?.onStateChanged(state: "listening")
        case Self.evtTtsType:
            break
        default:
            if let json = json { handleSessionEvent(json) }
        }
    }

    private func handleSessionEvent(_ json: [String: Any]) {
        let name: String = {
            if let s = json["event"] as? String, !s.isEmpty { return s }
            return (json["type"] as? String) ?? ""
        }()
        switch name {
        case "SentenceRecognized":
            let payload = json["payload"] as? [String: Any]
            let text = (json["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? ((payload?["text"] as? String) ?? "")
            if !text.isEmpty {
                callback?.onSttFinalResult(text: text)
                callback?.onStateChanged(state: "llm")
            }
        case "TTSSentenceStart":
            callback?.onStateChanged(state: "playing")
        case "TTSDone":
            callback?.onStateChanged(state: "listening")
        case "BotError":
            let code = (json["error_code"] as? String) ?? "bot_error"
            let msg = (json["error_msg"] as? String)
                ?? (json["message"] as? String) ?? "BotError"
            callback?.onError(code: code, message: msg)
        default:
            break
        }
    }

    private func writeTtsAudio(_ payload: Data) {
        if externalMode {
            guard let sink = externalSink else {
                os_log("writeTtsAudio: externalMode without sink — drop %dB",
                       log: Self.log, type: .info, payload.count)
                return
            }
            let pcm16k = PcmAudioIO.downsample24kTo16k(payload)
            sink.onTtsFrame(ExternalAudioFrame(
                codec: .pcmS16LE,
                sampleRate: Self.micSampleRate,
                channels: 1,
                bytes: pcm16k
            ))
            return
        }
        audioIO.enqueueTts(payload)
        callback?.onTtsAudioChunk(pcmData: payload)
    }

    // MARK: - Helpers

    private func buildSessionPayload() -> String {
        let payload: [String: Any] = [
            "asr": [
                "extra": [
                    "end_smooth_window_ms": 1500,
                ],
            ],
            "tts": [
                "speaker": speaker,
                "audio_config": [
                    "channel": 1,
                    "format": "pcm_s16le",
                    "sample_rate": Self.ttsSampleRate,
                ],
            ],
            "dialog": [
                "system_role": systemPrompt,
                "extra": [
                    "strict_audit": false,
                    "recv_timeout": 10,
                    "input_mod": "audio",
                    "model": "O",
                ],
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func u32be(_ v: UInt32) -> Data {
        var be = v.bigEndian
        return Data(bytes: &be, count: 4)
    }

    private func readU32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}

// MARK: - Async timeout helper

private func withTimeout<T>(seconds: TimeInterval,
                            operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw NativeServiceError.invalidConfig("timeout after \(Int(seconds))s")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
