import Foundation
import JL_BLEKit

/// 翻译特性入口（iOS）—— 7-mode 分发器，对齐 Android `TranslationFeature` 的 method/event 表面。
///
/// # 与 Android 行为差异（按 iOS demo 实测能力定）
/// - **不做 mode=3 → mode=6 自动升级**：iOS demo 由用户手动二选一（callTranslate / callTranslateStereo），
///   我们也沿用这个语义。Dart 端按需直接选 modeId。
/// - 7 个 mode handler 共享同一个 [TranslationSession]（同一台设备一个 `JLTranslationManager`），
///   切换 mode 时先 stop 旧的、再 start 新的。
public final class TranslationFeature {

    private weak var server: JieliHomeServer?

    private let handlers: [Int: BaseTranslationModeHandler]
    private var current: BaseTranslationModeHandler?

    init(server: JieliHomeServer) {
        self.server = server
        self.handlers = [
            TranslationModeIds.MODE_RECORD: RecordModeHandler(server: server),
            TranslationModeIds.MODE_RECORDING_TRANSLATION: RecordingTranslationModeHandler(server: server),
            TranslationModeIds.MODE_CALL_TRANSLATION: CallTranslationModeHandler(server: server),
            TranslationModeIds.MODE_CALL_TRANSLATION_WITH_STEREO: StereoCallTranslationModeHandler(server: server),
            TranslationModeIds.MODE_AUDIO_TRANSLATION: AudioTranslationModeHandler(server: server),
            TranslationModeIds.MODE_FACE_TO_FACE_TRANSLATION: FaceToFaceTranslationModeHandler(server: server),
            TranslationModeIds.MODE_CALL_RECORD: CallRecordModeHandler(server: server),
        ]
    }

    public var isWorking: Bool { current?.isWorking == true }
    public var currentModeId: Int? { current?.modeId }
    public var currentInputStreams: [String] { current?.inputStreams ?? [] }
    public var currentOutputStreams: [String] { current?.outputStreams ?? [] }

    public func start(modeId: Int, args: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let handler = handlers[modeId] else {
            completion(false, "unknown modeId=\(modeId)"); return
        }
        if let cur = current, cur.isWorking, cur !== handler { cur.stop() }
        current = handler
        handler.start(args: args, completion: completion)
    }

    public func stop() {
        current?.stop()
        current = nil
    }

    public func feedTranslatedAudio(
        streamId: String, pcm: Data,
        sampleRate: Int, channels: Int, bitsPerSample: Int,
        isFinal: Bool
    ) -> Bool {
        guard let h = current, h.isWorking else {
            NSLog("[TranslationFeature] feedTranslatedAudio DROPPED: no current/working handler streamId=%@ pcm=%dB isFinal=%@",
                  streamId, pcm.count, isFinal ? "true" : "false")
            return false
        }
        if !h.outputStreams.contains(streamId) {
            NSLog("[TranslationFeature] feedTranslatedAudio DROPPED: streamId=%@ not in handler.outputStreams=%@ (modeId=%d)",
                  streamId, h.outputStreams.description, h.modeId)
            return false
        }
        return h.onTranslatedAudio(
            streamId: streamId, pcm: pcm,
            format: AudioFormat(sampleRate: sampleRate, channels: channels, bitsPerSample: bitsPerSample),
            isFinal: isFinal
        )
    }

    public func feedTranslationResult(
        srcLang: String?, srcText: String?,
        destLang: String?, destText: String?,
        requestId: String?
    ) {
        let mid = current?.modeId ?? 0
        server?.dispatcher.send([
            "type": "translationResult",
            "modeId": mid,
            "srcLang": srcLang as Any,
            "srcText": srcText as Any,
            "destLang": destLang as Any,
            "destText": destText as Any,
            "requestId": requestId as Any,
        ])
    }

    /// 探测设备是否支持立体声通话翻译模式（mode=6）。
    /// iOS SDK 没有显式的 `isSupportCallTranslationWithStereo` API；demo 用
    /// `trIsPlayWithA2dp() == true && trIsSupportTranslate() == true` 综合判定。
    public func isSupportCallTranslationWithStereo(address: String?) -> Bool {
        guard let server = server else { return false }
        let session = address.flatMap { server.translationSession(for: $0) } ?? server.currentTranslationSession()
        guard let tm = session?.currentManager() else { return false }
        return tm.trIsSupportTranslate() && tm.trIsPlayWithA2dp()
    }

    public func feedAudioFilePcm(pcm: Data, sampleRate: Int) -> Bool {
        guard let h = current as? AudioTranslationModeHandler else { return false }
        return h.feedFilePcm(pcm, sampleRate: sampleRate)
    }
}
