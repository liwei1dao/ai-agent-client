package ai.unihelper.knowledge.embedding

import ai.unihelper.knowledge.EmbeddingProvider
import kotlin.math.sqrt

/**
 * 端上 ONNX 句向量嵌入（bge-small-zh-v1.5 / multilingual-e5-small）。
 *
 * 本类实现**分词 + masked mean-pooling + L2 归一**的完整逻辑（真实、可单测）；
 * 唯一 env/依赖相关的"跑一次 ONNX 前向"抽象为 [OnnxSession]，由你的环境用 onnxruntime 实现
 * （模板见 README「ORT 接入」）。这样 knowledge_native 不被 onnxruntime 依赖绑死。
 *
 * 流程：WordPiece 分词 → input_ids/attention_mask → [OnnxSession.run] → last_hidden_state
 *       → 按 mask 平均池化 → L2 归一 → $dim 维。
 */
class OnnxEmbedding(
    private val tokenizer: WordPieceTokenizer,
    private val session: OnnxSession,
    override val dim: Int = 384,
    override val model: String = "bge-small-zh-v1.5",
) : EmbeddingProvider {
    override fun embed(text: String): DoubleArray {
        val (ids, mask) = tokenizer.encode(text)
        val hidden = session.run(ids, mask) // [seqLen][hidden]
        val pooled = DoubleArray(dim)
        var denom = 0.0
        for (i in hidden.indices) {
            if (i < mask.size && mask[i] == 0L) continue
            denom += 1.0
            val row = hidden[i]
            val n = minOf(dim, row.size)
            for (j in 0 until n) pooled[j] += row[j]
        }
        if (denom > 0) for (j in 0 until dim) pooled[j] /= denom
        var norm = 0.0
        for (x in pooled) norm += x * x
        norm = sqrt(norm)
        if (norm > 0) for (j in 0 until dim) pooled[j] /= norm
        return pooled
    }
}

/**
 * ONNX 前向端口：喂 input_ids/attention_mask，返回 last_hidden_state（[seqLen][hidden]）。
 *
 * 由 app 用 onnxruntime 实现（见 README 模板）。示意：
 * ```kotlin
 * class OrtSession(modelPath: String) : OnnxSession {
 *   private val env = OrtEnvironment.getEnvironment()
 *   private val sess = env.createSession(modelPath, OrtSession.SessionOptions())
 *   override fun run(ids: LongArray, mask: LongArray): Array<FloatArray> {
 *     val shape = longArrayOf(1, ids.size.toLong())
 *     val inputs = mapOf(
 *       "input_ids" to OnnxTensor.createTensor(env, arrayOf(ids), shape),      // 视模型输入名调整
 *       "attention_mask" to OnnxTensor.createTensor(env, arrayOf(mask), shape),
 *     )
 *     sess.run(inputs).use { r ->
 *       val out = (r[0].value as Array<Array<FloatArray>>)[0]  // [seq][hidden]
 *       return out
 *     }
 *   }
 * }
 * ```
 */
interface OnnxSession {
    fun run(inputIds: LongArray, attentionMask: LongArray): Array<FloatArray>
}
