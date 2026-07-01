/// 领域模型：知识源 / 文档 / 切块 / 检索结果。
library;

enum KbSourceKind { file, note, web, chat, life }

enum KbStatus { importing, ready, failed }

/// 一次导入 = 一个知识源。
class KbSource {
  final String id;
  final String userId;
  final KbSourceKind kind;
  final String? title;
  final String? uri;
  final String? mime;
  KbStatus status;
  final int createdAt;

  KbSource({
    required this.id,
    required this.userId,
    required this.kind,
    this.title,
    this.uri,
    this.mime,
    this.status = KbStatus.ready,
    required this.createdAt,
  });
}

/// 解析后的逻辑文档（与 md 文库里的一份 note 对应）。
class KbDocument {
  final String id;
  final String sourceId;
  final String userId;
  final String? title;
  final Map<String, String> meta;
  final int createdAt;

  KbDocument({
    required this.id,
    required this.sourceId,
    required this.userId,
    this.title,
    Map<String, String>? meta,
    required this.createdAt,
  }) : meta = meta ?? const {};
}

/// 切块在原文里的定位（用于引用溯源）。
class ChunkLoc {
  final int start;
  final int end;
  final String? heading;
  const ChunkLoc({required this.start, required this.end, this.heading});
  Map<String, Object?> toJson() =>
      {'start': start, 'end': end, 'heading': heading};
}

/// 切块（索引与检索的基本单位）。
class KbChunk {
  final String id;
  final String documentId;
  final String userId;
  final int ordinal;
  final String text;
  final ChunkLoc loc;
  KbChunk({
    required this.id,
    required this.documentId,
    required this.userId,
    required this.ordinal,
    required this.text,
    required this.loc,
  });
}

/// 引用溯源信息。
class Citation {
  final String documentId;
  final String? documentTitle;
  final ChunkLoc loc;
  const Citation({
    required this.documentId,
    this.documentTitle,
    required this.loc,
  });
}

/// 一条检索命中：切块 + 融合分数 + 引用。
class ScoredChunk {
  final KbChunk chunk;
  final double score;
  final Citation citation;
  const ScoredChunk({
    required this.chunk,
    required this.score,
    required this.citation,
  });
}

/// answerContext 返回：可直接拼进 LLM 提示的带引用上下文（答案生成由调用方/管家完成）。
class KbAnswerContext {
  final String query;
  final List<ScoredChunk> hits;
  const KbAnswerContext({required this.query, required this.hits});

  bool get isEmpty => hits.isEmpty;

  /// 拼成给 LLM 的上下文（每段带 [n] 引用标号 + 来源标题）。
  String toPromptContext() {
    final b = StringBuffer();
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      final title = h.citation.documentTitle ?? h.chunk.documentId;
      b.writeln('[${i + 1}] 《$title》');
      b.writeln(h.chunk.text.trim());
      b.writeln();
    }
    return b.toString().trimRight();
  }
}
