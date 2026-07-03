import Foundation
import JL_BLEKit

/// MODE_CALL_TRANSLATION（iOS 固件走 mode=6 立体声路径）—— 通话翻译。
///
/// 为什么 iOS 端硬绑到 mode=6：
///   - 在当前版本的杰理耳机固件上，mode=3（单声道通话翻译）不会把 eSCO 上/下行
///     帧通过 cmd=52 推到 SDK；实测 `onReceiveAudioData` 永远 0 帧。
///   - mode=6（MODE_CALL_TRANSLATION_WITH_STEREO）走的是同一颗芯片内部
///     SOURCE_E_SCO_MIX 通路：耳机直接把 uplink(L) + downlink(R) 混成立体声 OPUS
///     推上来，再由 APP 端软件分声道。Android 在支持此能力时也会自动升级到 6。
///
/// 约定：
///   - `modeId` 对外仍然是 MODE_CALL_TRANSLATION，保持 Dart 层逻辑不变。
///   - 下发给固件的 mode 固定是 `callTranslateStereo(0x06)`, channel=2。
///   - 默认 OPUS、`byDevice` 录音策略。
///
/// 上行：耳机推 **立体声** OPUS → 2 声道解码 → `PcmKit.splitStereo16` 拆 L/R
///      → L 进 `in.uplink`、R 进 `in.downlink`
/// 下行：Dart 喂 PCM → 单声道 OPUS 编码 → 按 source 写回耳机（`typeESCOUp`/`typeESCODown`）
public final class CallTranslationModeHandler: BaseTranslationModeHandler {

    private var decoder: OpusStreamDecoder?
    private var encoderUplink: OpusStreamEncoder?
    private var encoderDownlink: OpusStreamEncoder?
    private var sampleRate = 16000
    private var audioType: JL_SpeakDataType = .OPUS
    private var rxFrameCount: Int64 = 0
    private var rxUplinkBytes: Int64 = 0
    private var rxDownlinkBytes: Int64 = 0
    private var heartbeatTimer: DispatchSourceTimer?
    private let heartbeatQueue = DispatchQueue(label: "calltrans.heartbeat", qos: .utility)

    // TTS 下行：per-leg PCM / OPUS 累积缓冲。isFinal=true 时一次性编码 + 下发。
    // 这条“整段开闸”语义对应 Android `JieliAITranslationBridge.feedTtsPcm`；
    // 固件/SDK 期望的是“一次 trWriteAudioV2 = 一段完整 utterance OPUS（带 head）”。
    private let ttsBufferLock = NSLock()
    private var pcmBufferUplink = Data()
    private var pcmBufferDownlink = Data()
    private var opusBufferUplink = Data()
    private var opusBufferDownlink = Data()
    // 兜底：上层一直不发 isFinal 时避免内存爆，和 Android `PCM_BUFFER_HARD_LIMIT_BYTES` 对齐。
    private let pcmBufferHardLimitBytes = 2 * 1024 * 1024
    // 诊断：TTS 入口调用计数，用于节流打印入口日志。
    private var ttsInCount: Int64 = 0

    public init(server: JieliHomeServer) {
        super.init(
            server: server,
            modeId: TranslationModeIds.MODE_CALL_TRANSLATION,
            inputs: [TranslationStreams.IN_UPLINK, TranslationStreams.IN_DOWNLINK],
            outputs: [TranslationStreams.OUT_UPLINK, TranslationStreams.OUT_DOWNLINK]
        )
    }

    public override func start(args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        print("[CallTrans] start ENTRY args=\(args)")
        guard let server = server else {
            print("[CallTrans] start FAIL server uninitialized")
            completion(false, "server uninitialized"); return
        }
        if working {
            print("[CallTrans] start already working, returning ok")
            completion(true, nil); return
        }

        let address = args["address"] as? String
        let session: TranslationSession? = {
            if let addr = address { return server.translationSession(for: addr) }
            return server.currentTranslationSession()
        }()
        guard let s = session else {
            print("[CallTrans] start FAIL no connected device")
            emitError(-200, "no connected device; pass args.address or connect first")
            completion(false, "no connected device"); return
        }
        print("[CallTrans] start session resolved uuid=\(s.uuid) isBusy=\(s.isBusy)")

        let sr = (args["sampleRate"] as? NSNumber)?.intValue ?? 16000
        let aType = Self.parseAudioType(args["audioType"]) ?? .OPUS
        let recordType = Self.parseRecordType(args["strategy"], default: .byDevice)
        print("[CallTrans] start params sr=\(sr) audioType=\(aType.rawValue) recordType=\(recordType.rawValue)")

        sampleRate = sr
        audioType = aType
        self.session = s

        // 编/解码器（仅 OPUS 模式需要）
        if aType == .OPUS {
            // 立体声 OPUS。channels=2、dataSize 参考 [StereoCallTranslationModeHandler] 给 80。
            decoder = OpusStreamDecoder(channels: 2, dataSize: 80, sampleRate: sr) { [weak self] stereoPcm in
                guard let self = self else { return }
                // stereo PCM (interleaved L,R) → 拆成两路单声道
                let (l, r) = PcmKit.splitStereo16(stereoPcm)
                let fmt = AudioFormat(sampleRate: sr, channels: 1, bitsPerSample: 16)
                self.rxUplinkBytes &+= Int64(l.count)
                self.rxDownlinkBytes &+= Int64(r.count)
                self.pushFrame(streamId: TranslationStreams.IN_UPLINK, pcm: l, format: fmt)
                self.pushFrame(streamId: TranslationStreams.IN_DOWNLINK, pcm: r, format: fmt)
            } onError: { [weak self] code, msg in
                self?.emitError(code, "opus stereo decode: \(msg ?? "")")
            }
            encoderUplink = OpusStreamEncoder(channels: 1, sampleRate: sr, hasDataHeader: true) { [weak self] opus in
                self?.appendOpus(opus, to: TranslationStreams.OUT_UPLINK)
            } onError: { [weak self] code, msg in
                self?.emitError(code, "opus encode uplink: \(msg ?? "")")
            }
            encoderDownlink = OpusStreamEncoder(channels: 1, sampleRate: sr, hasDataHeader: true) { [weak self] opus in
                self?.appendOpus(opus, to: TranslationStreams.OUT_DOWNLINK)
            } onError: { [weak self] code, msg in
                self?.emitError(code, "opus encode downlink: \(msg ?? "")")
            }
        }

        s.acquire(owner: self) { [weak self] tm, errMsg in
            guard let self = self else { return }
            guard let tm = tm else {
                print("[CallTrans] acquire FAIL err=\(errMsg ?? "nil")")
                self.emitError(-201, errMsg)
                completion(false, errMsg); return
            }
            print("[CallTrans] acquire OK, applying recordtype=\(recordType.rawValue) " +
                  "isSupportTranslate=\(tm.trIsSupportTranslate()) isPlayWithA2dp=\(tm.trIsPlayWithA2dp()) " +
                  "isWorking=\(tm.trIsWorking()) isCalling=\(tm.isCalling)")
            tm.recordtype = recordType
            // iOS 端硬绑 mode=6：在当前固件上 mode=3 不推帧，只有 mode=6 会把
            // SOURCE_E_SCO_MIX 立体声帧推上来。维持 isCalling / trSendIsRelay 这两
            // 个“开闸”也一并保留。
            tm.isCalling = true
            let mode = Self.buildMode(modeType: .callTranslateStereo, audioType: aType, channel: 2, sampleRate: sr)
            self.emitLog("CallTranslation start (mode=6 stereo) audioType=\(aType.rawValue) sr=\(sr) recordType=\(recordType.rawValue)")
            print("[CallTrans] calling trStartTranslateMode mode=callTranslateStereo(0x06) dataType=\(aType.rawValue) ch=2 sr=\(sr)")
            tm.trStartTranslate(mode) { [weak self] status, err in
                guard let self = self else { return }
                print("[CallTrans] trStartTranslateMode completion status=\(status.rawValue) err=\(err?.localizedDescription ?? "nil")")
                if status == .success || status == .sameMode {
                    self.working = true
                    // 对齐 Android `IAITranslationApi.startTranslating -> callback.onStart()` 语义：
                    // SDK 需要 APP 显式告知「已准备好接收上行音频」才会开始把固件的
                    // cmd=52 帧通过 onReceiveAudioData 推上来。
                    tm.trSendIsRelay()
                    NSLog("[CallTrans] ✅ 通话翻译启动成功 (status=\(status.rawValue) mode=6 stereo sr=\(sr) audioType=\(aType.rawValue) recordType=\(recordType.rawValue)) — 已发 trSendIsRelay，等待耳机立体声上行音频...")
                    self.startHeartbeat()
                    completion(true, nil)
                } else {
                    NSLog("[CallTrans] ❌ 通话翻译启动失败 status=\(status.rawValue) err=\(err?.localizedDescription ?? "nil")")
                    self.emitError(Int(status.rawValue), err?.localizedDescription ?? "trStartTranslateMode failed")
                    self.stop()
                    completion(false, "tm status=\(status.rawValue)")
                }
            }
        }
    }

    public override func stop() {
        stopHeartbeat()
        guard let s = session, working else { working = false; return }
        working = false
        s.release(owner: self)
        decoder?.release(); decoder = nil
        encoderUplink?.release(); encoderUplink = nil
        encoderDownlink?.release(); encoderDownlink = nil
        // 清空 TTS 累积缓冲，避免下次启动残留。
        ttsBufferLock.lock()
        pcmBufferUplink = Data(); pcmBufferDownlink = Data()
        opusBufferUplink = Data(); opusBufferDownlink = Data()
        ttsBufferLock.unlock()
        ttsInCount = 0
        NSLog("[CallTrans] 🛑 CallTranslation stop (totalRxFrames=\(rxFrameCount) uplinkBytes=\(rxUplinkBytes) downlinkBytes=\(rxDownlinkBytes))")
        emitLog("CallTranslation stop")
    }

    // MARK: - Heartbeat (每 2 秒打一次"是否收到上行音频"心跳)

    private func startHeartbeat() {
        stopHeartbeat()
        rxFrameCount = 0
        rxUplinkBytes = 0
        rxDownlinkBytes = 0
        let t = DispatchSource.makeTimerSource(queue: heartbeatQueue)
        t.schedule(deadline: .now() + 2, repeating: 2.0)
        t.setEventHandler { [weak self] in
            guard let self = self, self.working else { return }
            if self.rxFrameCount == 0 {
                NSLog("[CallTrans/Heartbeat] ⚠️ 通话翻译运行中，但耳机上行音频 0 帧 — SDK 尚未回调 onReceiveAudioData。请确认设备是否处于真实通话/录音状态。")
            } else {
                NSLog("[CallTrans/Heartbeat] ✓ rx=\(self.rxFrameCount) 帧 uplinkBytes=\(self.rxUplinkBytes) downlinkBytes=\(self.rxDownlinkBytes)")
            }
        }
        heartbeatTimer = t
        t.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    // MARK: - Audio upstream (SDK → APP)

    public override func onReceiveAudio(_ audio: JLTranslateAudio) {
        rxFrameCount &+= 1
        // 诊断日志：前 5 帧每帧都打，之后每 100 帧打一次。
        if rxFrameCount <= 5 || rxFrameCount % 100 == 1 {
            let msg = "[CallTrans/onRx] #\(rxFrameCount) working=\(working) " +
                      "source=\(audio.sourceType.rawValue) audioType=\(audio.audioType.rawValue) " +
                      "len=\(audio.data.count) count=\(audio.count)"
            NSLog("%@", msg)
            emitLog(msg)
        }
        guard working else { return }
        // mode=6 下耳机只推 SOURCE_E_SCO_MIX（typeESCOMax）一路立体声帧。其它
        // source 如果真的来了，应当当成异常丢掉，而不是错误地当单声道处理。
        guard audio.sourceType == .typeESCOMax else {
            if rxFrameCount <= 5 || rxFrameCount % 100 == 1 {
                let msg = "[CallTrans/onRx] drop unexpected sourceType=\(audio.sourceType.rawValue) (expected typeESCOMax in stereo mode=6)"
                NSLog("%@", msg)
                emitLog(msg)
            }
            return
        }

        switch audio.audioType {
        case .OPUS:
            decoder?.feed(audio.data)  // 解码后在 decoder 回调里拆 L/R 推 IN_UPLINK / IN_DOWNLINK
        case .PCM:
            // 直接立体声 PCM（interleaved L,R, 16bit），立即软分声道
            let (l, r) = PcmKit.splitStereo16(audio.data)
            let fmt = AudioFormat(sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
            rxUplinkBytes &+= Int64(l.count)
            rxDownlinkBytes &+= Int64(r.count)
            pushFrame(streamId: TranslationStreams.IN_UPLINK, pcm: l, format: fmt)
            pushFrame(streamId: TranslationStreams.IN_DOWNLINK, pcm: r, format: fmt)
        default:
            // Speex / JLA_V2 / MSBC 等编码暂不支持立体声软分：记日志丢弃。
            if rxFrameCount <= 5 || rxFrameCount % 100 == 1 {
                let msg = "[CallTrans/onRx] drop non-OPUS/PCM audioType=\(audio.audioType.rawValue) in stereo mode"
                NSLog("%@", msg)
                emitLog(msg)
            }
        }
    }

    // MARK: - TTS downstream (APP → SDK)

    public override func onTranslatedAudio(streamId: String, pcm: Data, format: AudioFormat, isFinal: Bool) -> Bool {
        ttsInCount &+= 1
        // 入口日志：首 5 次 + 每 50 次 + isFinal 必打 + working=false 必打。
        if ttsInCount <= 5 || ttsInCount % 50 == 0 || isFinal || !working {
            NSLog("[CallTrans/feedTTS-IN] #\(ttsInCount) streamId=\(streamId) pcm=\(pcm.count)B isFinal=\(isFinal) working=\(working) audioType=\(audioType.rawValue)")
        }
        guard working else { return false }
        switch streamId {
        case TranslationStreams.OUT_UPLINK:
            return feed(pcm: pcm, encoderTo: encoderUplink, source: .typeESCOUp, leg: streamId, isFinal: isFinal)
        case TranslationStreams.OUT_DOWNLINK:
            return feed(pcm: pcm, encoderTo: encoderDownlink, source: .typeESCODown, leg: streamId, isFinal: isFinal)
        default:
            NSLog("[CallTrans/feedTTS-IN] unknown streamId=\(streamId), drop")
            return false
        }
    }

    /// 对齐 Android `JieliAITranslationBridge.feedTtsPcm`：
    ///   - PCM 模式：每次调用直接作为一段 writeBack。
    ///   - OPUS 模式：纯 isFinal 驱动—— 累积 PCM；`isFinal=true` 时用整段
    ///     PCM 一次性喛给 encoder，收集所有 `onOpus` 回调拼成整段带 head 的 OPUS，然后
    ///     **一次** `trWriteAudioV2` 下发给 SDK/固件。
    ///   - 兜底：缓冲超过 `pcmBufferHardLimitBytes` 强制 flush，和 Android 一致。
    private func feed(
        pcm: Data,
        encoderTo encoder: OpusStreamEncoder?,
        source: JLTranslateAudioSourceType,
        leg: String,
        isFinal: Bool
    ) -> Bool {
        if audioType != .OPUS {
            // PCM 模式：直接单次下发（Android PCM 模式也是这么做）
            if !pcm.isEmpty {
                writeBackAudio(pcm, source: source, audioType: .PCM)
            }
            return true
        }

        // OPUS 模式：累积 + isFinal/超限触发整段编码
        var pendingPcm: Data? = nil
        var bufferAfter: Int = 0
        ttsBufferLock.lock()
        do {
            if !pcm.isEmpty {
                let currentSize = pcmBufferSize(of: leg)
                if currentSize + pcm.count > pcmBufferHardLimitBytes {
                    NSLog("[CallTrans] feedTTS leg=%@ buffer hit hard limit %d, force flush", leg, pcmBufferHardLimitBytes)
                    var out = takePcmBuffer(of: leg)
                    out.append(pcm)
                    pendingPcm = out
                } else {
                    appendPcm(pcm, to: leg)
                }
            }
            if pendingPcm == nil && isFinal {
                let out = takePcmBuffer(of: leg)
                pendingPcm = out.isEmpty ? nil : out
            }
            bufferAfter = pcmBufferSize(of: leg)
        }
        ttsBufferLock.unlock()

        // 累积阶段节流日志：每次超过 100KB 边界打一条。
        if pendingPcm == nil && !pcm.isEmpty {
            let prevK = (bufferAfter - pcm.count) / (100 * 1024)
            let nowK = bufferAfter / (100 * 1024)
            if nowK > prevK {
                NSLog("[CallTrans] feedTTS leg=%@ buffering... pcm=%dB total=%dB (waiting isFinal)", leg, pcm.count, bufferAfter)
            }
        }

        guard let pcmSegment = pendingPcm else { return true }
    
        // 文件级整段编码 — 与 Android `encodeAndDeliverAsync` 对齐。
        // JL SDK 的 `opusEncodeFile` 产出带完整 head 的整段 OPUS 流，直接 `trWriteAudioV2` 下发。
        // （流式的 `opusEncodeData:` 实测在当前场景下回调不触发，opus 输出=0）
        let sr = self.sampleRate
        OpusSegmentEncoder.encode(
            pcm: pcmSegment,
            sampleRate: sr,
            channels: 1,
            hasDataHeader: true
        ) { [weak self] opus, err in
            guard let self = self else { return }
            if let err = err {
                NSLog("[CallTrans] feedTTS leg=%@ final=%@ pcm=%dB opus=0B encode error: %@",
                      leg, isFinal ? "true" : "false", pcmSegment.count, err.localizedDescription)
                return
            }
            guard let opusSegment = opus, !opusSegment.isEmpty else {
                NSLog("[CallTrans] feedTTS leg=%@ final=%@ pcm=%dB opus=0B (empty after file encode, skip)",
                      leg, isFinal ? "true" : "false", pcmSegment.count)
                return
            }
            NSLog("[CallTrans] feedTTS leg=%@ final=%@ pcm=%dB opus=%dB \u{2192} trWriteAudio",
                  leg, isFinal ? "true" : "false", pcmSegment.count, opusSegment.count)
            self.writeBackAudio(opusSegment, source: source, audioType: .OPUS)
        }
        return true
    }

    // MARK: - per-leg buffer helpers (调用方需持有 ttsBufferLock)

    private func pcmBufferSize(of leg: String) -> Int {
        return leg == TranslationStreams.OUT_UPLINK ? pcmBufferUplink.count : pcmBufferDownlink.count
    }

    private func appendPcm(_ data: Data, to leg: String) {
        if leg == TranslationStreams.OUT_UPLINK { pcmBufferUplink.append(data) }
        else { pcmBufferDownlink.append(data) }
    }

    private func takePcmBuffer(of leg: String) -> Data {
        if leg == TranslationStreams.OUT_UPLINK {
            let out = pcmBufferUplink; pcmBufferUplink = Data(); return out
        } else {
            let out = pcmBufferDownlink; pcmBufferDownlink = Data(); return out
        }
    }

    private func resetOpusBuffer(of leg: String) {
        if leg == TranslationStreams.OUT_UPLINK { opusBufferUplink = Data() }
        else { opusBufferDownlink = Data() }
    }

    private func takeOpusBuffer(of leg: String) -> Data {
        if leg == TranslationStreams.OUT_UPLINK {
            let out = opusBufferUplink; opusBufferUplink = Data(); return out
        } else {
            let out = opusBufferDownlink; opusBufferDownlink = Data(); return out
        }
    }

    /// encoder onOpus 回调 → 写入 leg 的 opusBuffer。
    fileprivate func appendOpus(_ opus: Data, to leg: String) {
        ttsBufferLock.lock()
        defer { ttsBufferLock.unlock() }
        if leg == TranslationStreams.OUT_UPLINK { opusBufferUplink.append(opus) }
        else { opusBufferDownlink.append(opus) }
    }

    private func writeBackAudio(_ data: Data, source: JLTranslateAudioSourceType, audioType: JL_SpeakDataType? = nil) {
        guard let tm = session?.currentManager() else {
            NSLog("[CallTrans] writeBackAudio DROPPED: no current manager (source=%d, len=%d)", source.rawValue, data.count)
            return
        }
        let aType = audioType ?? self.audioType
        let audio = JLTranslateAudio()
        audio.sourceType = source
        audio.audioType = aType
        audio.data = data
        audio.len = Int32(data.count)
        audio.count = 1
        // 关键：OPUS 整段（带 head）必须走 `trWriteAudio`（交互式，SDK 按内部队列按帧节奏推 cmd=52）。
        // `trWriteAudioV2` 头注释明确说明：“无交互式下发，当前默认 20ms/42B jlv2 压缩数据，不支持修改”，
        // 整段 OPUS 会被它按 42B 硬切，耳机端解不出来（日志写回成功但无声即此）。
        NSLog("[CallTrans] writeBackAudio \u{2192} trWriteAudio source=%d audioType=%d len=%d",
              source.rawValue, aType.rawValue, data.count)
        tm.trWrite(audio, translate: data)
    }
}
