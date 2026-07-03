import Foundation
import Compression

/// Tiny gzip codec built on Apple's `Compression` framework.
///
/// `Compression` only exposes raw deflate (`COMPRESSION_ZLIB`), so we manually
/// frame it with a 10-byte gzip header + 8-byte trailer (CRC32 + ISIZE) on
/// compress, and strip both on decompress. Used by `sts_volcengine` /
/// `ast_volcengine` which speak a binary frame protocol with mandatory
/// gzip-compressed payloads.
public enum Gzip {

    public enum Error: Swift.Error {
        case invalidHeader
        case decompressFailed
        case compressFailed
    }

    /// Standard gzip header for uncompressed text (FLG=0, OS=255 unknown).
    private static let header: [UInt8] = [
        0x1f, 0x8b,             // magic
        0x08,                   // compression method = deflate
        0x00,                   // flags
        0x00, 0x00, 0x00, 0x00, // mtime
        0x00,                   // xfl
        0xff,                   // os = unknown
    ]

    /// Compress `data` into a gzip-framed payload.
    public static func compress(_ data: Data) throws -> Data {
        let deflated = try rawDeflate(data)
        var out = Data(capacity: header.count + deflated.count + 8)
        out.append(contentsOf: header)
        out.append(deflated)
        let crc = crc32(data)
        let size = UInt32(truncatingIfNeeded: data.count)
        out.append(contentsOf: u32le(crc))
        out.append(contentsOf: u32le(size))
        return out
    }

    /// Decompress a gzip-framed payload back to raw bytes.
    public static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else {
            throw Error.invalidHeader
        }
        let flg = data[3]
        var start = 10
        // FEXTRA
        if (flg & 0x04) != 0 {
            guard start + 2 <= data.count - 8 else { throw Error.invalidHeader }
            let xlen = Int(data[start]) | (Int(data[start + 1]) << 8)
            start += 2 + xlen
        }
        // FNAME
        if (flg & 0x08) != 0 {
            while start < data.count - 8 && data[start] != 0 { start += 1 }
            start += 1
        }
        // FCOMMENT
        if (flg & 0x10) != 0 {
            while start < data.count - 8 && data[start] != 0 { start += 1 }
            start += 1
        }
        // FHCRC
        if (flg & 0x02) != 0 { start += 2 }
        guard start <= data.count - 8 else { throw Error.invalidHeader }

        let bodyEnd = data.count - 8
        let deflated = data.subdata(in: start..<bodyEnd)
        return try rawInflate(deflated)
    }

    // ── Raw deflate / inflate (Compression framework) ──────────────

    private static func rawDeflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let bufferSize = max(data.count, 64 * 1024)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }

        let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dst, bufferSize,
                                             base, data.count,
                                             nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { throw Error.compressFailed }
        return Data(bytes: dst, count: written)
    }

    private static func rawInflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        // Inflated size unknown; grow until decode fits.
        var capacity = max(data.count * 4, 64 * 1024)
        for _ in 0..<6 {
            let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dst.deallocate() }
            let written = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, capacity,
                                                 base, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
            if written > 0 && written < capacity {
                return Data(bytes: dst, count: written)
            }
            capacity *= 4
        }
        throw Error.decompressFailed
    }

    // ── CRC32 (IEEE polynomial, table-driven) ──────────────────────

    private static let crcTable: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            t[i] = c
        }
        return t
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xffffffff
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf {
                c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8)
            }
        }
        return c ^ 0xffffffff
    }

    private static func u32le(_ v: UInt32) -> [UInt8] {
        return [
            UInt8(truncatingIfNeeded: v),
            UInt8(truncatingIfNeeded: v >> 8),
            UInt8(truncatingIfNeeded: v >> 16),
            UInt8(truncatingIfNeeded: v >> 24),
        ]
    }
}
