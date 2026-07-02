import Foundation
import SQLite3

// KB 自带索引库（独立 db 文件）——iOS 内置 SQLite3（libsqlite3，无需额外 pod）。
// 向量存 BLOB + 暴力余弦；个人 KB 规模小无需 sqlite-vec。真源仍是 md 文库，本库可重建。
// ⚠️ 未编译验证：SQLite3 C 互操作请在真机 XCTest 确认（尤其 bind/column 边界）。

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ st: OpaquePointer?, _ i: Int32, _ s: String) {
    sqlite3_bind_text(st, i, s, -1, SQLITE_TRANSIENT)
}
private func bindTextOpt(_ st: OpaquePointer?, _ i: Int32, _ s: String?) {
    if let s = s { sqlite3_bind_text(st, i, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(st, i) }
}
private func colText(_ st: OpaquePointer?, _ i: Int32) -> String {
    if let c = sqlite3_column_text(st, i) { return String(cString: c) }
    return ""
}
private func colTextOpt(_ st: OpaquePointer?, _ i: Int32) -> String? {
    if let c = sqlite3_column_text(st, i) { return String(cString: c) }
    return nil
}
private func vecToData(_ v: [Double]) -> Data {
    v.withUnsafeBufferPointer { Data(buffer: $0) }
}
private func dataToVec(_ d: Data) -> [Double] {
    let n = d.count / MemoryLayout<Double>.size
    var out = [Double](repeating: 0, count: n)
    _ = out.withUnsafeMutableBytes { d.copyBytes(to: $0) }
    return out
}

final class KnowledgeDb {
    fileprivate var db: OpaquePointer?
    init(path: String) {
        if sqlite3_open(path, &db) == SQLITE_OK { createTables() }
    }
    deinit { sqlite3_close(db) }
    fileprivate func exec(_ sql: String) { sqlite3_exec(db, sql, nil, nil, nil) }
    private func createTables() {
        exec("CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY, source_id TEXT, user_id TEXT, title TEXT, created_at INTEGER)")
        exec("CREATE TABLE IF NOT EXISTS chunks(id TEXT PRIMARY KEY, document_id TEXT, user_id TEXT, ordinal INTEGER, text TEXT, loc_start INTEGER, loc_end INTEGER, heading TEXT)")
        exec("CREATE INDEX IF NOT EXISTS idx_chunks_user ON chunks(user_id)")
        exec("CREATE TABLE IF NOT EXISTS embeddings(chunk_id TEXT PRIMARY KEY, document_id TEXT, user_id TEXT, dim INTEGER, vec BLOB)")
        exec("CREATE INDEX IF NOT EXISTS idx_emb_user ON embeddings(user_id)")
    }
}

/// 一把拿到基于同一 db 的两个端口实现，注入 KnowledgeEngine。
final class SqliteKnowledgeIndex {
    let db: KnowledgeDb
    let store: KnowledgeStore
    let vectors: VectorStore
    init(path: String) {
        let d = KnowledgeDb(path: path)
        db = d
        store = SqliteKnowledgeStore(d)
        vectors = SqliteVectorStore(d)
    }
}

final class SqliteKnowledgeStore: KnowledgeStore {
    private let dbh: KnowledgeDb
    init(_ dbh: KnowledgeDb) { self.dbh = dbh }
    private var db: OpaquePointer? { dbh.db }

    func putDocument(_ doc: KbDocument) {
        var st: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO documents(id,source_id,user_id,title,created_at) VALUES(?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(st) }
        bindText(st, 1, doc.id); bindText(st, 2, doc.sourceId); bindText(st, 3, doc.userId)
        bindTextOpt(st, 4, doc.title); sqlite3_bind_int64(st, 5, doc.createdAt)
        sqlite3_step(st)
    }

    func putChunks(_ chunks: [KbChunk]) {
        dbh.exec("BEGIN")
        let sql = "INSERT OR REPLACE INTO chunks(id,document_id,user_id,ordinal,text,loc_start,loc_end,heading) VALUES(?,?,?,?,?,?,?,?)"
        for c in chunks {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                bindText(st, 1, c.id); bindText(st, 2, c.documentId); bindText(st, 3, c.userId)
                sqlite3_bind_int(st, 4, Int32(c.ordinal)); bindText(st, 5, c.text)
                sqlite3_bind_int(st, 6, Int32(c.loc.start)); sqlite3_bind_int(st, 7, Int32(c.loc.end))
                bindTextOpt(st, 8, c.loc.heading)
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
        dbh.exec("COMMIT")
    }

    func getChunk(_ id: String) -> KbChunk? { queryChunks(whereClause: "WHERE id = ?", args: [id]).first }

    func getDocument(_ id: String) -> KbDocument? {
        var st: OpaquePointer?
        let sql = "SELECT id,source_id,user_id,title,created_at FROM documents WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        bindText(st, 1, id)
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        return KbDocument(id: colText(st, 0), sourceId: colText(st, 1), userId: colText(st, 2),
                          title: colTextOpt(st, 3), createdAt: sqlite3_column_int64(st, 4))
    }

    func allChunks(userId: String?) -> [KbChunk] {
        if let u = userId { return queryChunks(whereClause: "WHERE user_id = ?", args: [u]) }
        return queryChunks(whereClause: "", args: [])
    }

    func deleteDocument(_ documentId: String) {
        for sql in ["DELETE FROM chunks WHERE document_id = ?", "DELETE FROM documents WHERE id = ?"] {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK { bindText(st, 1, documentId); sqlite3_step(st) }
            sqlite3_finalize(st)
        }
    }

    func clearIndex() { dbh.exec("DELETE FROM chunks"); dbh.exec("DELETE FROM documents") }

    private func queryChunks(whereClause: String, args: [String]) -> [KbChunk] {
        var st: OpaquePointer?
        let sql = "SELECT id,document_id,user_id,ordinal,text,loc_start,loc_end,heading FROM chunks \(whereClause)"
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        for (i, a) in args.enumerated() { bindText(st, Int32(i + 1), a) }
        var out: [KbChunk] = []
        while sqlite3_step(st) == SQLITE_ROW {
            out.append(KbChunk(
                id: colText(st, 0), documentId: colText(st, 1), userId: colText(st, 2),
                ordinal: Int(sqlite3_column_int(st, 3)), text: colText(st, 4),
                loc: ChunkLoc(start: Int(sqlite3_column_int(st, 5)), end: Int(sqlite3_column_int(st, 6)), heading: colTextOpt(st, 7))
            ))
        }
        return out
    }
}

final class SqliteVectorStore: VectorStore {
    private let dbh: KnowledgeDb
    init(_ dbh: KnowledgeDb) { self.dbh = dbh }
    private var db: OpaquePointer? { dbh.db }

    func upsert(_ records: [VectorRecord]) {
        dbh.exec("BEGIN")
        let sql = "INSERT OR REPLACE INTO embeddings(chunk_id,document_id,user_id,dim,vec) VALUES(?,?,?,?,?)"
        for r in records {
            var st: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK {
                bindText(st, 1, r.chunkId); bindText(st, 2, r.documentId); bindText(st, 3, r.userId)
                sqlite3_bind_int(st, 4, Int32(r.vector.count))
                let data = vecToData(r.vector)
                data.withUnsafeBytes { raw in
                    sqlite3_bind_blob(st, 5, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                }
                sqlite3_step(st)
            }
            sqlite3_finalize(st)
        }
        dbh.exec("COMMIT")
    }

    func search(_ query: [Double], k: Int, userId: String?) -> [(String, Double)] {
        var st: OpaquePointer?
        let sql = "SELECT chunk_id, vec FROM embeddings" + (userId != nil ? " WHERE user_id = ?" : "")
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(st) }
        if let u = userId { bindText(st, 1, u) }
        var hits: [(String, Double)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let id = colText(st, 0)
            if let blob = sqlite3_column_blob(st, 1) {
                let n = Int(sqlite3_column_bytes(st, 1))
                hits.append((id, cosine(query, dataToVec(Data(bytes: blob, count: n)))))
            }
        }
        return hits.sorted { $0.1 > $1.1 }.prefix(k).map { $0 }
    }

    func deleteByDocument(_ documentId: String) {
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM embeddings WHERE document_id = ?", -1, &st, nil) == SQLITE_OK {
            bindText(st, 1, documentId); sqlite3_step(st)
        }
        sqlite3_finalize(st)
    }

    func clear() { dbh.exec("DELETE FROM embeddings") }

    func count() -> Int {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM embeddings", -1, &st, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? Int(sqlite3_column_int(st, 0)) : 0
    }
}
