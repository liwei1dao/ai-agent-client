package ai.unihelper.knowledge.embedding

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.sqrt

/** WordPiece 分词 + OnnxEmbedding 池化/归一逻辑单测（用假 OnnxSession，不需真模型）。 */
class OnnxEmbeddingTest {
    private val vocab = mapOf(
        "[PAD]" to 0, "[UNK]" to 100, "[CLS]" to 101, "[SEP]" to 102,
        "你" to 1000, "好" to 1001, "hello" to 2000, "##ing" to 2001, "test" to 2002,
    )

    @Test
    fun tokenizerBasics() {
        val tk = WordPieceTokenizer(vocab)
        val (ids, mask) = tk.encode("你好 hello")
        assertEquals(101L, ids.first())            // [CLS]
        assertEquals(102L, ids.last())             // [SEP]
        assertEquals(ids.size, mask.size)
        assertTrue(mask.all { it == 1L })
        assertEquals(listOf(101L, 1000L, 1001L, 2000L, 102L), ids.toList())
    }

    @Test
    fun wordpieceSplitAndUnk() {
        val tk = WordPieceTokenizer(vocab)
        // "testing" → test + ##ing
        assertEquals(listOf(101L, 2002L, 2001L, 102L), tk.encode("testing").first.toList())
        // 未登录词 → [UNK]
        assertEquals(listOf(101L, 100L, 102L), tk.encode("zzz").first.toList())
    }

    @Test
    fun poolingAndNormalize() {
        val tk = WordPieceTokenizer(vocab)
        // 假前向：每个位置全 1 的 4 维 → 池化后全 1 → L2 归一为 0.5/维
        val fake = object : OnnxSession {
            override fun run(inputIds: LongArray, attentionMask: LongArray): Array<FloatArray> =
                Array(inputIds.size) { floatArrayOf(1f, 1f, 1f, 1f) }
        }
        val v = OnnxEmbedding(tk, fake, dim = 4).embed("你好")
        assertEquals(4, v.size)
        assertTrue(abs(sqrt(v.sumOf { it * it }) - 1.0) < 1e-9)   // 归一
        assertTrue(v.all { abs(it - 0.5) < 1e-9 })
    }
}
