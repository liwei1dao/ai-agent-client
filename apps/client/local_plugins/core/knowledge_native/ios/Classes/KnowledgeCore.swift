import Foundation

// 知识库算法核心（Swift）——镜像 KnowledgeCore.kt / 已验证的 Dart 核心。
// 供纯原生 agents_server 后台/唤醒直调；默认零外部依赖（内存索引 + 特征哈希嵌入）。

// MARK: - 分词

/// ASCII 词 + 中文单字/相邻双字(bigram)。与 Kotlin/Dart 一致。
func tokenize(_ input: String) -> [String] {
    var tokens: [String] = []
    var buf = ""
    var prevCjk: UnicodeScalar? = nil
    func flush() { if !buf.isEmpty { tokens.append(buf); buf = "" } }
    for scalar in input.lowercased().unicodeScalars {
        let cp = scalar.value
        let isAsciiAlnum = (cp >= 0x30 && cp <= 0x39) || (cp >= 0x61 && cp <= 0x7a)
        let isCjk = cp >= 0x4E00 && cp <= 0x9FFF
        if isAsciiAlnum {
            buf.unicodeScalars.append(scalar)
            prevCjk = nil
        } else if isCjk {
            flush()
            tokens.append(String(scalar))
            if let p = prevCjk { tokens.append(String(p) + String(scalar)) }
            prevCjk = scalar
        } else {
            flush()
            prevCjk = nil
        }
    }
    flush()
    return tokens
}

/// 确定性 32-bit FNV-1a（按 UTF-16 code unit，跨运行稳定）。
func fnv1a(_ s: String) -> UInt64 {
    var h: UInt64 = 0x811c9dc5
    for u in s.utf16 {
        h ^= UInt64(u)
        h = (h &* 0x01000193) & 0xffffffff
    }
    return h
}

// MARK: - 模型

struct ChunkLoc { let start: Int; let end: Int; let heading: String? }

struct KbChunk {
    let id: String
    let documentId: String
    let userId: String
    let ordinal: Int
    let text: String
    let loc: ChunkLoc
}

struct KbDocument {
    let id: String
    let sourceId: String
    let userId: String
    let title: String?
    let createdAt: Int64
}

struct ScoredChunk { let chunk: KbChunk; let score: Double; let documentTitle: String? }

// MARK: - 端口

protocol EmbeddingProvider {
    var model: String { get }
    var dim: Int { get }
    func embed(_ text: String) -> [Double]
}
extension EmbeddingProvider {
    func embedBatch(_ texts: [String]) -> [[Double]] { texts.map { embed($0) } }
}

struct VectorRecord { let chunkId: String; let documentId: String; let userId: String; let vector: [Double] }

protocol VectorStore {
    func upsert(_ records: [VectorRecord])
    /// 返回 (chunkId, 余弦相似度) 降序 topK。
    func search(_ query: [Double], k: Int, userId: String?) -> [(String, Double)]
    func deleteByDocument(_ documentId: String)
    func clear()
    func count() -> Int
}

protocol KnowledgeStore {
    func putDocument(_ doc: KbDocument)
    func putChunks(_ chunks: [KbChunk])
    func getChunk(_ id: String) -> KbChunk?
    func getDocument(_ id: String) -> KbDocument?
    func allChunks(userId: String?) -> [KbChunk]
    func deleteDocument(_ documentId: String)
    func clearIndex()
}

// MARK: - 端上哈希嵌入（默认/离线）

/// 平台层可用 ONNX 本地模型（bge-small-zh/e5-small）实现同一协议替换。
final class HashingEmbedding: EmbeddingProvider {
    let dim: Int
    init(dim: Int = 256) { self.dim = dim }
    var model: String { "hashing-v1-\(dim)" }
    func embed(_ text: String) -> [Double] {
        var v = [Double](repeating: 0, count: dim)
        for tok in tokenize(text) {
            let h = fnv1a(tok)
            let idx = Int(h % UInt64(dim))
            let sign = (fnv1a("#" + tok) & 1) == 0 ? 1.0 : -1.0
            v[idx] += sign
        }
        var norm = 0.0
        for x in v { norm += x * x }
        norm = norm.squareRoot()
        if norm > 0 { for i in 0..<dim { v[i] /= norm } }
        return v
    }
}

func cosine(_ a: [Double], _ b: [Double]) -> Double {
    let n = min(a.count, b.count)
    var dot = 0.0, na = 0.0, nb = 0.0
    for i in 0..<n { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    if na == 0 || nb == 0 { return 0 }
    return dot / (na.squareRoot() * nb.squareRoot())
}

// MARK: - 切块

final class Chunker {
    let maxChars: Int
    let overlap: Int
    init(maxChars: Int = 800, overlap: Int = 120) { self.maxChars = maxChars; self.overlap = overlap }

    func chunk(_ markdown: String) -> [(String, ChunkLoc)] {
        var out: [(String, ChunkLoc)] = []
        let paras = splitParagraphs(markdown)
        var buf = ""
        var bufStart = 0
        var heading: String? = nil
        func flush(_ end: Int) {
            let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append((t, ChunkLoc(start: bufStart, end: end, heading: heading))) }
            buf = ""
        }
        for (text, start) in paras {
            if isHeading(text) { heading = stripHeading(text) }
            if !buf.isEmpty && buf.count + text.count > maxChars {
                flush(start)
                let prev = out.last?.0 ?? ""
                let tail = prev.count > overlap ? String(prev.suffix(overlap)) : prev
                buf += tail
                bufStart = start
            }
            if buf.isEmpty { bufStart = start } else { buf += "\n\n" }
            buf += text
        }
        flush(markdown.count)
        return out
    }

    private func isHeading(_ s: String) -> Bool {
        var hashes = 0
        for ch in s {
            if ch == "#" { hashes += 1 }
            else { return hashes >= 1 && hashes <= 6 && (ch == " " || ch == "\t") }
        }
        return false
    }

    private func stripHeading(_ s: String) -> String {
        var i = s.startIndex
        while i < s.endIndex && s[i] == "#" { i = s.index(after: i) }
        return String(s[i...]).trimmingCharacters(in: .whitespaces)
    }

    private func splitParagraphs(_ md: String) -> [(String, Int)] {
        var res: [(String, Int)] = []
        var cursor = md.startIndex
        for raw in md.components(separatedBy: "\n\n") {
            guard !raw.isEmpty,
                  let range = md.range(of: raw, range: cursor..<md.endIndex) else { continue }
            let start = md.distance(from: md.startIndex, to: range.lowerBound)
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { res.append((t, start)) }
            cursor = range.upperBound
        }
        return res
    }
}

// MARK: - 内存存储（默认实现）

final class InMemoryVectorStore: VectorStore {
    private var byChunk: [String: VectorRecord] = [:]
    func upsert(_ records: [VectorRecord]) { for r in records { byChunk[r.chunkId] = r } }
    func search(_ query: [Double], k: Int, userId: String?) -> [(String, Double)] {
        byChunk.values
            .filter { userId == nil || $0.userId == userId }
            .map { ($0.chunkId, cosine(query, $0.vector)) }
            .sorted { $0.1 > $1.1 }
            .prefix(k)
            .map { $0 }
    }
    func deleteByDocument(_ documentId: String) {
        byChunk = byChunk.filter { $0.value.documentId != documentId }
    }
    func clear() { byChunk.removeAll() }
    func count() -> Int { byChunk.count }
}

final class InMemoryKnowledgeStore: KnowledgeStore {
    private var docs: [String: KbDocument] = [:]
    private var chunks: [String: KbChunk] = [:]
    func putDocument(_ doc: KbDocument) { docs[doc.id] = doc }
    func putChunks(_ chunkList: [KbChunk]) { for c in chunkList { chunks[c.id] = c } }
    func getChunk(_ id: String) -> KbChunk? { chunks[id] }
    func getDocument(_ id: String) -> KbDocument? { docs[id] }
    func allChunks(userId: String?) -> [KbChunk] {
        chunks.values.filter { userId == nil || $0.userId == userId }
    }
    func deleteDocument(_ documentId: String) {
        docs[documentId] = nil
        chunks = chunks.filter { $0.value.documentId != documentId }
    }
    func clearIndex() { docs.removeAll(); chunks.removeAll() }
}

// MARK: - 混合检索（向量 + 关键词 RRF）

final class Retriever {
    private let vectors: VectorStore
    private let store: KnowledgeStore
    private let embedder: EmbeddingProvider
    private let rrfK: Int
    init(vectors: VectorStore, store: KnowledgeStore, embedder: EmbeddingProvider, rrfK: Int = 60) {
        self.vectors = vectors; self.store = store; self.embedder = embedder; self.rrfK = rrfK
    }

    func retrieve(_ query: String, k: Int = 6, userId: String? = nil) -> [ScoredChunk] {
        let qvec = embedder.embed(query)
        let vHits = vectors.search(qvec, k: k * 3, userId: userId).map { $0.0 }
        let kHits = keyword(query, k: k * 3, userId: userId)

        var fused: [String: Double] = [:]
        func fuse(_ ids: [String]) {
            for (i, id) in ids.enumerated() { fused[id, default: 0] += 1.0 / Double(rrfK + i + 1) }
        }
        fuse(vHits); fuse(kHits)

        return fused.sorted { $0.value > $1.value }.prefix(k).compactMap { e in
            guard let c = store.getChunk(e.key) else { return nil }
            let doc = store.getDocument(c.documentId)
            return ScoredChunk(chunk: c, score: e.value, documentTitle: doc?.title)
        }
    }

    private func keyword(_ query: String, k: Int, userId: String?) -> [String] {
        let q = Set(tokenize(query))
        if q.isEmpty { return [] }
        return store.allChunks(userId: userId).compactMap { c -> (String, Double)? in
            let toks = tokenize(c.text)
            if toks.isEmpty { return nil }
            let hit = toks.filter { q.contains($0) }.count
            return hit > 0 ? (c.id, Double(hit) / Double(toks.count)) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(k)
        .map { $0.0 }
    }
}
