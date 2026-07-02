import 'package:flutter/services.dart';

/// 一条检索命中（原生返回）。
class KbHit {
  final String chunkId;
  final String documentId;
  final String? documentTitle;
  final String text;
  final double score;
  final String? heading;

  KbHit({
    required this.chunkId,
    required this.documentId,
    required this.documentTitle,
    required this.text,
    required this.score,
    required this.heading,
  });

  factory KbHit.fromMap(Map<Object?, Object?> m) => KbHit(
        chunkId: m['chunkId'] as String? ?? '',
        documentId: m['documentId'] as String? ?? '',
        documentTitle: m['documentTitle'] as String?,
        text: m['text'] as String? ?? '',
        score: (m['score'] as num?)?.toDouble() ?? 0,
        heading: m['heading'] as String?,
      );
}

/// Flutter UI 侧调用原生知识库引擎（"我的→知识库"页）。
///
/// 后台/设备唤醒场景由纯原生 agents_server 直接调 KnowledgeEngine，不走本类。
class KnowledgeNative {
  static const MethodChannel _ch = MethodChannel('ai.unihelper/knowledge');

  static Future<String> ingestMarkdown({
    required String userId,
    required String title,
    required String markdown,
    String kind = 'note',
    String? sourceUri,
    String? id,
  }) async {
    final r = await _ch.invokeMethod<String>('ingestMarkdown', {
      'userId': userId,
      'title': title,
      'markdown': markdown,
      'kind': kind,
      'sourceUri': sourceUri,
      'id': id,
    });
    return r ?? '';
  }

  static Future<List<KbHit>> retrieve(String query,
      {int k = 6, String? userId}) async {
    final res = await _ch.invokeListMethod<Object?>('retrieve', {
      'query': query,
      'k': k,
      'userId': userId,
    });
    return (res ?? [])
        .map((e) => KbHit.fromMap((e as Map).cast<Object?, Object?>()))
        .toList();
  }

  static Future<String> answerContext(String query,
      {int k = 6, String? userId}) async {
    final r = await _ch.invokeMethod<String>('answerContext', {
      'query': query,
      'k': k,
      'userId': userId,
    });
    return r ?? '';
  }

  static Future<void> deleteDocument(String docId) =>
      _ch.invokeMethod<void>('deleteDocument', {'docId': docId});

  static Future<int> reindexFromVault({String? userId}) async {
    final r = await _ch.invokeMethod<int>('reindexFromVault', {'userId': userId});
    return r ?? 0;
  }
}
