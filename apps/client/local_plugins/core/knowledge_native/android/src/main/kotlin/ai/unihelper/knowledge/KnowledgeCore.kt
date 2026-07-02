package ai.unihelper.knowledge

import kotlin.math.sqrt

/**
 * 知识库算法核心（Kotlin）——忠实移植已验证的 Dart `core/knowledge`。
 *
 * 供纯原生 `agents_server` 在后台/设备唤醒场景直接调用（不经 Flutter）。
 * 默认实现零外部依赖（内存向量 + 特征哈希嵌入），可先跑通；
 * sqlite-vec / ONNX 端上嵌入以同名端口替换（见 [VectorStore] / [EmbeddingProvider]）。
 */

// ─────────────────────────── 分词 ───────────────────────────

/** ASCII 词 + 中文单字/相邻双字(bigram)。与 Dart tokenizer 一致。 */
fun tokenize(input: String): List<String> {
    val tokens = ArrayList<String>()
    val buf = StringBuilder()
    var prevCjk: Char? = null
    fun flush() {
        if (buf.isNotEmpty()) {
            tokens.add(buf.toString()); buf.setLength(0)
        }
    }
    for (c in input.lowercase()) {
        val cp = c.code
        val isAsciiAlnum = (cp in 0x30..0x39) || (cp in 0x61..0x7a)
        val isCjk = cp in 0x4E00..0x9FFF
        when {
            isAsciiAlnum -> { buf.append(c); prevCjk = null }
            isCjk -> {
                flush()
                tokens.add(c.toString())
                val p = prevCjk
                if (p != null) tokens.add("$p$c")
                prevCjk = c
            }
            else -> { flush(); prevCjk = null }
        }
    }
    flush()
    return tokens
}

/** 确定性 32-bit FNV-1a（跨运行稳定）。 */
fun fnv1a(s: String): Long {
    var h = 0x811c9dc5L
    for (ch in s) {
        h = h xor ch.code.toLong()
        h = (h * 0x01000193L) and 0xffffffffL
    }
    return h
}

// ─────────────────────────── 模型 ───────────────────────────

data class ChunkLoc(val start: Int, val end: Int, val heading: String?)

data class KbChunk(
    val id: String,
    val documentId: String,
    val userId: String,
    val ordinal: Int,
    val text: String,
    val loc: ChunkLoc,
)

data class KbDocument(
    val id: String,
    val sourceId: String,
    val userId: String,
    val title: String?,
    val createdAt: Long,
)

data class ScoredChunk(val chunk: KbChunk, val score: Double, val documentTitle: String?)

// ─────────────────────────── 端口 ───────────────────────────

interface EmbeddingProvider {
    val model: String
    val dim: Int
    fun embed(text: String): DoubleArray
    fun embedBatch(texts: List<String>): List<DoubleArray> = texts.map { embed(it) }
}

data class VectorRecord(
    val chunkId: String,
    val documentId: String,
    val userId: String,
    val vector: DoubleArray,
)

interface VectorStore {
    fun upsert(records: List<VectorRecord>)
    /** 返回 (chunkId, 余弦相似度) 降序 topK。 */
    fun search(query: DoubleArray, k: Int = 8, userId: String? = null): List<Pair<String, Double>>
    fun deleteByDocument(documentId: String)
    fun clear()
    fun count(): Int
}

interface KnowledgeStore {
    fun putDocument(doc: KbDocument)
    fun putChunks(chunks: List<KbChunk>)
    fun getChunk(id: String): KbChunk?
    fun getDocument(id: String): KbDocument?
    fun allChunks(userId: String? = null): List<KbChunk>
    fun deleteDocument(documentId: String)
    fun clearIndex()
}

// ─────────────────────── 端上哈希嵌入（默认/离线） ───────────────────────

/** 平台层可用 ONNX 本地模型（bge-small-zh/e5-small）实现同一端口替换。 */
class HashingEmbedding(override val dim: Int = 256) : EmbeddingProvider {
    override val model: String get() = "hashing-v1-$dim"
    override fun embed(text: String): DoubleArray {
        val v = DoubleArray(dim)
        for (tok in tokenize(text)) {
            val h = fnv1a(tok)
            val idx = (h % dim).toInt()
            val sign = if ((fnv1a("#$tok") and 1L) == 0L) 1.0 else -1.0
            v[idx] += sign
        }
        var norm = 0.0
        for (x in v) norm += x * x
        norm = sqrt(norm)
        if (norm > 0) for (i in v.indices) v[i] /= norm
        return v
    }
}

// ─────────────────────────── 切块 ───────────────────────────

class Chunker(private val maxChars: Int = 800, private val overlap: Int = 120) {
    private val headingRe = Regex("^#{1,6}\\s")
    private val leadHashRe = Regex("^#+\\s*")
    private val paraSplit = Regex("\\n\\s*\\n")

    fun chunk(markdown: String): List<Pair<String, ChunkLoc>> {
        val out = ArrayList<Pair<String, ChunkLoc>>()
        val paras = splitParagraphs(markdown)
        val buf = StringBuilder()
        var bufStart = 0
        var heading: String? = null
        fun flush(end: Int) {
            val t = buf.toString().trim()
            if (t.isNotEmpty()) out.add(t to ChunkLoc(bufStart, end, heading))
            buf.setLength(0)
        }
        for ((text, start) in paras) {
            if (headingRe.containsMatchIn(text)) {
                heading = text.replaceFirst(leadHashRe, "").trim()
            }
            if (buf.isNotEmpty() && buf.length + text.length > maxChars) {
                flush(start)
                val prev = if (out.isNotEmpty()) out.last().first else ""
                val tail = if (prev.length > overlap) prev.substring(prev.length - overlap) else prev
                buf.append(tail)
                bufStart = start
            }
            if (buf.isEmpty()) bufStart = start else buf.append("\n\n")
            buf.append(text)
        }
        flush(markdown.length)
        return out
    }

    private fun splitParagraphs(md: String): List<Pair<String, Int>> {
        val res = ArrayList<Pair<String, Int>>()
        var cursor = 0
        for (raw in md.split(paraSplit)) {
            val idx = md.indexOf(raw, cursor)
            val start = if (idx == -1) cursor else idx
            val t = raw.trim()
            if (t.isNotEmpty()) res.add(t to start)
            cursor = start + raw.length
        }
        return res
    }
}

// ─────────────────────── 内存存储（默认实现） ───────────────────────

class InMemoryVectorStore : VectorStore {
    private val byChunk = LinkedHashMap<String, VectorRecord>()
    override fun upsert(records: List<VectorRecord>) {
        for (r in records) byChunk[r.chunkId] = r
    }
    override fun search(query: DoubleArray, k: Int, userId: String?): List<Pair<String, Double>> =
        byChunk.values
            .filter { userId == null || it.userId == userId }
            .map { it.chunkId to cosine(query, it.vector) }
            .sortedByDescending { it.second }
            .take(k)
    override fun deleteByDocument(documentId: String) {
        byChunk.values.removeAll { it.documentId == documentId }
    }
    override fun clear() = byChunk.clear()
    override fun count(): Int = byChunk.size
}

class InMemoryKnowledgeStore : KnowledgeStore {
    private val docs = LinkedHashMap<String, KbDocument>()
    private val chunks = LinkedHashMap<String, KbChunk>()
    override fun putDocument(doc: KbDocument) { docs[doc.id] = doc }
    override fun putChunks(chunkList: List<KbChunk>) { for (c in chunkList) chunks[c.id] = c }
    override fun getChunk(id: String): KbChunk? = chunks[id]
    override fun getDocument(id: String): KbDocument? = docs[id]
    override fun allChunks(userId: String?): List<KbChunk> =
        chunks.values.filter { userId == null || it.userId == userId }
    override fun deleteDocument(documentId: String) {
        docs.remove(documentId)
        chunks.values.removeAll { it.documentId == documentId }
    }
    override fun clearIndex() { docs.clear(); chunks.clear() }
}

internal fun cosine(a: DoubleArray, b: DoubleArray): Double {
    val n = minOf(a.size, b.size)
    var dot = 0.0; var na = 0.0; var nb = 0.0
    for (i in 0 until n) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
    if (na == 0.0 || nb == 0.0) return 0.0
    return dot / (sqrt(na) * sqrt(nb))
}

// ─────────────────────── 混合检索（向量 + 关键词 RRF） ───────────────────────

class Retriever(
    private val vectors: VectorStore,
    private val store: KnowledgeStore,
    private val embedder: EmbeddingProvider,
    private val rrfK: Int = 60,
) {
    fun retrieve(query: String, k: Int = 6, userId: String? = null): List<ScoredChunk> {
        val qvec = embedder.embed(query)
        val vHits = vectors.search(qvec, k * 3, userId).map { it.first }
        val kHits = keyword(query, k * 3, userId)

        val fused = LinkedHashMap<String, Double>()
        fun fuse(ids: List<String>) {
            for (i in ids.indices) fused[ids[i]] = (fused[ids[i]] ?: 0.0) + 1.0 / (rrfK + i + 1)
        }
        fuse(vHits); fuse(kHits)

        return fused.entries
            .sortedByDescending { it.value }
            .take(k)
            .mapNotNull { e ->
                val c = store.getChunk(e.key) ?: return@mapNotNull null
                val doc = store.getDocument(c.documentId)
                ScoredChunk(c, e.value, doc?.title)
            }
    }

    private fun keyword(query: String, k: Int, userId: String?): List<String> {
        val qTokens = tokenize(query).toHashSet()
        if (qTokens.isEmpty()) return emptyList()
        return store.allChunks(userId)
            .mapNotNull { c ->
                val toks = tokenize(c.text)
                if (toks.isEmpty()) return@mapNotNull null
                val hit = toks.count { it in qTokens }
                if (hit > 0) c.id to hit.toDouble() / toks.size else null
            }
            .sortedByDescending { it.second }
            .take(k)
            .map { it.first }
    }
}
