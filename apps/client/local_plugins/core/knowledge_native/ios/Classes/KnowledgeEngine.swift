import Foundation

/// md 文库（真源）：每条笔记一份 `<id>.md`，落盘于 rootPath。镜像 Kotlin MarkdownVault。
final class MarkdownVault {
    struct Note { let id: String; let frontmatter: [String: String]; let body: String }

    private let rootPath: String
    init(_ rootPath: String) { self.rootPath = rootPath }

    private func root() -> URL {
        let url = URL(fileURLWithPath: rootPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func file(_ id: String) -> URL { root().appendingPathComponent("\(id).md") }

    func put(_ note: Note) {
        var s = "---\n"
        for (k, v) in note.frontmatter { s += "\(k): \(v.replacingOccurrences(of: "\n", with: " "))\n" }
        s += "---\n" + note.body
        try? s.write(to: file(note.id), atomically: true, encoding: .utf8)
    }

    func read(_ id: String) -> Note? {
        guard let raw = try? String(contentsOf: file(id), encoding: .utf8) else { return nil }
        return parse(id, raw)
    }

    func listIds() -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: root().path)) ?? []
        return items.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted()
    }

    func exists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: file(id).path) }
    func delete(_ id: String) { try? FileManager.default.removeItem(at: file(id)) }

    private func parse(_ id: String, _ raw: String) -> Note {
        var fm: [String: String] = [:]
        var body = raw
        if raw.hasPrefix("---") {
            let afterFence = raw.index(raw.startIndex, offsetBy: 3)
            if let endRange = raw.range(of: "\n---", range: afterFence..<raw.endIndex) {
                let block = String(raw[afterFence..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                for line in block.split(separator: "\n") {
                    if let ci = line.firstIndex(of: ":") {
                        let key = String(line[line.startIndex..<ci]).trimmingCharacters(in: .whitespaces)
                        let val = String(line[line.index(after: ci)...]).trimmingCharacters(in: .whitespaces)
                        fm[key] = val
                    }
                }
                if let nl = raw.range(of: "\n", range: endRange.upperBound..<raw.endIndex) {
                    body = String(raw[nl.upperBound...])
                } else {
                    body = ""
                }
            }
        }
        return Note(id: id, frontmatter: fm, body: body)
    }
}

/// 本地用户级知识库服务（原生门面）。镜像 Kotlin KnowledgeEngine。
///
/// 纯原生 agents_server 直接实例化调用（后台/设备唤醒，不经 Flutter）：
/// ```swift
/// let kb = KnowledgeEngine(vaultPath: dir)
/// kb.ingestMarkdown(userId: "u1", title: "连接蓝牙耳机", markdown: "…")
/// let ctx = kb.answerContext("蓝牙耳机怎么配对", userId: "u1")  // → 交 LLM
/// ```
final class KnowledgeEngine {
    private let vault: MarkdownVault
    private let embedder: EmbeddingProvider
    private let store: KnowledgeStore
    private let vectors: VectorStore
    private let chunker: Chunker
    private let retriever: Retriever
    private var counter = 0

    init(vaultPath: String,
         embedder: EmbeddingProvider = HashingEmbedding(),
         store: KnowledgeStore = InMemoryKnowledgeStore(),
         vectors: VectorStore = InMemoryVectorStore(),
         chunker: Chunker = Chunker()) {
        self.vault = MarkdownVault(vaultPath)
        self.embedder = embedder
        self.store = store
        self.vectors = vectors
        self.chunker = chunker
        self.retriever = Retriever(vectors: vectors, store: store, embedder: embedder)
    }

    private func nextId(_ prefix: String) -> String {
        let t = DispatchTime.now().uptimeNanoseconds
        let s = "\(prefix)-\(String(t, radix: 36))-\(String(counter, radix: 36))"
        counter += 1
        return s
    }

    @discardableResult
    func ingestMarkdown(userId: String, title: String, markdown: String,
                        kind: String = "note", sourceUri: String? = nil, id: String? = nil) -> String {
        let docId = id ?? nextId("doc")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var fm = ["id": docId, "title": title, "userId": userId, "kind": kind, "createdAt": "\(now)"]
        if let u = sourceUri { fm["uri"] = u }
        vault.put(MarkdownVault.Note(id: docId, frontmatter: fm, body: markdown))
        let doc = KbDocument(id: docId, sourceId: nextId("src"), userId: userId, title: title, createdAt: now)
        store.putDocument(doc)
        indexDocument(doc, markdown)
        return docId
    }

    func retrieve(_ query: String, k: Int = 6, userId: String? = nil) -> [ScoredChunk] {
        retriever.retrieve(query, k: k, userId: userId)
    }

    func answerContext(_ query: String, k: Int = 6, userId: String? = nil) -> String {
        let hits = retrieve(query, k: k, userId: userId)
        var s = ""
        for (i, h) in hits.enumerated() {
            s += "[\(i + 1)] 《\(h.documentTitle ?? h.chunk.documentId)》\n"
            s += h.chunk.text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deleteDocument(_ docId: String) {
        vault.delete(docId)
        vectors.deleteByDocument(docId)
        store.deleteDocument(docId)
    }

    @discardableResult
    func reindexFromVault(userId: String? = nil) -> Int {
        store.clearIndex(); vectors.clear()
        var n = 0
        for id in vault.listIds() {
            guard let note = vault.read(id) else { continue }
            let uid = note.frontmatter["userId"] ?? "default"
            if let want = userId, uid != want { continue }
            let createdAt = Int64(note.frontmatter["createdAt"] ?? "") ?? 0
            let doc = KbDocument(id: id, sourceId: "src-\(id)", userId: uid,
                                 title: note.frontmatter["title"], createdAt: createdAt)
            store.putDocument(doc)
            indexDocument(doc, note.body)
            n += 1
        }
        return n
    }

    func vectorCount() -> Int { vectors.count() }

    private func indexDocument(_ doc: KbDocument, _ markdown: String) {
        let pieces = chunker.chunk(markdown)
        var chunks: [KbChunk] = []
        for (i, piece) in pieces.enumerated() {
            chunks.append(KbChunk(id: "\(doc.id)#\(i)", documentId: doc.id, userId: doc.userId,
                                  ordinal: i, text: piece.0, loc: piece.1))
        }
        store.putChunks(chunks)
        let vecs = embedder.embedBatch(chunks.map { $0.text })
        var recs: [VectorRecord] = []
        for (i, c) in chunks.enumerated() {
            recs.append(VectorRecord(chunkId: c.id, documentId: doc.id, userId: doc.userId, vector: vecs[i]))
        }
        vectors.upsert(recs)
    }
}
