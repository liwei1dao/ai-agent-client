/// 把 markdown 正文切成带定位的块。
library;

import 'models.dart';

/// 按段落聚合到 [maxChars]，块间 [overlap] 字符重叠，记录最近标题作为上下文。
class Chunker {
  final int maxChars;
  final int overlap;
  const Chunker({this.maxChars = 800, this.overlap = 120});

  List<({String text, ChunkLoc loc})> chunk(String markdown) {
    final out = <({String text, ChunkLoc loc})>[];
    final paras = _splitParagraphs(markdown);
    final buf = StringBuffer();
    var bufStart = 0;
    String? heading;

    void flush(int end) {
      final text = buf.toString().trim();
      if (text.isNotEmpty) {
        out.add((
          text: text,
          loc: ChunkLoc(start: bufStart, end: end, heading: heading),
        ));
      }
      buf.clear();
    }

    for (final p in paras) {
      if (_isHeading(p.text)) {
        heading = p.text.replaceAll(RegExp(r'^#+\s*'), '').trim();
      }
      if (buf.isNotEmpty && buf.length + p.text.length > maxChars) {
        flush(p.start);
        final prev = out.isNotEmpty ? out.last.text : '';
        final tail =
            prev.length > overlap ? prev.substring(prev.length - overlap) : prev;
        buf.write(tail);
        bufStart = p.start;
      }
      if (buf.isEmpty) {
        bufStart = p.start;
      } else {
        buf.write('\n\n');
      }
      buf.write(p.text);
    }
    flush(markdown.length);
    return out;
  }

  bool _isHeading(String s) => RegExp(r'^#{1,6}\s').hasMatch(s);

  List<({String text, int start})> _splitParagraphs(String md) {
    final res = <({String text, int start})>[];
    var cursor = 0;
    for (final raw in md.split(RegExp(r'\n\s*\n'))) {
      final idx = md.indexOf(raw, cursor);
      final start = idx == -1 ? cursor : idx;
      final t = raw.trim();
      if (t.isNotEmpty) res.add((text: t, start: start));
      cursor = start + raw.length;
    }
    return res;
  }
}
