/// 轻量分词：ASCII 词 + 中文单字/相邻双字(bigram)。供关键词检索与哈希嵌入共用。
library;

List<String> tokenize(String input) {
  final tokens = <String>[];
  final buf = StringBuffer();
  int? prevCjk;
  void flush() {
    if (buf.isNotEmpty) {
      tokens.add(buf.toString());
      buf.clear();
    }
  }

  for (final c in input.toLowerCase().runes) {
    final isAsciiAlnum =
        (c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x7a);
    final isCjk = c >= 0x4e00 && c <= 0x9fff;
    if (isAsciiAlnum) {
      buf.writeCharCode(c);
      prevCjk = null;
    } else if (isCjk) {
      flush();
      final ch = String.fromCharCode(c);
      tokens.add(ch); // 单字
      if (prevCjk != null) {
        tokens.add('${String.fromCharCode(prevCjk)}$ch'); // 相邻双字
      }
      prevCjk = c;
    } else {
      flush();
      prevCjk = null;
    }
  }
  flush();
  return tokens;
}

/// 确定性 32-bit FNV-1a 哈希（跨运行稳定，用于特征哈希嵌入）。
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}
