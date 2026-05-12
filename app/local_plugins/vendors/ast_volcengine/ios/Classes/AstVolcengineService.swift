import Foundation
import ai_plugin_interface
import os.log

/// Volcengine end-to-end speech translation (AST) service.
///
/// Ports the Android `AstVolcengineService`. Protocol summary:
///   - WebSocket  `wss://openspeech.bytedance.com/api/v4/ast/v2/translate`
///   - Pure Protobuf payloads (no custom binary envelope).
///   - Handshake: `StartSession` (100) → `SessionStarted` (150) →
///     `TaskRequest` (200) audio frames flow.
///   - Each round emits a source-subtitle triple (650/651/652) followed by
///     a translation-subtitle triple (653/654/655); TTS PCM rides inside
///     the `data` field (proto field 3) of the translation frames.
///   - Languages must be **primary subtags** (`zh`, `en`, `ja`, …) — BCP-47
///     locales (`zh-CN`, `en-US`) trigger server error 45000001.
public final class AstVolcengineService: NativeAstService {

    private static let log = OSLog(subsystem: "com.aiagent.ast_volcengine", category: "Service")

    // MARK: Constants

    private static let micSampleRate = 16_000
    private static let ttsSampleRate = 24_000
    private static let wsUrl =
        "wss://openspeech.bytedance.com/api/v4/ast/v2/translate"
    private static let fixedResourceId = "volc.bigasr.auc"

    // Session lifecycle.
    private static let evtStartSession    = 100
    private static let evtFinishSession   = 102
    private static let evtSessionStarted  = 150
    private static let evtSessionFinished = 152
    private static let evtSessionFailed   = 153
    private static let evtUsageResponse   = 154
    // Audio uplink.
    private static let evtTaskRequest     = 200
    // TTS.
    private static let evtTtsSentenceStart = 350
    private static let evtTtsEnded         = 359
    // ASR partial.
    private static let evtAsrResponse      = 451
    // Source subtitle triple.
    private static let evtSrcSubtitleStart = 650
    private static let evtSrcSubtitle      = 651
    private static let evtSrcSubtitleEnd   = 652
    // Translation subtitle triple.
    private static let evtTransSubtitleStart = 653
    private static let evtTransSubtitle      = 654
    private static let evtTransSubtitleEnd   = 655

    // MARK: Configuration

    private var appKey: String = ""
    private var accessKey: String = ""
    private var resourceId: String = fixedResourceId
    private var srcLang: String = "zh"
    private var dstLang: String = "en"

    // MARK: State

    private weak var callback: AstCallback?
    private let stateLock = NSLock()
    private let urlSession: URLSession
    private var wsTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    private var isRunning = false
    private var isConnected = false
    private var isAudioRunning = false
    private var remoteSessionId = ""
    private var connectId = ""

    private var externalMode = false
    private weak var externalSink: ExternalAudioSink?

    private var sessionStartedContinuation: CheckedContinuation<Void, Error>?

    // Subtitle accumulators (server sends incremental fragments).
    private var srcSubtitleAccum = ""
    private var transSubtitleAccum = ""

    // Recognition round state mirroring the AST 5-piece lifecycle.
    private var currentRequestId: String?
    private var sourceRoleOpen = false
    private var translatedRoleOpen = false
    private var ttsFinalSentForRound = false

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
        appKey = (cfg["appKey"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? ((cfg["appId"] as? String) ?? "")
        accessKey = (cfg["accessKey"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? ((cfg["accessToken"] as? String) ?? "")
        let rid = (cfg["resourceId"] as? String) ?? ""
        resourceId = rid.isEmpty ? Self.fixedResourceId : rid
        srcLang = normalizeLang((cfg["srcLang"] as? String) ?? "")
        dstLang = normalizeLang((cfg["dstLang"] as? String) ?? "")
        os_log("initialize: srcLang=%{public}@ dstLang=%{public}@",
               log: Self.log, type: .debug, srcLang, dstLang)
    }

    private func normalizeLang(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "zh" }
        let firstSegment = trimmed
            .split(separator: "-", maxSplits: 1)[0]
            .split(separator: "_", maxSplits: 1)[0]
        return firstSegment.lowercased()
    }

    public func connect(callback: AstCallback) {
        self.callback = callback
        guard !appKey.isEmpty, !accessKey.isEmpty else {
            callback.onError(code: "config_error", message: "appKey or accessKey missing")
            return
        }
        Task { await runConnect(callback: callback) }
    }

    private func runConnect(callback: AstCallback) async {
        isRunning = true
        remoteSessionId = UUID().uuidString
        connectId = UUID().uuidString
        srcSubtitleAccum = ""
        transSubtitleAccum = ""

        guard let url = URL(string: Self.wsUrl) else {
            callback.onError(code: "config_error", message: "invalid ws url")
            return
        }
        var request = URLRequest(url: url)
        request.setValue(appKey, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessKey, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceId, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")

        let task = urlSession.webSocketTask(with: request)
        wsTask = task
        task.resume()

        receiveLoopTask = Task { [weak self] in await self?.runReceiveLoop(task: task) }

        do {
            try await withTimeout(seconds: 10) { [weak self] in
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self?.stateLock.lock()
                    self?.sessionStartedContinuation = cont
                    self?.stateLock.unlock()
                    if let frame = self?.buildTranslateRequest(event: Self.evtStartSession) {
                        self?.sendProto(frame)
                    }
                }
            }
            isConnected = true
            resetRoundState()
            os_log("SessionStarted — ready", log: Self.log, type: .debug)
            callback.onConnected()
        } catch {
            isRunning = false
            isConnected = false
            os_log("AST connect failed: %{public}@", log: Self.log, type: .error,
                   error.localizedDescription)
            callback.onError(code: "ast_error", message: error.localizedDescription)
        }
    }

    public func startAudio() {
        guard isConnected, !isAudioRunning else { return }
        if externalMode {
            os_log("startAudio: skip (externalMode active)", log: Self.log, type: .info)
            return
        }
        AudioOutputManager.shared.applyMode()
        isAudioRunning = true
        audioIO.startMic { [weak self] frame in
            guard let self = self else { return }
            self.sendProto(self.buildAudioFrame(pcm: frame))
        }
    }

    public func stopAudio() {
        isAudioRunning = false
        audioIO.stopMic()
        audioIO.flushTts()
    }

    public func interrupt() {
        audioIO.flushTts()
    }

    public func release() {
        stopAudio()
        stopExternalAudio()
        isRunning = false
        isConnected = false
        sendProto(buildTranslateRequest(event: Self.evtFinishSession))
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
                "ast_volcengine accepts only PCM_S16LE (got \(format.codec))")
        }
        if format.sampleRate != Self.micSampleRate || format.channels != 1 {
            throw NativeServiceError.unsupported(
                "ast_volcengine requires \(Self.micSampleRate)Hz mono")
        }
        if !isConnected {
            throw NativeServiceError.invalidConfig(
                "ast_volcengine not connected; call connect() first")
        }
        if isAudioRunning { stopAudio() }
        externalSink = sink
        externalMode = true
    }

    public func pushExternalAudioFrame(_ frame: Data) {
        if !externalMode || !isConnected || frame.isEmpty { return }
        sendProto(buildAudioFrame(pcm: frame))
    }

    public func stopExternalAudio() {
        if !externalMode { return }
        externalMode = false
        externalSink = nil
    }

    // MARK: - Protobuf framing

    /// Builds a TranslateRequest carrying full metadata, optionally embedding
    /// `pcmData` in `source_audio.binary_data` (proto field 14).
    private func buildTranslateRequest(event: Int, pcmData: Data? = nil) -> Data {
        var srcAudioFields = Data()
        srcAudioFields.append(encStr(4, "wav"))
        srcAudioFields.append(encInt(7, 16000))
        srcAudioFields.append(encInt(8, 16))
        srcAudioFields.append(encInt(9, 1))
        if let pcm = pcmData, !pcm.isEmpty {
            srcAudioFields.append(encBytes(14, pcm))
        }

        var meta = Data()
        meta.append(encStr(5, connectId))
        meta.append(encStr(6, remoteSessionId))

        var user = Data()
        user.append(encStr(1, "ast_ios"))
        user.append(encStr(2, "ast_ios"))

        var targetAudio = Data()
        targetAudio.append(encStr(4, "wav"))
        targetAudio.append(encInt(7, Self.ttsSampleRate))
        targetAudio.append(encInt(8, 16))
        targetAudio.append(encInt(9, 1))

        var request = Data()
        request.append(encStr(1, "s2s"))
        request.append(encStr(2, srcLang))
        request.append(encStr(3, dstLang))

        var out = Data()
        out.append(encMsg(1, meta))
        out.append(encEnum(2, event))
        out.append(encMsg(3, user))
        out.append(encMsg(4, srcAudioFields))
        out.append(encMsg(5, targetAudio))
        out.append(encMsg(6, request))
        return out
    }

    /// Builds a minimal audio-only TaskRequest (no redundant metadata).
    private func buildAudioFrame(pcm: Data) -> Data {
        var meta = Data()
        meta.append(encStr(6, remoteSessionId))
        var src = Data()
        src.append(encBytes(14, pcm))
        var out = Data()
        out.append(encMsg(1, meta))
        out.append(encEnum(2, Self.evtTaskRequest))
        out.append(encMsg(4, src))
        return out
    }

    private func sendProto(_ data: Data) {
        wsTask?.send(.data(data)) { _ in }
    }

    // ── Protobuf encoders ──────────────────────────────────────────

    private func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        while (v & ~UInt64(0x7F)) != 0 {
            out.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        out.append(UInt8(v))
        return out
    }

    private func tag(_ fieldNum: Int, _ wireType: Int) -> Data {
        varint(UInt64((fieldNum << 3) | wireType))
    }

    private func encEnum(_ fieldNum: Int, _ value: Int) -> Data {
        if value == 0 { return Data() }
        return tag(fieldNum, 0) + varint(UInt64(value))
    }

    private func encInt(_ fieldNum: Int, _ value: Int) -> Data {
        if value == 0 { return Data() }
        return tag(fieldNum, 0) + varint(UInt64(value))
    }

    private func encStr(_ fieldNum: Int, _ value: String) -> Data {
        if value.isEmpty { return Data() }
        let bytes = value.data(using: .utf8) ?? Data()
        return tag(fieldNum, 2) + varint(UInt64(bytes.count)) + bytes
    }

    private func encBytes(_ fieldNum: Int, _ value: Data) -> Data {
        if value.isEmpty { return Data() }
        return tag(fieldNum, 2) + varint(UInt64(value.count)) + value
    }

    private func encMsg(_ fieldNum: Int, _ msg: Data) -> Data {
        tag(fieldNum, 2) + varint(UInt64(msg.count)) + msg
    }

    // ── Protobuf decoder ───────────────────────────────────────────

    private struct PbField {
        let num: Int
        let wireType: Int
        let raw: Data
    }

    private func decodeProto(_ bytes: Data) -> [PbField] {
        var fields: [PbField] = []
        var pos = 0
        while pos < bytes.count {
            var tag: UInt64 = 0
            var shift: UInt64 = 0
            while pos < bytes.count {
                let b = UInt64(bytes[pos]); pos += 1
                tag |= (b & 0x7F) << shift
                shift += 7
                if (b & 0x80) == 0 { break }
            }
            let fieldNum = Int(tag >> 3)
            let wireType = Int(tag & 0x07)
            switch wireType {
            case 0:
                var v: UInt64 = 0
                var sh: UInt64 = 0
                while pos < bytes.count {
                    let b = UInt64(bytes[pos]); pos += 1
                    v |= (b & 0x7F) << sh
                    sh += 7
                    if (b & 0x80) == 0 { break }
                }
                var raw = Data(count: 8)
                for i in 0..<8 {
                    raw[i] = UInt8((v >> UInt64(i * 8)) & 0xFF)
                }
                fields.append(PbField(num: fieldNum, wireType: 0, raw: raw))
            case 2:
                var len: UInt64 = 0
                var sh: UInt64 = 0
                while pos < bytes.count {
                    let b = UInt64(bytes[pos]); pos += 1
                    len |= (b & 0x7F) << sh
                    sh += 7
                    if (b & 0x80) == 0 { break }
                }
                let end = min(pos + Int(len), bytes.count)
                fields.append(PbField(num: fieldNum, wireType: 2,
                                       raw: bytes.subdata(in: pos..<end)))
                pos = end
            case 1:
                pos += 8
            case 5:
                pos += 4
            default:
                return fields
            }
        }
        return fields
    }

    private func fieldLong(_ fields: [PbField], _ num: Int) -> Int64 {
        guard let f = fields.first(where: { $0.num == num && $0.wireType == 0 }) else { return 0 }
        var v: UInt64 = 0
        for i in 0..<min(8, f.raw.count) {
            v |= UInt64(f.raw[i]) << UInt64(i * 8)
        }
        return Int64(bitPattern: v)
    }

    private func fieldBytes(_ fields: [PbField], _ num: Int) -> Data {
        fields.first(where: { $0.num == num && $0.wireType == 2 })?.raw ?? Data()
    }

    private func fieldStr(_ fields: [PbField], _ num: Int) -> String {
        let b = fieldBytes(fields, num)
        if b.isEmpty { return "" }
        return String(data: b, encoding: .utf8) ?? ""
    }

    // MARK: - Receive loop

    private func runReceiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let msg = try await task.receive()
                switch msg {
                case .data(let bytes):
                    handleResponse(bytes)
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
                    stateLock.lock()
                    let cont = sessionStartedContinuation
                    sessionStartedContinuation = nil
                    stateLock.unlock()
                    cont?.resume(throwing: error)
                }
                isRunning = false
                isConnected = false
                isAudioRunning = false
                return
            }
        }
    }

    private func handleResponse(_ data: Data) {
        if wsTask == nil { return }
        let fields = decodeProto(data)
        let event = Int(fieldLong(fields, 2))
        let audio = fieldBytes(fields, 3)
        let text = fieldStr(fields, 4)
        let metaBytes = fieldBytes(fields, 1)
        let metaFields = metaBytes.isEmpty ? [] : decodeProto(metaBytes)
        let statusCode = Int(fieldLong(metaFields, 3))
        let message = fieldStr(metaFields, 4)

        os_log("RX event=%d status=%d audioLen=%d",
               log: Self.log, type: .debug, event, statusCode, audio.count)

        switch event {
        case Self.evtSessionStarted:
            stateLock.lock()
            let cont = sessionStartedContinuation
            sessionStartedContinuation = nil
            stateLock.unlock()
            cont?.resume()

        case Self.evtSessionFinished:
            isConnected = false
            forceEndRound()
            callback?.onDisconnected()

        case Self.evtSessionFailed:
            let err = "SessionFailed status=\(statusCode) msg=\(message)"
            isConnected = false
            stateLock.lock()
            let cont = sessionStartedContinuation
            sessionStartedContinuation = nil
            stateLock.unlock()
            cont?.resume(throwing: NativeServiceError.runtime(err))
            wsTask?.cancel(with: .normalClosure, reason: nil)
            wsTask = nil
            callback?.onError(code: "ast_session_failed", message: err)

        case Self.evtAsrResponse:
            if !text.isEmpty, let cb = callback {
                beginRound(cb)
                openRole(cb, role: .source)
                emitRoleText(cb, role: .source, isFinal: false, text: text)
            }
            if !audio.isEmpty { writeAudio(audio) }

        case Self.evtSrcSubtitleStart:
            ttsFinalSentForRound = false
            srcSubtitleAccum = ""
            if let cb = callback {
                beginRound(cb, force: true)
                openRole(cb, role: .source)
            }
            if !audio.isEmpty { writeAudio(audio) }

        case Self.evtSrcSubtitle:
            if !text.isEmpty {
                srcSubtitleAccum.append(text)
                if let cb = callback {
                    beginRound(cb)
                    openRole(cb, role: .source)
                    emitRoleText(cb, role: .source, isFinal: false, text: srcSubtitleAccum)
                }
            }
            if !audio.isEmpty { writeAudio(audio) }

        case Self.evtSrcSubtitleEnd:
            if let cb = callback {
                if !srcSubtitleAccum.isEmpty {
                    emitRoleText(cb, role: .source, isFinal: true, text: srcSubtitleAccum)
                }
                closeRole(cb, role: .source)
                // Keep `currentRequestId` open for the matching translation triple.
            }

        case Self.evtTransSubtitleStart:
            transSubtitleAccum = ""
            if let cb = callback {
                beginRound(cb)
                openRole(cb, role: .translated)
            }
            if !audio.isEmpty { writeAudio(audio) }

        case Self.evtTransSubtitle:
            if !text.isEmpty {
                transSubtitleAccum.append(text)
                if let cb = callback {
                    beginRound(cb)
                    openRole(cb, role: .translated)
                    emitRoleText(cb, role: .translated, isFinal: false, text: transSubtitleAccum)
                }
            }
            if !audio.isEmpty { writeAudio(audio) }

        case Self.evtTransSubtitleEnd:
            if let cb = callback {
                if !transSubtitleAccum.isEmpty {
                    emitRoleText(cb, role: .translated, isFinal: true, text: transSubtitleAccum)
                }
                closeRole(cb, role: .translated)
                maybeEndRound(cb)
            }
            emitTtsFinalOnce(reason: "trans_end")

        case Self.evtTtsSentenceStart:
            if !audio.isEmpty { writeAudio(audio) }

        case Self.evtTtsEnded:
            emitTtsFinalOnce(reason: "tts_ended")

        case Self.evtUsageResponse:
            break

        default:
            if !audio.isEmpty { writeAudio(audio) }
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
        guard let cb = callback else { resetRoundState(); return }
        if currentRequestId == nil { return }
        if sourceRoleOpen { closeRole(cb, role: .source) }
        if translatedRoleOpen { closeRole(cb, role: .translated) }
        endRound(cb)
    }

    private func emitRoleText(_ cb: AstCallback, role: AstRole, isFinal: Bool, text: String) {
        guard let rid = currentRequestId else { return }
        if isFinal {
            cb.onRecognized(role: role, requestId: rid, text: text)
        } else {
            cb.onRecognizing(role: role, requestId: rid, text: text)
        }
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
        return "ast_volcengine_\(ms)_\(padded)"
    }

    private func emitTtsFinalOnce(reason: String) {
        if ttsFinalSentForRound { return }
        if !externalMode { return }
        guard let sink = externalSink else { return }
        ttsFinalSentForRound = true
        os_log("emitTtsFinal: %{public}@", log: Self.log, type: .debug, reason)
        sink.onTtsFrame(ExternalAudioFrame(
            codec: .pcmS16LE,
            sampleRate: Self.micSampleRate,
            channels: 1,
            bytes: Data(),
            isFinal: true
        ))
    }

    private func writeAudio(_ data: Data) {
        if data.isEmpty { return }
        if externalMode {
            guard let sink = externalSink else {
                os_log("writeAudio: externalMode without sink — drop %dB",
                       log: Self.log, type: .info, data.count)
                return
            }
            let pcm16k = PcmAudioIO.downsample24kTo16k(data)
            sink.onTtsFrame(ExternalAudioFrame(
                codec: .pcmS16LE,
                sampleRate: Self.micSampleRate,
                channels: 1,
                bytes: pcm16k
            ))
            return
        }
        audioIO.enqueueTts(data)
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
