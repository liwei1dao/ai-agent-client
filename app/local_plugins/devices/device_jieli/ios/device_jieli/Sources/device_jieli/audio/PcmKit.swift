import Foundation

/// 16-bit signed PCM 工具集 —— 与 Android `audio/PcmKit.kt` 对齐。
public enum PcmKit {

    /// 把 16-bit signed stereo interleaved PCM (L/R/L/R…) 拆成左右两路 mono。
    /// 输入字节数必须为 4 的整数倍。
    public static func splitStereo16(_ interleaved: Data) -> (left: Data, right: Data) {
        let n = interleaved.count
        guard n >= 4 else { return (Data(), Data()) }
        let frameCount = n / 4
        var left = Data(count: frameCount * 2)
        var right = Data(count: frameCount * 2)
        interleaved.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self).baseAddress!
            left.withUnsafeMutableBytes { (lRaw: UnsafeMutableRawBufferPointer) in
                right.withUnsafeMutableBytes { (rRaw: UnsafeMutableRawBufferPointer) in
                    let lp = lRaw.bindMemory(to: UInt8.self).baseAddress!
                    let rp = rRaw.bindMemory(to: UInt8.self).baseAddress!
                    for i in 0..<frameCount {
                        let inOfs = i * 4
                        let outOfs = i * 2
                        lp[outOfs] = p[inOfs]
                        lp[outOfs + 1] = p[inOfs + 1]
                        rp[outOfs] = p[inOfs + 2]
                        rp[outOfs + 1] = p[inOfs + 3]
                    }
                }
            }
        }
        return (left, right)
    }

    /// 把两路 16-bit mono PCM 交织成 stereo (L/R/L/R…)
    public static func interleaveStereo16(left: Data, right: Data) -> Data {
        let frameCount = min(left.count, right.count) / 2
        var out = Data(count: frameCount * 4)
        left.withUnsafeBytes { (lRaw: UnsafeRawBufferPointer) in
            right.withUnsafeBytes { (rRaw: UnsafeRawBufferPointer) in
                out.withUnsafeMutableBytes { (oRaw: UnsafeMutableRawBufferPointer) in
                    let lp = lRaw.bindMemory(to: UInt8.self).baseAddress!
                    let rp = rRaw.bindMemory(to: UInt8.self).baseAddress!
                    let op = oRaw.bindMemory(to: UInt8.self).baseAddress!
                    for i in 0..<frameCount {
                        let inOfs = i * 2
                        let outOfs = i * 4
                        op[outOfs] = lp[inOfs]
                        op[outOfs + 1] = lp[inOfs + 1]
                        op[outOfs + 2] = rp[inOfs]
                        op[outOfs + 3] = rp[inOfs + 1]
                    }
                }
            }
        }
        return out
    }
}
