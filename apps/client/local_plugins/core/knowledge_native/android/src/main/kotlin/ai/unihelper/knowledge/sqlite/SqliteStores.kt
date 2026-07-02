package ai.unihelper.knowledge.sqlite

import ai.unihelper.knowledge.ChunkLoc
import ai.unihelper.knowledge.KbChunk
import ai.unihelper.knowledge.KbDocument
import ai.unihelper.knowledge.KnowledgeStore
import ai.unihelper.knowledge.VectorRecord
import ai.unihelper.knowledge.VectorStore
import ai.unihelper.knowledge.cosine
import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * KB 自带索引库（独立 db 文件，非 local_db）——平台内置 SQLite。
 *
 * 个人 KB 规模小（通常 < 10 万切块）：向量存 BLOB + 暴力余弦，**无需 sqlite-vec 扩展**。
 * 真源仍是 md 文库；本库是派生索引，删了可 `KnowledgeEngine.reindexFromVault()` 重建。
 *
 * 用法（agents_server 或 UI 注入进引擎）：
 * ```kotlin
 * val idx = SqliteKnowledgeIndex(context)
 * val kb  = KnowledgeEngine(vaultPath, store = idx.store, vectors = idx.vectors /*, embedder = OnnxEmbedding(...) */)
 * ```
 */
class KnowledgeDb(context: Context, name: String = "unihelper_kb.db") :
    SQLiteOpenHelper(context.applicationContext, name, null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE documents(id TEXT PRIMARY KEY, source_id TEXT, user_id TEXT, " +
                "title TEXT, created_at INTEGER)"
        )
        db.execSQL(
            "CREATE TABLE chunks(id TEXT PRIMARY KEY, document_id TEXT, user_id TEXT, ordinal INTEGER, " +
                "text TEXT, loc_start INTEGER, loc_end INTEGER, heading TEXT)"
        )
        db.execSQL("CREATE INDEX idx_chunks_doc ON chunks(document_id)")
        db.execSQL("CREATE INDEX idx_chunks_user ON chunks(user_id)")
        db.execSQL(
            "CREATE TABLE embeddings(chunk_id TEXT PRIMARY KEY, document_id TEXT, user_id TEXT, " +
                "dim INTEGER, vec BLOB)"
        )
        db.execSQL("CREATE INDEX idx_emb_user ON embeddings(user_id)")
        // 可选优化：CREATE VIRTUAL TABLE chunks_fts USING fts4(text)；本版关键词走 allChunks + tokenize
    }

    override fun onUpgrade(db: SQLiteDatabase, oldV: Int, newV: Int) {
        db.execSQL("DROP TABLE IF EXISTS documents")
        db.execSQL("DROP TABLE IF EXISTS chunks")
        db.execSQL("DROP TABLE IF EXISTS embeddings")
        onCreate(db)
    }
}

/** 一次性拿到基于同一 db 的两个端口实现，注入 KnowledgeEngine。 */
class SqliteKnowledgeIndex(context: Context, dbName: String = "unihelper_kb.db") {
    private val helper = KnowledgeDb(context, dbName)
    val store: KnowledgeStore = SqliteKnowledgeStore(helper)
    val vectors: VectorStore = SqliteVectorStore(helper)
}

internal fun vecToBlob(v: DoubleArray): ByteArray {
    val buf = ByteBuffer.allocate(v.size * 8).order(ByteOrder.LITTLE_ENDIAN)
    for (x in v) buf.putDouble(x)
    return buf.array()
}

internal fun blobToVec(b: ByteArray): DoubleArray {
    val buf = ByteBuffer.wrap(b).order(ByteOrder.LITTLE_ENDIAN)
    val out = DoubleArray(b.size / 8)
    for (i in out.indices) out[i] = buf.double
    return out
}

class SqliteKnowledgeStore(private val helper: KnowledgeDb) : KnowledgeStore {
    override fun putDocument(doc: KbDocument) {
        val cv = ContentValues().apply {
            put("id", doc.id); put("source_id", doc.sourceId); put("user_id", doc.userId)
            put("title", doc.title); put("created_at", doc.createdAt)
        }
        helper.writableDatabase.insertWithOnConflict("documents", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
    }

    override fun putChunks(chunks: List<KbChunk>) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            for (c in chunks) {
                val cv = ContentValues().apply {
                    put("id", c.id); put("document_id", c.documentId); put("user_id", c.userId)
                    put("ordinal", c.ordinal); put("text", c.text)
                    put("loc_start", c.loc.start); put("loc_end", c.loc.end); put("heading", c.loc.heading)
                }
                db.insertWithOnConflict("chunks", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun getChunk(id: String): KbChunk? =
        helper.readableDatabase.query(
            "chunks", CHUNK_COLS, "id = ?", arrayOf(id), null, null, null
        ).use { if (it.moveToFirst()) readChunk(it) else null }

    override fun getDocument(id: String): KbDocument? =
        helper.readableDatabase.query(
            "documents", DOC_COLS, "id = ?", arrayOf(id), null, null, null
        ).use { if (it.moveToFirst()) readDoc(it) else null }

    override fun allChunks(userId: String?): List<KbChunk> {
        val sel = if (userId != null) "user_id = ?" else null
        val args = if (userId != null) arrayOf(userId) else null
        return helper.readableDatabase.query("chunks", CHUNK_COLS, sel, args, null, null, null).use { c ->
            val out = ArrayList<KbChunk>(c.count)
            while (c.moveToNext()) out.add(readChunk(c))
            out
        }
    }

    override fun deleteDocument(documentId: String) {
        val db = helper.writableDatabase
        db.delete("chunks", "document_id = ?", arrayOf(documentId))
        db.delete("documents", "id = ?", arrayOf(documentId))
    }

    override fun clearIndex() {
        val db = helper.writableDatabase
        db.delete("chunks", null, null)
        db.delete("documents", null, null)
    }

    private fun readChunk(c: android.database.Cursor) = KbChunk(
        id = c.getString(0),
        documentId = c.getString(1),
        userId = c.getString(2),
        ordinal = c.getInt(3),
        text = c.getString(4),
        loc = ChunkLoc(c.getInt(5), c.getInt(6), if (c.isNull(7)) null else c.getString(7)),
    )

    private fun readDoc(c: android.database.Cursor) = KbDocument(
        id = c.getString(0),
        sourceId = c.getString(1),
        userId = c.getString(2),
        title = if (c.isNull(3)) null else c.getString(3),
        createdAt = c.getLong(4),
    )

    companion object {
        private val CHUNK_COLS = arrayOf("id", "document_id", "user_id", "ordinal", "text", "loc_start", "loc_end", "heading")
        private val DOC_COLS = arrayOf("id", "source_id", "user_id", "title", "created_at")
    }
}

class SqliteVectorStore(private val helper: KnowledgeDb) : VectorStore {
    override fun upsert(records: List<VectorRecord>) {
        val db = helper.writableDatabase
        db.beginTransaction()
        try {
            for (r in records) {
                val cv = ContentValues().apply {
                    put("chunk_id", r.chunkId); put("document_id", r.documentId)
                    put("user_id", r.userId); put("dim", r.vector.size); put("vec", vecToBlob(r.vector))
                }
                db.insertWithOnConflict("embeddings", null, cv, SQLiteDatabase.CONFLICT_REPLACE)
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun search(query: DoubleArray, k: Int, userId: String?): List<Pair<String, Double>> {
        val sel = if (userId != null) "user_id = ?" else null
        val args = if (userId != null) arrayOf(userId) else null
        return helper.readableDatabase.query(
            "embeddings", arrayOf("chunk_id", "vec"), sel, args, null, null, null
        ).use { c ->
            val hits = ArrayList<Pair<String, Double>>(c.count)
            while (c.moveToNext()) {
                hits.add(c.getString(0) to cosine(query, blobToVec(c.getBlob(1))))
            }
            hits.sortedByDescending { it.second }.take(k)
        }
    }

    override fun deleteByDocument(documentId: String) {
        helper.writableDatabase.delete("embeddings", "document_id = ?", arrayOf(documentId))
    }

    override fun clear() {
        helper.writableDatabase.delete("embeddings", null, null)
    }

    override fun count(): Int =
        helper.readableDatabase.rawQuery("SELECT COUNT(*) FROM embeddings", null).use {
            if (it.moveToFirst()) it.getInt(0) else 0
        }
}
