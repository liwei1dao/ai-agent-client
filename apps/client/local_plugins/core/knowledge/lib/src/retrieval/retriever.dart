/// 混合检索：向量(语义) + 关键词(词重叠近似) → RRF 融合。
library;

import '../models.dart';
import '../ports.dart';
import '../text/tokenizer.dart';

class Retriever {
  final VectorStore vectors;
  final KnowledgeStore store;
  final EmbeddingProvider embedder;

  /// RRF 常数（越大越弱化排名靠前的权重差异）。
  final int rrfK;

  const Retriever({
    required this.vectors,
    required this.store,
    required this.embedder,
    this.rrfK = 60,
  });

  Future<List<ScoredChunk>> retrieve(String query,
      {int k = 6, String? userId}) async {
    final qvec = await embedder.embed(query);
    final vHits = await vectors.search(qvec, k: k * 3, userId: userId);
    final kHits = await _keyword(query, k: k * 3, userId: userId);

    // Reciprocal Rank Fusion
    final fused = <String, double>{};
    void fuse(List<String> ids) {
      for (var i = 0; i < ids.length; i++) {
        fused[ids[i]] = (fused[ids[i]] ?? 0) + 1.0 / (rrfK + i + 1);
      }
    }

    fuse([for (final h in vHits) h.chunkId]);
    fuse(kHits);

    final ordered = fused.keys.toList()
      ..sort((a, b) => fused[b]!.compareTo(fused[a]!));

    final out = <ScoredChunk>[];
    for (final id in ordered.take(k)) {
      final c = await store.getChunk(id);
      if (c == null) continue;
      final doc = await store.getDocument(c.documentId);
      out.add(ScoredChunk(
        chunk: c,
        score: fused[id]!,
        citation: Citation(
          documentId: c.documentId,
          documentTitle: doc?.title,
          loc: c.loc,
        ),
      ));
    }
    return out;
  }

  Future<List<String>> _keyword(String query,
      {int k = 18, String? userId}) async {
    final qTokens = tokenize(query).toSet();
    if (qTokens.isEmpty) return const [];
    final scored = <({String id, double s})>[];
    for (final c in await store.allChunks(userId: userId)) {
      final toks = tokenize(c.text);
      if (toks.isEmpty) continue;
      var hit = 0;
      for (final t in toks) {
        if (qTokens.contains(t)) hit++;
      }
      if (hit > 0) scored.add((id: c.id, s: hit / toks.length));
    }
    scored.sort((a, b) => b.s.compareTo(a.s));
    return [for (final e in scored.take(k)) e.id];
  }
}
