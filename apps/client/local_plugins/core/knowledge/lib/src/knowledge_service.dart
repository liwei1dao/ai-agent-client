/// 本地用户级知识库服务（业务服务门面）。
library;

import 'chunker.dart';
import 'models.dart';
import 'ports.dart';
import 'retrieval/retriever.dart';
import 'vault/note_vault.dart';

/// 确定性 id：时间(微秒) + 递增计数，base36。测试可传显式 id。
class _IdGen {
  int _c = 0;
  String next(String prefix) {
    final t = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-${t.toRadixString(36)}-${(_c++).toRadixString(36)}';
  }
}

/// 真源 = [NoteVault]（md 文库）；派生索引 = [KnowledgeStore] + [VectorStore]。
///
/// 对管家/专员暴露 [retrieve] / [answerContext]；入库 [ingestMarkdown] 先写 md
/// 文库（真源）再建索引；[reindexFromVault] 可从真源整库重建。
class KnowledgeService {
  final NoteVault vault;
  final KnowledgeStore store;
  final VectorStore vectors;
  final EmbeddingProvider embedder;
  final Chunker chunker;
  final Retriever _retriever;
  final _ids = _IdGen();

  KnowledgeService({
    required this.vault,
    required this.store,
    required this.vectors,
    required this.embedder,
    Chunker? chunker,
    Retriever? retriever,
  })  : chunker = chunker ?? const Chunker(),
        _retriever = retriever ??
            Retriever(vectors: vectors, store: store, embedder: embedder);

  /// 入库一段 markdown：写 md 文库(真源) + 建索引。返回文档。
  Future<KbDocument> ingestMarkdown({
    required String userId,
    required String title,
    required String markdown,
    KbSourceKind kind = KbSourceKind.note,
    String? sourceUri,
    String? id,
  }) async {
    final docId = id ?? _ids.next('doc');
    final now = DateTime.now().millisecondsSinceEpoch;

    // 1) 真源：写 md 文库
    await vault.put(VaultNote(
      id: docId,
      frontmatter: {
        'id': docId,
        'title': title,
        'userId': userId,
        'kind': kind.name,
        if (sourceUri != null) 'uri': sourceUri,
        'createdAt': '$now',
      },
      body: markdown,
    ));

    // 2) 派生索引
    final source = KbSource(
      id: _ids.next('src'),
      userId: userId,
      kind: kind,
      title: title,
      uri: sourceUri,
      mime: 'text/markdown',
      createdAt: now,
    );
    final doc = KbDocument(
      id: docId,
      sourceId: source.id,
      userId: userId,
      title: title,
      createdAt: now,
    );
    await store.putSource(source);
    await store.putDocument(doc);
    await _indexDocument(doc, markdown);
    return doc;
  }

  /// 入库纯文本（包成 markdown）。
  Future<KbDocument> ingestText({
    required String userId,
    required String title,
    required String text,
    KbSourceKind kind = KbSourceKind.note,
    String? sourceUri,
    String? id,
  }) =>
      ingestMarkdown(
        userId: userId,
        title: title,
        markdown: text,
        kind: kind,
        sourceUri: sourceUri,
        id: id,
      );

  /// 检索：混合(向量 + 关键词) → 带引用命中。
  Future<List<ScoredChunk>> retrieve(String query,
          {int k = 6, String? userId}) =>
      _retriever.retrieve(query, k: k, userId: userId);

  /// 供 LLM/管家：检索 + 组装带引用上下文（答案生成由调用方完成）。
  Future<KbAnswerContext> answerContext(String query,
      {int k = 6, String? userId}) async {
    final hits = await retrieve(query, k: k, userId: userId);
    return KbAnswerContext(query: query, hits: hits);
  }

  /// 删除一个文档（真源 md + 派生索引）。
  Future<void> deleteDocument(String docId) async {
    await vault.delete(docId);
    await vectors.deleteByDocument(docId);
    await store.deleteDocument(docId);
  }

  /// 从 md 文库整库重建索引（证明"索引派生自真源、可重建"）。返回重建文档数。
  Future<int> reindexFromVault({String? userId}) async {
    await store.clearIndex();
    await vectors.clear();
    var n = 0;
    for (final id in await vault.listIds()) {
      final note = await vault.read(id);
      if (note == null) continue;
      final uid = note.frontmatter['userId'] ?? 'default';
      if (userId != null && uid != userId) continue;
      final createdAt = int.tryParse(note.frontmatter['createdAt'] ?? '') ?? 0;
      final source = KbSource(
        id: 'src-$id',
        userId: uid,
        kind: _kindOf(note.frontmatter['kind']),
        title: note.frontmatter['title'],
        uri: note.frontmatter['uri'],
        mime: 'text/markdown',
        createdAt: createdAt,
      );
      final doc = KbDocument(
        id: id,
        sourceId: source.id,
        userId: uid,
        title: note.frontmatter['title'],
        createdAt: createdAt,
      );
      await store.putSource(source);
      await store.putDocument(doc);
      await _indexDocument(doc, note.body);
      n++;
    }
    return n;
  }

  Future<void> _indexDocument(KbDocument doc, String markdown) async {
    final pieces = chunker.chunk(markdown);
    final chunks = <KbChunk>[
      for (var i = 0; i < pieces.length; i++)
        KbChunk(
          id: '${doc.id}#$i',
          documentId: doc.id,
          userId: doc.userId,
          ordinal: i,
          text: pieces[i].text,
          loc: pieces[i].loc,
        ),
    ];
    await store.putChunks(chunks);
    final vecs = await embedder.embedBatch([for (final c in chunks) c.text]);
    await vectors.upsert([
      for (var i = 0; i < chunks.length; i++)
        VectorRecord(
          chunkId: chunks[i].id,
          documentId: doc.id,
          userId: doc.userId,
          vector: vecs[i],
        ),
    ]);
  }

  KbSourceKind _kindOf(String? s) => KbSourceKind.values
      .firstWhere((e) => e.name == s, orElse: () => KbSourceKind.note);
}
