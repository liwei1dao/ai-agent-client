package ai.unihelper.knowledge.embedding

/**
 * BERT WordPiece 分词（bge-small-zh / multilingual-e5 等均用 BERT 分词）。
 *
 * vocab 从模型附带的 `vocab.txt` 读入（行号即 token id）。处理流程与 HF BertTokenizer 对齐：
 *   可选小写 → 基础切分（空白/标点独立、中文按单字）→ WordPiece 贪心最长匹配（`##` 续接）。
 *
 * ⚠️ 逻辑真实、可单测；但需模型自带的 vocab.txt。未接模型时用 [HashingEmbedding] 兜底。
 */
class WordPieceTokenizer(
    private val vocab: Map<String, Int>,
    private val maxLen: Int = 256,
    private val doLowerCase: Boolean = true,
    cls: String = "[CLS]",
    sep: String = "[SEP]",
    unk: String = "[UNK]",
) {
    private val clsId = vocab[cls] ?: 101
    private val sepId = vocab[sep] ?: 102
    private val unkId = vocab[unk] ?: 100

    companion object {
        /** 从 vocab.txt 文本（每行一个 token）构建 token→id 映射。 */
        fun fromVocabText(text: String): Map<String, Int> {
            val m = HashMap<String, Int>()
            text.split("\n").forEachIndexed { i, line ->
                val t = line.trimEnd('\r')
                if (t.isNotEmpty()) m[t] = i
            }
            return m
        }
    }

    /** 返回 (inputIds, attentionMask)，含 [CLS]/[SEP]，截断至 maxLen。 */
    fun encode(text: String): Pair<LongArray, LongArray> {
        val ids = ArrayList<Long>()
        ids.add(clsId.toLong())
        outer@ for (word in basicTokenize(text)) {
            for (sub in wordpiece(word)) {
                if (ids.size >= maxLen - 1) break@outer  // 预留 [SEP]
                ids.add((vocab[sub] ?: unkId).toLong())
            }
        }
        ids.add(sepId.toLong())
        val arr = ids.toLongArray()
        return arr to LongArray(arr.size) { 1L }
    }

    private fun basicTokenize(text: String): List<String> {
        val s = if (doLowerCase) text.lowercase() else text
        val out = ArrayList<String>()
        val buf = StringBuilder()
        fun flush() { if (buf.isNotEmpty()) { out.add(buf.toString()); buf.setLength(0) } }
        for (c in s) {
            val isCjk = c.code in 0x4E00..0x9FFF
            when {
                c.isWhitespace() -> flush()
                isCjk -> { flush(); out.add(c.toString()) }             // 中文单字独立
                !c.isLetterOrDigit() -> { flush(); out.add(c.toString()) } // 标点独立
                else -> buf.append(c)
            }
        }
        flush()
        return out
    }

    /** 单个词的 WordPiece 贪心最长匹配；整词无法切分则回退 [UNK]（BERT 行为）。 */
    private fun wordpiece(word: String): List<String> {
        if (word.isEmpty()) return emptyList()
        if (vocab.containsKey(word)) return listOf(word)  // 中文单字/短词常直接命中
        val out = ArrayList<String>()
        var start = 0
        while (start < word.length) {
            var end = word.length
            var cur: String? = null
            while (start < end) {
                val piece = if (start > 0) "##${word.substring(start, end)}" else word.substring(start, end)
                if (vocab.containsKey(piece)) { cur = piece; break }
                end--
            }
            if (cur == null) return listOf("[UNK]")
            out.add(cur)
            start = end
        }
        return out
    }
}
