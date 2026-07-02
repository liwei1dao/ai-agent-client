package ai.unihelper.knowledge.service

import ai.unihelper.knowledge.KnowledgeEngine
import org.json.JSONArray
import org.json.JSONObject

/**
 * 知识库业务服务：把 [KnowledgeEngine] 接入 agents_server 团队（见 docs/UniHelper-agents-protocol.md）。
 *
 * 两个集成面：
 *  1) **管家(Manager)**：`contextFor()` 取相关知识的带引用上下文，在每轮对话前注入系统提示（RAG）。
 *  2) **LLM 工具**：`toolDescriptor()` / `invokeTool()` 暴露 MCP 工具 `kb.search`，让模型按需自检索。
 *
 * 只依赖 knowledge_native 自身 + org.json（Android 内置）。agents_server 按其
 * Manager 注入点与 MCP 工具表适配这两个方法即可（本类不感知具体框架类型）。
 *
 * ```kotlin
 * val kb = KnowledgeEngine(vaultPath, store = idx.store, vectors = idx.vectors)
 * val svc = KnowledgeBusinessService(kb)
 * // 管家：val sys = base + (svc.contextFor(userText, userId) ?: "")
 * // 工具表：registerTool(svc.toolDescriptor()) { args -> svc.invokeTool(args, userId) }
 * ```
 */
class KnowledgeBusinessService(private val engine: KnowledgeEngine) {

    /** 管家每轮对话前调用：相关知识的带引用上下文，注入系统提示；无命中返回 null。 */
    fun contextFor(query: String, userId: String? = null, k: Int = 6): String? =
        engine.answerContext(query, k, userId).ifBlank { null }

    /** MCP 工具描述（JSON）：agents_server 注册进工具表，供 LLM 调用。 */
    fun toolDescriptor(): String = JSONObject().apply {
        put("name", "kb.search")
        put(
            "description",
            "在用户本地知识库中检索相关内容，返回带来源的片段。用于回答涉及用户文档/笔记/资料/记忆的问题。"
        )
        put("inputSchema", JSONObject().apply {
            put("type", "object")
            put("properties", JSONObject().apply {
                put("query", JSONObject().apply {
                    put("type", "string"); put("description", "检索关键词或问题")
                })
                put("k", JSONObject().apply {
                    put("type", "integer"); put("description", "返回条数，默认 6")
                })
            })
            put("required", JSONArray().put("query"))
        })
    }.toString()

    /** LLM 触发 kb.search 时，agents_server 转调此方法；argsJson 为工具入参，返回结果 JSON。 */
    fun invokeTool(argsJson: String, userId: String? = null): String {
        val args = JSONObject(argsJson)
        val query = args.optString("query")
        val k = if (args.has("k")) args.getInt("k") else 6
        val arr = JSONArray()
        for (h in engine.retrieve(query, k, userId)) {
            arr.put(JSONObject().apply {
                put("documentId", h.chunk.documentId)
                put("title", h.documentTitle ?: h.chunk.documentId)
                put("text", h.chunk.text)
                put("score", h.score)
            })
        }
        return JSONObject().put("hits", arr).toString()
    }
}
