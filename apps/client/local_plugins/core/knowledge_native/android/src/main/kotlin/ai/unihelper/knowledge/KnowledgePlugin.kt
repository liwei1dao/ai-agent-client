package ai.unihelper.knowledge

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Flutter UI 桥（供"我的→知识库"页读写）。
 *
 * 注意：**主用户是纯原生 agents_server**，它直接 `new KnowledgeEngine(...)` 调用，不经此桥。
 * 本桥仅服务 Flutter UI。默认用 [KnowledgeEngine] 的内存索引 + 哈希嵌入；生产可注入
 * sqlite-vec / ONNX 端口实现。可按项目惯例迁移为 Pigeon（此处用手写 MethodChannel 保持自包含）。
 */
class KnowledgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private var engine: KnowledgeEngine? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ai.unihelper/knowledge")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun engine(): KnowledgeEngine =
        engine ?: KnowledgeEngine(File(appContext.filesDir, "kb_vault").path).also { engine = it }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ingestMarkdown" -> result.success(
                    engine().ingestMarkdown(
                        userId = call.argument<String>("userId") ?: "default",
                        title = call.argument<String>("title") ?: "",
                        markdown = call.argument<String>("markdown") ?: "",
                        kind = call.argument<String>("kind") ?: "note",
                        sourceUri = call.argument<String>("sourceUri"),
                        id = call.argument<String>("id"),
                    )
                )
                "retrieve" -> result.success(
                    engine().retrieve(
                        query = call.argument<String>("query") ?: "",
                        k = call.argument<Int>("k") ?: 6,
                        userId = call.argument<String>("userId"),
                    ).map { h ->
                        mapOf(
                            "chunkId" to h.chunk.id,
                            "documentId" to h.chunk.documentId,
                            "documentTitle" to h.documentTitle,
                            "text" to h.chunk.text,
                            "score" to h.score,
                            "heading" to h.chunk.loc.heading,
                        )
                    }
                )
                "answerContext" -> result.success(
                    engine().answerContext(
                        query = call.argument<String>("query") ?: "",
                        k = call.argument<Int>("k") ?: 6,
                        userId = call.argument<String>("userId"),
                    )
                )
                "deleteDocument" -> {
                    engine().deleteDocument(call.argument<String>("docId") ?: "")
                    result.success(null)
                }
                "reindexFromVault" -> result.success(
                    engine().reindexFromVault(call.argument<String>("userId"))
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("kb_error", e.message, null)
        }
    }
}
