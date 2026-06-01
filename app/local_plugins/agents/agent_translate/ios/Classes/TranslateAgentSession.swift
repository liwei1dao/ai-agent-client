import Foundation
import ai_plugin_interface
import os.log

/// Translate agent session — iOS port of the Kotlin `TranslateAgentSession`.
///
/// Pipeline: STT → Translation → TTS. Persistence (message DB) stays on the
/// Dart side, so this class is a pure orchestrator over native services.
///
/// Scheduling model is **strict FIFO** (no preemption): every input lands in
/// `callQueue` and a single worker runs translate + TTS in order. Switching
/// input mode, explicit `interrupt`, `stopExternalAudio`, and `release`
/// flush the queue — VAD speech-start does not.
///
/// NOTE: as of 2026-05, iOS does not yet ship a `NativeSttService` /
/// `NativeTtsService` vendor implementation registered with
/// `NativeServiceRegistry` (`stt_azure` / `tts_azure` iOS are still old-style
/// MethodChannel plugins exposed directly to Dart). Until those are ported
/// this session will fail at `initialize()` with `invalidConfig`. The class
/// is here so registration parity with Android holds.
public final class TranslateAgentSession: NativeAgent {

    public let agentType = "translate"

    private static let log = OSLog(subsystem: "com.aiagent.agent_translate", category: "Session")

    public static let directionSrcToDst = "src_to_dst"
    public static let directionDstToSrc = "dst_to_src"

    private static let maxConcurrentSynthesis = 2

    private static let sentenceTerminators: Set<Character> = [
        "。", "！", "？", ".", "!", "?", "；", ";", "\n",
    ]

    fileprivate enum State: String { case idle, listening, stt, translating, tts, playing, error }

    // ── Configuration / state ─────────────────────────────────────────────

    private var config: NativeAgentConfig!
    private weak var eventSink: AgentEventSink?

    private var sttService: NativeSttService?
    private var translationService: NativeTranslationService?
    private var ttsService: NativeTtsService?

    private let stateLock = NSLock()
    private var state: State = .idle
    private var activeRequestId: String?

    private var inputMode: String = "text"
    private var srcLang: String?
    private var dstLang: String = "en"
    private var bidirectional: Bool = false
    private var direction: String = TranslateAgentSession.directionSrcToDst
    private var externalAudioActive: Bool = false

    /// Last STT `detectedLang` — consumed once by push-to-talk `sendText`.
    private var lastSttDetectedLang: String?

    // ── FIFO queue ────────────────────────────────────────────────────────

    fileprivate struct QueuedRequest {
        let requestId: String
        let text: String
        let direction: String
    }

    private var queueContinuation: AsyncStream<QueuedRequest>.Continuation?
    private var queueWorkerTask: Task<Void, Never>?

    public init() {}

    // ── NativeAgent lifecycle ─────────────────────────────────────────────

    public func initialize(config: NativeAgentConfig, eventSink: AgentEventSink) {
        self.config = config
        self.eventSink = eventSink
        self.inputMode = config.inputMode

        self.srcLang = config.extraParams["srcLang"]
        self.dstLang = config.extraParams["dstLang"] ?? "en"
        self.bidirectional = (config.extraParams["bidirectional"] == "true")
        self.direction = config.extraParams["direction"] ?? Self.directionSrcToDst

        do {
            let stt = try NativeServiceRegistry.shared.createStt(config.sttVendor ?? "azure")
            let trans = try NativeServiceRegistry.shared.createTranslation(config.translationVendor ?? "deepl")
            let tts = try NativeServiceRegistry.shared.createTts(config.ttsVendor ?? "azure")
            stt.initialize(configJson: config.sttConfigJson ?? "{}")
            trans.initialize(configJson: config.translationConfigJson ?? "{}")
            tts.initialize(configJson: config.ttsConfigJson ?? "{}")
            self.sttService = stt
            self.translationService = trans
            self.ttsService = tts
            os_log("initialized agentId=%{public}@ stt=%{public}@ trans=%{public}@ tts=%{public}@ srcLang=%{public}@ dstLang=%{public}@",
                   log: Self.log, type: .debug,
                   config.agentId,
                   config.sttVendor ?? "azure",
                   config.translationVendor ?? "deepl",
                   config.ttsVendor ?? "azure",
                   srcLang ?? "auto", dstLang)
        } catch {
            os_log("translate-agent service init failed: %{public}@",
                   log: Self.log, type: .error, error.localizedDescription)
            eventSink.onError(
                sessionId: config.agentId,
                errorCode: "translate_init_failed",
                message: error.localizedDescription,
                requestId: nil
            )
        }
    }

    public func connectService() {
        // Three-stage agent — no remote handshake; report ready immediately.
        eventSink?.onAgentReady(
            sessionId: config.agentId,
            ready: sttService != nil && translationService != nil && ttsService != nil,
            errorCode: nil,
            errorMessage: nil
        )
    }

    public func sendText(requestId: String, text: String) {
        // push-to-talk path: STT just fired finalResult with detectedLang and
        // stashed it in `lastSttDetectedLang`; consume once for direction
        // resolution. Pure text input has nil detectedLang → fallback to UI.
        let det = lastSttDetectedLang
        lastSttDetectedLang = nil
        enqueueTranslation(QueuedRequest(
            requestId: requestId,
            text: text,
            direction: resolveDirection(det)
        ))
    }

    public func setOption(key: String, value: String) {
        switch key {
        case "bidirectional":
            bidirectional = (value == "true")
        case "direction":
            direction = (value == Self.directionDstToSrc) ? Self.directionDstToSrc : Self.directionSrcToDst
        default:
            break
        }
    }

    public func startListening() {
        if externalAudioActive {
            os_log("startListening skipped: external audio active", log: Self.log, type: .debug)
            return
        }
        transitionTo(.listening)
        sttService?.startListening(callback: SttCallbackAdapter(owner: self))
    }

    public func stopListening() {
        sttService?.stopListening()
    }

    public func setInputMode(_ mode: String) {
        os_log("setInputMode: %{public}@", log: Self.log, type: .debug, mode)
        inputMode = mode
        // Explicit mode switch — flush the queue.
        shutdownCallQueue(reason: "mode_switch_\(mode)")
        switch mode {
        case "call":
            if externalAudioActive { return }
            ttsService?.stop()
            startContinuousListening()
        case "short_voice":
            break
        default:
            sttService?.stopListening()
        }
    }

    public func interrupt() {
        ttsService?.stop()
        shutdownCallQueue(reason: "manual_interrupt")
        transitionTo(.idle)
    }

    public func release() {
        shutdownCallQueue(reason: "release")
        sttService?.release()
        translationService?.release()
        ttsService?.release()
        sttService = nil
        translationService = nil
        ttsService = nil
    }

    // ── External audio (call translation) ─────────────────────────────────

    public func externalAudioCapability() -> ExternalAudioCapability {
        guard let stt = sttService, let tts = ttsService else { return .unsupported }
        let s = stt.externalAudioCapability()
        let t = tts.externalAudioCapability()
        return ExternalAudioCapability(
            acceptsOpus: s.acceptsOpus && t.acceptsOpus,
            acceptsPcm: s.acceptsPcm && t.acceptsPcm,
            preferredSampleRate: s.preferredSampleRate,
            preferredChannels: s.preferredChannels,
            preferredFrameMs: s.preferredFrameMs
        )
    }

    public func startExternalAudio(format: ExternalAudioFormat, sink: ExternalAudioSink) throws {
        guard let stt = sttService, let tts = ttsService else {
            throw NativeServiceError.invalidConfig("translate services not initialised")
        }
        inputMode = "call"
        externalAudioActive = true
        try tts.startExternalAudio(format: format, sink: sink)
        try stt.startExternalAudio(format: format, callback: SttCallbackAdapter(owner: self))
    }

    public func pushExternalAudioFrame(_ frame: Data) {
        sttService?.pushExternalAudioFrame(frame)
    }

    public func stopExternalAudio() {
        externalAudioActive = false
        sttService?.stopExternalAudio()
        ttsService?.stop()
        ttsService?.stopExternalAudio()
        shutdownCallQueue(reason: "external_audio_stop")
        transitionTo(.idle)
    }

    // ── Direction resolution ──────────────────────────────────────────────

    fileprivate func resolveDirection(_ detectedLang: String?) -> String {
        guard bidirectional, let det = detectedLang, !det.isEmpty else { return direction }
        let detBase = langBase(det)
        let srcBase = langBase(srcLang ?? "")
        let dstBase = langBase(dstLang)
        if detBase == dstBase && detBase != srcBase { return Self.directionDstToSrc }
        if detBase == srcBase { return Self.directionSrcToDst }
        return direction
    }

    private func langBase(_ s: String) -> String {
        var head = s
        if let r = head.firstIndex(of: "-") { head = String(head[..<r]) }
        if let r = head.firstIndex(of: "_") { head = String(head[..<r]) }
        return head.lowercased()
    }

    // ── Translation FIFO pipeline ─────────────────────────────────────────

    fileprivate func enqueueTranslation(_ req: QueuedRequest) {
        if queueContinuation == nil {
            var capturedCont: AsyncStream<QueuedRequest>.Continuation?
            let stream = AsyncStream<QueuedRequest> { cont in capturedCont = cont }
            queueContinuation = capturedCont
            queueWorkerTask = Task { [weak self] in
                guard let self = self else { return }
                for await item in stream {
                    if Task.isCancelled { break }
                    self.setActiveRequestId(item.requestId)
                    await self.runTranslationPipeline(
                        requestId: item.requestId,
                        text: item.text,
                        dir: item.direction
                    )
                    if Task.isCancelled { break }
                    if self.inputMode == "call" {
                        self.transitionTo(.listening)
                    } else {
                        self.setActiveRequestId(nil)
                        self.transitionTo(.idle)
                    }
                }
            }
        }
        queueContinuation?.yield(req)
    }

    fileprivate func shutdownCallQueue(reason: String) {
        queueContinuation?.finish()
        queueContinuation = nil
        queueWorkerTask?.cancel()
        queueWorkerTask = nil
        setActiveRequestId(nil)
    }

    private func runTranslationPipeline(requestId: String, text: String, dir: String) async {
        guard let translation = translationService, let sink = eventSink else { return }
        let sourceForCall: String?
        let targetForCall: String
        if dir == Self.directionDstToSrc {
            sourceForCall = dstLang
            targetForCall = srcLang ?? dstLang
        } else {
            sourceForCall = srcLang
            targetForCall = dstLang
        }

        transitionTo(.translating)
        sink.onLlmEvent(LlmEventData(
            sessionId: config.agentId,
            requestId: requestId,
            kind: "firstToken",
            textDelta: ""
        ))

        let translatedText: String
        do {
            let result = try await translation.translate(
                text: text,
                targetLang: targetForCall,
                sourceLang: sourceForCall
            )
            translatedText = result.translatedText
        } catch is CancellationError {
            return
        } catch {
            os_log("Translation failed: %{public}@", log: Self.log, type: .error,
                   error.localizedDescription)
            sink.onLlmEvent(LlmEventData(
                sessionId: config.agentId,
                requestId: requestId,
                kind: "error",
                errorCode: "translation_error",
                errorMessage: error.localizedDescription
            ))
            transitionTo(.error)
            return
        }

        if Task.isCancelled { return }

        sink.onLlmEvent(LlmEventData(
            sessionId: config.agentId,
            requestId: requestId,
            kind: "done",
            fullText: translatedText
        ))

        if Task.isCancelled { return }

        if !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transitionTo(.tts)
            await runTtsPipeline(requestId: requestId, text: translatedText)
        }
    }

    // ── TTS sub-pipeline ──────────────────────────────────────────────────

    private static func splitSentences(_ text: String) -> [String] {
        var out: [String] = []
        var buf = ""
        for c in text {
            buf.append(c)
            if Self.sentenceTerminators.contains(c) {
                let trimmed = buf.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
                buf = ""
            }
        }
        let tail = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    private func runTtsPipeline(requestId: String, text: String) async {
        guard let tts = ttsService, let sink = eventSink else { return }
        // Call mode: don't split (RCSP downstream wants one AudioData per segment).
        let sentences = inputMode == "call"
            ? [text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
            : Self.splitSentences(text)
        if sentences.isEmpty { return }

        let segments = sentences.enumerated().map { (idx, sentence) in
            TtsSegment(seq: idx, text: sentence, audio: AudioPromise())
        }

        // Open the "playback in progress" gates exactly once.
        var firstEmitted = false
        let emitFirstIfNeeded = {
            if firstEmitted { return }
            firstEmitted = true
            sink.onTtsEvent(TtsEventData(
                sessionId: self.config.agentId,
                requestId: requestId,
                kind: "synthesisStart"
            ))
            sink.onTtsEvent(TtsEventData(
                sessionId: self.config.agentId,
                requestId: requestId,
                kind: "playbackStart"
            ))
        }

        // Synth pool (≤ MAX_CONCURRENT_SYNTHESIS in flight).
        var synthIter = AtomicCounter()
        let pool = Task<Void, Never> { [weak self] in
            guard let self = self else { return }
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<Self.maxConcurrentSynthesis {
                    group.addTask {
                        while !Task.isCancelled {
                            let i = synthIter.next()
                            if i >= segments.count { return }
                            let seg = segments[i]
                            do {
                                let audio = try await tts.synthesize(
                                    requestId: requestId,
                                    text: seg.text
                                )
                                seg.audio.resolve(.success(audio))
                            } catch {
                                seg.audio.resolve(.failure(error))
                            }
                        }
                    }
                }
                await group.waitForAll()
            }
        }

        // Sequential playback consumer.
        let consumerCallback = TtsCallbackAdapter(owner: self, requestId: requestId)
        for seg in segments {
            if Task.isCancelled { break }
            emitFirstIfNeeded()
            do {
                let audio = try await seg.audio.value()
                sink.onTtsEvent(TtsEventData(
                    sessionId: config.agentId,
                    requestId: requestId,
                    kind: "synthesisReady",
                    durationMs: audio.durationMs ?? 0
                ))
                try await tts.play(requestId: requestId, audio: audio, callback: consumerCallback)
            } catch is CancellationError {
                break
            } catch {
                os_log("play seq=%d failed: %{public}@", log: Self.log, type: .error,
                       seg.seq, error.localizedDescription)
                sink.onTtsEvent(TtsEventData(
                    sessionId: config.agentId,
                    requestId: requestId,
                    kind: "error",
                    errorCode: "tts_segment_failed",
                    errorMessage: error.localizedDescription
                ))
            }
        }

        // Wait for synth pool to drain so we don't leak background work.
        _ = await pool.value

        if firstEmitted && !Task.isCancelled {
            sink.onTtsEvent(TtsEventData(
                sessionId: config.agentId,
                requestId: requestId,
                kind: "playbackDone"
            ))
        }
    }

    // ── Internal helpers ──────────────────────────────────────────────────

    fileprivate func transitionTo(_ newState: State) {
        stateLock.lock()
        state = newState
        let reqId = activeRequestId
        stateLock.unlock()
        eventSink?.onStateChanged(
            sessionId: config.agentId,
            state: newState.rawValue,
            requestId: reqId
        )
    }

    fileprivate func setActiveRequestId(_ id: String?) {
        stateLock.lock(); activeRequestId = id; stateLock.unlock()
    }

    private func startContinuousListening() {
        if externalAudioActive {
            transitionTo(.listening)
            return
        }
        transitionTo(.listening)
        sttService?.startListening(callback: SttCallbackAdapter(owner: self))
    }

    fileprivate func sink() -> AgentEventSink? { eventSink }
    fileprivate func agentId() -> String { config.agentId }
    fileprivate func currentInputMode() -> String { inputMode }
    fileprivate func setLastSttDetectedLang(_ lang: String?) { lastSttDetectedLang = lang }
}

// MARK: - Per-segment audio promise

private final class AudioPromise {
    private let lock = NSLock()
    private var result: Result<TtsAudio, Error>?
    private var waiters: [(Result<TtsAudio, Error>) -> Void] = []

    func resolve(_ r: Result<TtsAudio, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = r
        let ws = waiters
        waiters.removeAll()
        lock.unlock()
        for w in ws { w(r) }
    }

    func value() async throws -> TtsAudio {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<TtsAudio, Error>) in
            lock.lock()
            if let r = result {
                lock.unlock()
                cont.resume(with: r)
            } else {
                waiters.append { r in cont.resume(with: r) }
                lock.unlock()
            }
        }
    }
}

private struct TtsSegment {
    let seq: Int
    let text: String
    let audio: AudioPromise
}

/// Thread-safe ascending counter used as a synth-pool work index.
private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        let v = value
        value += 1
        return v
    }
}

// MARK: - STT callback adapter

private final class SttCallbackAdapter: SttCallback {
    private weak var owner: TranslateAgentSession?

    init(owner: TranslateAgentSession) { self.owner = owner }

    func onListeningStarted() {
        owner?.sink()?.onSttEvent(SttEventData(
            sessionId: owner?.agentId() ?? "", requestId: "", kind: "listeningStarted"
        ))
    }

    func onPartialResult(text: String, detectedLang: String?) {
        owner?.sink()?.onSttEvent(SttEventData(
            sessionId: owner?.agentId() ?? "",
            requestId: "",
            kind: "partialResult",
            text: text,
            detectedLang: detectedLang
        ))
    }

    func onFinalResult(text: String, detectedLang: String?) {
        guard let owner = owner, let sink = owner.sink() else { return }
        owner.setLastSttDetectedLang(detectedLang)
        let reqId = UUID().uuidString
        sink.onSttEvent(SttEventData(
            sessionId: owner.agentId(),
            requestId: reqId,
            kind: "finalResult",
            text: text,
            detectedLang: detectedLang
        ))
        // Call mode: enqueue translation automatically; detectedLang consumed here.
        if owner.currentInputMode() == "call" {
            owner.setLastSttDetectedLang(nil)
            owner.enqueueTranslation(.init(
                requestId: reqId,
                text: text,
                direction: owner.resolveDirection(detectedLang)
            ))
        }
    }

    func onVadSpeechStart() {
        owner?.sink()?.onSttEvent(SttEventData(
            sessionId: owner?.agentId() ?? "", requestId: "", kind: "vadSpeechStart"
        ))
        // VAD never preempts the translate FIFO — by design.
    }

    func onVadSpeechEnd() {
        owner?.sink()?.onSttEvent(SttEventData(
            sessionId: owner?.agentId() ?? "", requestId: "", kind: "vadSpeechEnd"
        ))
    }

    func onListeningStopped() {
        owner?.sink()?.onSttEvent(SttEventData(
            sessionId: owner?.agentId() ?? "", requestId: "", kind: "listeningStopped"
        ))
    }

    func onError(code: String, message: String) {
        owner?.sink()?.onSttEvent(SttEventData(
            sessionId: owner?.agentId() ?? "",
            requestId: "",
            kind: "error",
            errorCode: code,
            errorMessage: message
        ))
    }
}

// MARK: - TTS callback adapter

private final class TtsCallbackAdapter: TtsCallback {
    private weak var owner: TranslateAgentSession?
    private let requestId: String

    init(owner: TranslateAgentSession, requestId: String) {
        self.owner = owner
        self.requestId = requestId
    }

    func onSynthesisStart() {}
    func onSynthesisReady(durationMs: Int) {
        owner?.sink()?.onTtsEvent(TtsEventData(
            sessionId: owner?.agentId() ?? "",
            requestId: requestId,
            kind: "synthesisReady",
            durationMs: durationMs
        ))
    }
    func onPlaybackStart() {}
    func onPlaybackProgress(progressMs: Int) {
        owner?.sink()?.onTtsEvent(TtsEventData(
            sessionId: owner?.agentId() ?? "",
            requestId: requestId,
            kind: "playbackProgress",
            progressMs: progressMs
        ))
    }
    func onPlaybackDone() {}  // round-level "done" emitted by the pipeline.
    func onPlaybackInterrupted() {
        owner?.sink()?.onTtsEvent(TtsEventData(
            sessionId: owner?.agentId() ?? "",
            requestId: requestId,
            kind: "playbackInterrupted"
        ))
    }
    func onError(code: String, message: String) {
        owner?.sink()?.onTtsEvent(TtsEventData(
            sessionId: owner?.agentId() ?? "",
            requestId: requestId,
            kind: "error",
            errorCode: code,
            errorMessage: message
        ))
    }
}
