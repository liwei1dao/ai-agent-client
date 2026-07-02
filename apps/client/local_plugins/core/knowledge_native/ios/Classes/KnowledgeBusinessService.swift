import Foundation

/// 知识库业务服务：把 KnowledgeEngine 接入 agents_server 团队（镜像 Kotlin 版）。
///
/// - 管家(Manager)：`contextFor()` 取带引用上下文，注入本轮系统提示（RAG）
/// - LLM 工具：`toolDescriptor()` / `invokeTool()` 暴露 MCP 工具 `kb.search`
///
/// 只依赖引擎自身 + Foundation。agents_server 按其 Manager 注入点与 MCP 工具表适配。
final class KnowledgeBusinessService {
    private let engine: KnowledgeEngine
    init(engine: KnowledgeEngine) { self.engine = engine }

    /// 管家每轮对话前调用：带引用上下文，注入系统提示；无命中返回 nil。
    func contextFor(query: String, userId: String? = nil, k: Int = 6) -> String? {
        let ctx = engine.answerContext(query, k: k, userId: userId)
        return ctx.isEmpty ? nil : ctx
    }

    /// MCP 工具描述（JSON）。
    func toolDescriptor() -> String {
        let schema: [String: Any] = [
            "name": "kb.search",
            "description": "在用户本地知识库中检索相关内容，返回带来源的片段。用于回答涉及用户文档/笔记/资料/记忆的问题。",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "检索关键词或问题"],
                    "k": ["type": "integer", "description": "返回条数，默认 6"],
                ],
                "required": ["query"],
            ],
        ]
        return jsonString(schema)
    }

    /// LLM 触发 kb.search 时转调；argsJson 为入参，返回结果 JSON。
    func invokeTool(argsJson: String, userId: String? = nil) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argsJson.utf8))) as? [String: Any] ?? [:]
        let query = args["query"] as? String ?? ""
        let k = args["k"] as? Int ?? 6
        let hits = engine.retrieve(query, k: k, userId: userId).map { h in
            [
                "documentId": h.chunk.documentId,
                "title": h.documentTitle ?? h.chunk.documentId,
                "text": h.chunk.text,
                "score": h.score,
            ] as [String: Any]
        }
        return jsonString(["hits": hits])
    }

    private func jsonString(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}
