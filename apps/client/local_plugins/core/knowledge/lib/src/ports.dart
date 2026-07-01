/// 端口（接口）：框架层/平台层用这些契约替换默认实现，业务不变。
library;

import 'models.dart';

/// 嵌入运行时端口。默认端上本地实现；平台层用 ONNX 本地模型（bge-small-zh/e5-small）替换。
abstract interface class EmbeddingProvider {
  String get model;
  int get dim;
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
}

class VectorRecord {
  final String chunkId;
  final String documentId;
  final String userId;
  final List<double> vector;
  const VectorRecord({
    required this.chunkId,
    required this.documentId,
    required this.userId,
    required this.vector,
  });
}

class VectorHit {
  final String chunkId;
  final double score; // 余弦相似度
  const VectorHit(this.chunkId, this.score);
}

/// 向量存储端口。默认内存/暴力实现；框架层可换 sqlite-vec / LanceDB / ObjectBox(HNSW)。
abstract interface class VectorStore {
  Future<void> upsert(List<VectorRecord> records);
  Future<List<VectorHit>> search(List<double> query, {int k = 8, String? userId});
  Future<void> deleteByDocument(String documentId);
  Future<void> clear();
  Future<int> count();
}

/// 索引元数据存储端口（派生自 md 文库，可重建）。默认内存；框架层换 SQLite(local_db)+FTS5。
abstract interface class KnowledgeStore {
  Future<void> putSource(KbSource source);
  Future<void> putDocument(KbDocument doc);
  Future<void> putChunks(List<KbChunk> chunks);
  Future<KbChunk?> getChunk(String id);
  Future<KbDocument?> getDocument(String id);
  Future<List<KbChunk>> chunksOfDocument(String documentId);
  Future<List<KbChunk>> allChunks({String? userId});
  Future<void> deleteDocument(String documentId);
  Future<void> clearIndex();
}

class ParseInput {
  final String? text;
  final List<int>? bytes;
  final String? path;
  final String mime;
  const ParseInput({this.text, this.bytes, this.path, required this.mime});
}

/// 解析端口：把各类源转成 markdown。核心内置 text/markdown；PDF/OCR 由平台实现。
abstract interface class DocumentParser {
  bool supports(String mime);
  Future<String> toMarkdown(ParseInput input);
}
