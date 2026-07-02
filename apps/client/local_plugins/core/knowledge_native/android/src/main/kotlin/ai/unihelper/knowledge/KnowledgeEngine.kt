package ai.unihelper.knowledge

import java.io.File

/**
 * md 文库（真源）：每条笔记一份 `<id>.md`，落盘于 [rootPath]。
 */
class MarkdownVault(private val rootPath: String) {
    data class Note(val id: String, val frontmatter: Map<String, String>, val body: String)

    private fun root(): File = File(rootPath).apply { if (!exists()) mkdirs() }
    private fun file(id: String): File = File(root(), "$id.md")

    fun put(note: Note) {
        val sb = StringBuilder()
        sb.append("---\n")
        for ((k, v) in note.frontmatter) sb.append("$k: ${v.replace("\n", " ")}\n")
        sb.append("---\n")
        sb.append(note.body)
        file(note.id).writeText(sb.toString())
    }

    fun read(id: String): Note? {
        val f = file(id)
        if (!f.exists()) return null
        return parse(id, f.readText())
    }

    fun listIds(): List<String> =
        root().listFiles()?.filter { it.isFile && it.name.endsWith(".md") }
            ?.map { it.name.removeSuffix(".md") }?.sorted() ?: emptyList()

    fun exists(id: String): Boolean = file(id).exists()

    fun delete(id: String) { file(id).let { if (it.exists()) it.delete() } }

    private fun parse(id: String, raw: String): Note {
        val fm = LinkedHashMap<String, String>()
        var body = raw
        if (raw.startsWith("---")) {
            val end = raw.indexOf("\n---", 3)
            if (end != -1) {
                for (line in raw.substring(3, end).trim().split("\n")) {
                    val i = line.indexOf(':')
                    if (i > 0) fm[line.substring(0, i).trim()] = line.substring(i + 1).trim()
                }
                val nl = raw.indexOf('\n', end + 1)
                body = if (nl == -1) "" else raw.substring(nl + 1)
            }
        }
        return Note(id, fm, body)
    }
}

/**
 * 本地用户级知识库服务（原生门面）。
 *
 * 纯原生 `agents_server` 直接实例化并调用（后台/设备唤醒场景，不经 Flutter）：
 * ```kotlin
 * val kb = KnowledgeEngine(context.filesDir.resolve("kb_vault").path)
 * kb.ingestMarkdown("u1", "连接蓝牙耳机", "...")
 * val ctx = kb.answerContext("蓝牙耳机怎么配对", userId = "u1")   // → 交 LLM 生成答案
 * ```
 * 默认零外部依赖（内存索引 + 特征哈希嵌入）；平台层可换 sqlite-vec / ONNX 端口实现。
 */
class KnowledgeEngine(
    vaultPath: String,
    private val embedder: EmbeddingProvider = HashingEmbedding(),
    private val store: KnowledgeStore = InMemoryKnowledgeStore(),
    private val vectors: VectorStore = InMemoryVectorStore(),
    private val chunker: Chunker = Chunker(),
) {
    private val vault = MarkdownVault(vaultPath)
    private val retriever = Retriever(vectors, store, embedder)
    private var counter = 0

    private fun nextId(prefix: String): String {
        val t = System.nanoTime()
        return "$prefix-${t.toString(36)}-${(counter++).toString(36)}"
    }

    /** 入库 markdown：写 md 文库(真源) + 建索引。返回 documentId。 */
    fun ingestMarkdown(
        userId: String,
        title: String,
        markdown: String,
        kind: String = "note",
        sourceUri: String? = null,
        id: String? = null,
    ): String {
        val docId = id ?: nextId("doc")
        val now = System.currentTimeMillis()
        val fm = linkedMapOf(
            "id" to docId, "title" to title, "userId" to userId,
            "kind" to kind, "createdAt" to now.toString(),
        )
        if (sourceUri != null) fm["uri"] = sourceUri
        vault.put(MarkdownVault.Note(docId, fm, markdown))
        val doc = KbDocument(docId, nextId("src"), userId, title, now)
        store.putDocument(doc)
        indexDocument(doc, markdown)
        return docId
    }

    /** 检索：混合(向量 + 关键词) → 带引用命中。 */
    fun retrieve(query: String, k: Int = 6, userId: String? = null): List<ScoredChunk> =
        retriever.retrieve(query, k, userId)

    /** 供 LLM/管家：检索 + 拼装带 [n] 引用的上下文（答案生成由调用方完成）。 */
    fun answerContext(query: String, k: Int = 6, userId: String? = null): String {
        val hits = retrieve(query, k, userId)
        val sb = StringBuilder()
        hits.forEachIndexed { i, h ->
            sb.append("[${i + 1}] 《${h.documentTitle ?: h.chunk.documentId}》\n")
            sb.append(h.chunk.text.trim()).append("\n\n")
        }
        return sb.toString().trimEnd()
    }

    fun deleteDocument(docId: String) {
        vault.delete(docId)
        vectors.deleteByDocument(docId)
        store.deleteDocument(docId)
    }

    /** 从 md 文库整库重建索引（证明索引派生自真源、可重建）。返回文档数。 */
    fun reindexFromVault(userId: String? = null): Int {
        store.clearIndex(); vectors.clear()
        var n = 0
        for (id in vault.listIds()) {
            val note = vault.read(id) ?: continue
            val uid = note.frontmatter["userId"] ?: "default"
            if (userId != null && uid != userId) continue
            val createdAt = note.frontmatter["createdAt"]?.toLongOrNull() ?: 0L
            val doc = KbDocument(id, "src-$id", uid, note.frontmatter["title"], createdAt)
            store.putDocument(doc)
            indexDocument(doc, note.body)
            n++
        }
        return n
    }

    fun vectorCount(): Int = vectors.count()

    private fun indexDocument(doc: KbDocument, markdown: String) {
        val pieces = chunker.chunk(markdown)
        val chunks = pieces.mapIndexed { i, (text, loc) ->
            KbChunk("${doc.id}#$i", doc.id, doc.userId, i, text, loc)
        }
        store.putChunks(chunks)
        val vecs = embedder.embedBatch(chunks.map { it.text })
        vectors.upsert(chunks.mapIndexed { i, c ->
            VectorRecord(c.id, doc.id, doc.userId, vecs[i])
        })
    }
}
