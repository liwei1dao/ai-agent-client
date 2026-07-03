import Foundation
import JLAudioUnitKit

/// OPUS 流式解码器 —— 与 Android `OpusStreamDecoder` 同语义。
///
/// 输入：从耳机收到的 OPUS 编码帧（一次一帧，最大 ~80B）
/// 输出：16kHz / 给定声道 PCM 流（16-bit signed little-endian, interleaved）
///
/// **dataSize 是单个 OPUS 帧的实际字节大小**：
///   - 16k / 16bit / mono / 20ms ≈ 40 B
///   - 16k / 16bit / stereo / 20ms ≈ 80 B
///
/// 这与 Android `OpusStreamDecoder.packetSize` 对齐：传错值会导致 OpusManager 把多帧拼成
/// 一帧解，丢 80% 数据。
public final class OpusStreamDecoder {

    private let proxy: OpusDecoderProxy
    private let decoder: JLOpusDecoder

    public init(
        channels: Int = 1,
        dataSize: Int = 40,
        sampleRate: Int = 16000,
        hasDataHeader: Bool = false,
        onPcm: @escaping (Data) -> Void,
        onError: @escaping (Int, String?) -> Void = { _, _ in }
    ) {
        let fmt = JLOpusFormat.defaultFormats()
        fmt.sampleRate = Int32(sampleRate)
        fmt.channels = Int32(channels)
        fmt.frameDuration = 20
        fmt.dataSize = Int32(dataSize)
        fmt.hasDataHeader = hasDataHeader

        let proxy = OpusDecoderProxy(onPcm: onPcm, onError: onError)
        self.proxy = proxy
        self.decoder = JLOpusDecoder(decoder: fmt, delegate: proxy)
    }

    public func feed(_ opus: Data) {
        decoder.opusDecoderInputData(opus)
    }

    public func release() {
        decoder.opusOnRelease()
    }
}

/// JLOpusDecoder 的 delegate 是 `weak`，Swift class 直接做 delegate 会被立刻 dealloc。
/// 我们让 OpusStreamDecoder 强引用这个 proxy（通过 stored property）来保活。
private final class OpusDecoderProxy: NSObject, JLOpusDecoderDelegate {
    private let onPcm: (Data) -> Void
    private let onError: (Int, String?) -> Void

    init(onPcm: @escaping (Data) -> Void, onError: @escaping (Int, String?) -> Void) {
        self.onPcm = onPcm
        self.onError = onError
    }

    func opusDecoder(_ decoder: JLOpusDecoder, data: Data?, error: Error?) {
        if let err = error as NSError? {
            onError(err.code, err.localizedDescription); return
        }
        if let data = data, !data.isEmpty { onPcm(data) }
    }
}

/// OPUS 流式编码器 —— 与 Android `OpusStreamEncoder` 同语义。
///
/// 输入：16k/16bit/mono PCM 帧（20ms 步长 = 640 B）
/// 输出：OPUS 编码帧（默认无头，~40 B）
public final class OpusStreamEncoder {

    private let proxy: OpusEncoderProxy
    private let encoder: JLOpusEncoder

    public init(
        channels: Int = 1,
        sampleRate: Int = 16000,
        hasDataHeader: Bool = false,
        onOpus: @escaping (Data) -> Void,
        onError: @escaping (Int, String?) -> Void = { _, _ in }
    ) {
        let cfg = JLOpusEncodeConfig.defaultJL()
        cfg.sampleRate = Int32(sampleRate)
        cfg.channels = Int32(channels)
        cfg.frameDuration = 20
        cfg.hasDataHeader = hasDataHeader

        let proxy = OpusEncoderProxy(onOpus: onOpus, onError: onError)
        self.proxy = proxy
        self.encoder = JLOpusEncoder(format: cfg, delegate: proxy)
    }

    public func feed(_ pcm: Data) {
        encoder.opusEncode(pcm)
    }

    public func release() {
        encoder.opusOnRelease()
    }
}

private final class OpusEncoderProxy: NSObject, JLOpusEncoderDelegate {
    private let onOpus: (Data) -> Void
    private let onError: (Int, String?) -> Void

    init(onOpus: @escaping (Data) -> Void, onError: @escaping (Int, String?) -> Void) {
        self.onOpus = onOpus
        self.onError = onError
    }

    func opusEncoder(_ encoder: JLOpusEncoder, data: Data?, error: Error?) {
        if let err = error as NSError? {
            onError(err.code, err.localizedDescription); return
        }
        if let data = data, !data.isEmpty { onOpus(data) }
    }
}

/// 文件级整段 OPUS 编码 —— 与 Android `JieliAITranslationBridge.encodeAndDeliverAsync` 对齐。
///
/// 调用 `JLOpusEncoder.opusEncodeFile:output:result:` 把一整段 PCM 转成一整段带完整 head 的 OPUS 流。
/// 完全不走 delegate 回调（`opusEncoder:Data:error:`），仅仅从输出文件读出成果。
///
/// 为什么不用 `opusEncodeData:` 流式接口：
///   - 流式接口 per-frame 给不同的 partial OPUS，每次不一定带 head，拼出来的东西 SDK
///     切包销资性无法按 “一整段 utterance” 方式写回耳机。
///   - 文件接口内部完整初始化 OggOpus（hasDataHeader=true）+ 批量写入，与 demo `MachineTranslation.tryToTTS`
///     给 SDK 的格式一致。
public enum OpusSegmentEncoder {
    /// 对 `pcm` 整段文件级编码，结果在主线程以外的 SDK 内部线程回调。
    /// completion 传回`(opusData, error)`：两者至少一个非 nil；成功时 opusData 非空。
    public static func encode(
        pcm: Data,
        sampleRate: Int = 16000,
        channels: Int = 1,
        hasDataHeader: Bool = true,
        completion: @escaping (Data?, Error?) -> Void
    ) {
        guard !pcm.isEmpty else {
            completion(nil, NSError(domain: "OpusSegmentEncoder", code: -1,
                                    userInfo: [NSLocalizedDescriptionKey: "empty pcm input"]))
            return
        }

        let tmpDir = NSTemporaryDirectory() as NSString
        let seq = UUID().uuidString
        let pcmPath = tmpDir.appendingPathComponent("tts_\(seq).pcm")
        let opusPath = tmpDir.appendingPathComponent("tts_\(seq).opus")

        do {
            try pcm.write(to: URL(fileURLWithPath: pcmPath))
        } catch {
            completion(nil, error)
            return
        }

        // 对齐 Android：Android 侧 `OpusManager().encodeFile(...)` 不显式设置任何
        // 字段，直接使用 `OpusOption` 的默认配置（带 head）。
        // iOS 这边对应的是 `defaultConfig`（完整默认，带 head），而不是
        // `defaultJL`（注释说明是「杰理的无头配置」，字段默认值和带头模式
        // 不同，在其上手动叠 hasDataHeader=YES + bitRate=16000 + bandwidth=WIDEBAND
        // 干预的字段越多、与 Android 缺省行为的偏移就越大，导致耳机
        // 解码后声音扰曲错乱。直接用 defaultConfig 不动任何字段是最安全的对齐方式。
        let cfg = JLOpusEncodeConfig.defaultJL()
        cfg.sampleRate = Int32(sampleRate)
        cfg.channels = Int32(channels)

        // delegate 必须非 nil（且 weak，需要 stored 保活）。文件接口不会触发 data 回调，
        // 只是为满足初始化签名。
        let dummy = _SilentOpusEncoderDelegate()
        let encoder = JLOpusEncoder(format: cfg, delegate: dummy)

        encoder.opusEncodeFile(pcmPath, output: opusPath) { outPath, err in
            // 保活 dummy，避免被 ARC 提前释放导致 SDK 的 weak delegate 空指。
            _ = dummy
            defer {
                encoder.opusOnRelease()
                try? FileManager.default.removeItem(atPath: pcmPath)
                try? FileManager.default.removeItem(atPath: opusPath)
            }
            if let err = err {
                completion(nil, err); return
            }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: opusPath)), !data.isEmpty else {
                completion(nil, NSError(domain: "OpusSegmentEncoder", code: -2,
                                        userInfo: [NSLocalizedDescriptionKey: "empty opus output"]))
                return
            }
            completion(data, nil)
        }
    }
}

private final class _SilentOpusEncoderDelegate: NSObject, JLOpusEncoderDelegate {
    func opusEncoder(_ encoder: JLOpusEncoder, data: Data?, error: Error?) {
        // 文件级接口不走此回调，留空。
    }
}
