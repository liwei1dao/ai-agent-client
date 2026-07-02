/// 默认内存实现：向量存储（暴力余弦）+ 索引元数据存储。
///
/// 框架层可分别换成 sqlite-vec / LanceDB / ObjectBox（向量）与 SQLite+FTS5（元数据）。
library;

import 'dart:math';

import '../models.dart';
import '../ports.dart';

class InMemoryVectorStore implements VectorStore {
  final Map<String, VectorRecord> _byChunk = {};

  @override
  Future<void> upsert(List<VectorRecord> records) async {
    for (final r in records) {
      _byChunk[r.chunkId] = r;
    }
  }

  @override
  Future<List<VectorHit>> search(List<double> query,
      {int k = 8, String? userId}) async {
    final hits = <VectorHit>[];
    for (final r in _byChunk.values) {
      if (userId != null && r.userId != userId) continue;
      hits.add(VectorHit(r.chunkId, _cosine(query, r.vector)));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(k).toList();
  }

  @override
  Future<void> deleteByDocument(String documentId) async =>
      _byChunk.removeWhere((_, r) => r.documentId == documentId);

  @override
  Future<void> clear() async => _byChunk.clear();

  @override
  Future<int> count() async => _byChunk.length;
}

double _cosine(List<double> a, List<double> b) {
  final n = min(a.length, b.length);
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (sqrt(na) * sqrt(nb));
}

class InMemoryKnowledgeStore implements KnowledgeStore {
  final Map<String, KbSource> _sources = {};
  final Map<String, KbDocument> _docs = {};
  final Map<String, KbChunk> _chunks = {};

  @override
  Future<void> putSource(KbSource source) async => _sources[source.id] = source;

  @override
  Future<void> putDocument(KbDocument doc) async => _docs[doc.id] = doc;

  @override
  Future<void> putChunks(List<KbChunk> chunks) async {
    for (final c in chunks) {
      _chunks[c.id] = c;
    }
  }

  @override
  Future<KbChunk?> getChunk(String id) async => _chunks[id];

  @override
  Future<KbDocument?> getDocument(String id) async => _docs[id];

  @override
  Future<List<KbChunk>> chunksOfDocument(String documentId) async =>
      _chunks.values.where((c) => c.documentId == documentId).toList();

  @override
  Future<List<KbChunk>> allChunks({String? userId}) async =>
      _chunks.values.where((c) => userId == null || c.userId == userId).toList();

  @override
  Future<void> deleteDocument(String documentId) async {
    _docs.remove(documentId);
    _chunks.removeWhere((_, c) => c.documentId == documentId);
  }

  @override
  Future<void> clearIndex() async {
    _sources.clear();
    _docs.clear();
    _chunks.clear();
  }
}
