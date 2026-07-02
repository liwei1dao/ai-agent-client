// 底层知识库服务自检（端到端，零外部依赖）。
// 运行：dart run example/self_check.dart
import 'dart:io';

import 'package:knowledge/knowledge.dart';

void check(bool cond, String msg) {
  if (!cond) {
    stderr.writeln('✗ FAIL: $msg');
    exit(1);
  }
  stdout.writeln('  ✓ $msg');
}

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('uh_kb_');
  final vault = FileSystemVault(dir.path);
  final store = InMemoryKnowledgeStore();
  final vectors = InMemoryVectorStore();
  final kb = KnowledgeService(
    vault: vault,
    store: store,
    vectors: vectors,
    embedder: const HashingEmbedding(),
  );

  stdout.writeln('▶ 入库三条不同主题笔记（写入 md 文库真源 + 建索引）');
  final bt = await kb.ingestMarkdown(
    userId: 'u1',
    title: '连接蓝牙耳机',
    markdown:
        '# 如何连接 UniHelper 蓝牙耳机\n长按电源键三秒进入配对模式，在设备扫描界面点击连接即可。',
  );
  await kb.ingestMarkdown(
    userId: 'u1',
    title: '合同会议纪要',
    markdown: '# 会议纪要\n周二和张总讨论了合同条款三的付款节点，需本周确认。',
  );
  await kb.ingestMarkdown(
    userId: 'u1',
    title: '本月消费',
    markdown: '# 本月财务\n餐饮支出 2300 元，购物 3200 元，已超预算。',
  );

  check(await vectors.count() >= 3, '向量索引已建立（${await vectors.count()} 块）');

  final mdFiles = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.md'))
      .toList();
  check(mdFiles.length == 3, 'md 文库落盘 3 个 .md 文件（真源）');

  stdout.writeln('▶ 混合检索（向量 + 关键词 RRF）');
  final r1 = await kb.retrieve('蓝牙耳机怎么配对连接', userId: 'u1');
  check(r1.isNotEmpty, '检索有结果');
  check(r1.first.citation.documentId == bt.id,
      '“蓝牙耳机怎么配对连接” → Top1《${r1.first.citation.documentTitle}》');

  final r2 = await kb.retrieve('合同付款节点', userId: 'u1');
  check(r2.first.citation.documentTitle == '合同会议纪要',
      '“合同付款节点” → Top1《${r2.first.citation.documentTitle}》');

  final r3 = await kb.retrieve('餐饮花了多少钱', userId: 'u1');
  check(r3.first.citation.documentTitle == '本月消费',
      '“餐饮花了多少钱” → Top1《${r3.first.citation.documentTitle}》');

  stdout.writeln('▶ answerContext（带引用上下文，供 LLM/管家）');
  final ctx = await kb.answerContext('蓝牙耳机怎么连', userId: 'u1');
  check(ctx.toPromptContext().contains('蓝牙'), '生成带引用上下文');
  check(ctx.toPromptContext().contains('[1]'), '含引用标号 [1]');

  stdout.writeln('▶ 用户级隔离');
  final r4 = await kb.retrieve('蓝牙', userId: 'u2');
  check(r4.isEmpty, 'u2 检索不到 u1 的知识');

  stdout.writeln('▶ 从 md 文库重建索引（索引派生自真源、可重建）');
  await vectors.clear();
  await store.clearIndex();
  check(await vectors.count() == 0, '索引已清空');
  final n = await kb.reindexFromVault();
  check(n == 3, '从 md 文库重建 $n 个文档');
  final r5 = await kb.retrieve('蓝牙耳机怎么配对连接', userId: 'u1');
  check(r5.first.citation.documentId == bt.id, '重建后检索仍正确');

  stdout.writeln('▶ 删除');
  await kb.deleteDocument(bt.id);
  check(!await vault.exists(bt.id), '真源 md 已删');
  final r6 = await kb.retrieve('蓝牙耳机怎么配对连接', userId: 'u1');
  check(r6.every((h) => h.citation.documentId != bt.id), '索引里已无该文档');

  dir.deleteSync(recursive: true);
  stdout.writeln(
      '\n✅ 全部通过：md文库真源 + 派生索引 + 端上嵌入 + 混合检索 + 用户隔离 + 可重建 + 增删。');
}
