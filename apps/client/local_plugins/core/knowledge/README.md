# knowledge — UniHelper 本地用户级知识库服务

`local_plugins/core/knowledge` · 纯 Dart · 核心零外部依赖

**md 文库为真源 + 本地派生索引**的个人知识库服务（业务服务层），端上嵌入、混合检索、用户级隔离；对管家/专员暴露检索，供 RAG 使用。设计见 [`docs/UniHelper-knowledge.md`](../../../../../docs/UniHelper-knowledge.md)。

## 架构（端口驱动，框架/平台可替换实现）

```
KnowledgeService（业务服务门面）
  ├─ NoteVault        真源：md 文库   → FileSystemVault(落盘) / InMemoryVault
  ├─ Chunker          markdown 切块（带标题上下文 + 溯源定位）
  ├─ EmbeddingProvider 端上嵌入        → HashingEmbedding(默认/离线)  ▶ 平台层换 ONNX(bge-small-zh/e5-small)
  ├─ VectorStore      向量索引         → InMemoryVectorStore(暴力余弦)  ▶ 框架层换 sqlite-vec/LanceDB/ObjectBox
  ├─ KnowledgeStore   元数据/切块索引  → InMemoryKnowledgeStore        ▶ 框架层换 SQLite(local_db)+FTS5
  └─ Retriever        混合检索（向量 + 关键词 → RRF 融合）
```

- **真源是 md 文件、索引是派生缓存**：`reindexFromVault()` 可从 md 文库整库重建索引（换嵌入模型/重装无损）。
- **端口即接线点**：换向量库/嵌入模型/解析器都只实现对应端口，`KnowledgeService` 与业务不变。

## 用法

```dart
final kb = KnowledgeService(
  vault: FileSystemVault('/path/to/vault'),   // 真源 md 文库
  store: InMemoryKnowledgeStore(),            // TODO 平台层换 SQLite(local_db)
  vectors: InMemoryVectorStore(),             // TODO 平台层换 sqlite-vec
  embedder: const HashingEmbedding(),         // TODO 平台层换 ONNX 本地模型
);

await kb.ingestMarkdown(userId: 'u1', title: '连接蓝牙耳机', markdown: '...');
final ctx = await kb.answerContext('蓝牙耳机怎么配对', userId: 'u1');
// ctx.toPromptContext() → 带 [n] 引用的上下文，交 LLM/管家生成答案
```

## 接线（后续）

- **端上嵌入**：新增 `knowledge_onnx`（或 vendors 下）实现 `EmbeddingProvider`，加载 ONNX 小模型。
- **本地索引**：新增 `knowledge_sqlite` 用 `local_db`(SQLite) + `sqlite-vec` + FTS5 实现 `VectorStore` + `KnowledgeStore`。
- **解析/OCR**：实现 `DocumentParser`（PDF/网页/图片→md），复用多模态 Vision/OCR Provider。
- **团队接入**：`agents_server` 里把 `KnowledgeService` 作为业务服务，对管家暴露 `retrieve()`、对 LLM 暴露 MCP 工具 `kb.search`。

## 自检

```bash
dart pub get
dart run example/self_check.dart
```

覆盖：真源落盘 → 派生索引 → 端上嵌入 → 混合检索(3 主题 Top1) → 带引用 → 用户隔离 → 从 md 重建 → 增删。
