/// UniHelper 本地用户级知识库服务（core/knowledge）。
///
/// - 真源：markdown 文库（[NoteVault] / [FileSystemVault]）
/// - 派生索引：[KnowledgeStore] + [VectorStore]（默认内存实现，框架层可换 SQLite/sqlite-vec）
/// - 端上嵌入：[EmbeddingProvider]（默认 [HashingEmbedding]；平台层用 ONNX 本地模型替换）
/// - 门面：[KnowledgeService]（ingest / retrieve / answerContext / reindexFromVault）
library;

export 'src/models.dart';
export 'src/ports.dart';
export 'src/text/tokenizer.dart';
export 'src/chunker.dart';
export 'src/embedding/hashing_embedding.dart';
export 'src/vault/note_vault.dart';
export 'src/vault/file_system_vault.dart';
export 'src/store/in_memory_stores.dart';
export 'src/retrieval/retriever.dart';
export 'src/knowledge_service.dart';
