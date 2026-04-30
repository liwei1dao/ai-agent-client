import 'translate_event.dart';

/// 字幕聚合器：按 [requestId] 把 source 与 translated 配对到同一行字幕。
///
/// 输出 [lines] 是**跨 role 的全局时间线**——uplink 与 downlink 的 finalized 行
/// 按到达顺序混合排列，UI 可直接当作聊天列表渲染（role==user 右侧，role==peer 左侧）。
/// 每个 role 各自维护一个 in-progress 的 partial 源文（[partialSourceFor]），
/// 用于显示"对方正在说话"的临时气泡。
class SubtitleAggregator {
  /// 每个 role 当前正在识别但还没拿到 requestId 的源文。
  final Map<SubtitleRole, String?> _partialSource = {};

  /// 已捕获到 requestId 的字幕行（跨 role）。
  final Map<String, _Line> _lines = {};

  /// 行的展示顺序（首次见到 requestId 时入列）。
  final List<String> _order = [];

  void feed(TranslateSubtitleEvent e) {
    final reqId = e.requestId;

    if (e.stage == SubtitleStage.partial) {
      if (reqId == null) {
        // STT partial：覆盖该 role 的 in-progress 源文
        _partialSource[e.role] = e.sourceText;
      } else {
        // LLM partial：更新对应行的 partial 译文
        final line = _lines[reqId];
        if (line != null) {
          line.partialTranslated = e.translatedText ?? '';
        }
      }
      return;
    }

    // finalized：必带 requestId
    if (reqId == null) return;
    var line = _lines[reqId];
    if (line == null) {
      line = _Line(requestId: reqId, role: e.role);
      _lines[reqId] = line;
      _order.add(reqId);
    }
    if (e.sourceText.isNotEmpty) {
      line.source = e.sourceText;
      line.sourceFinalized = true;
      // 源文定稿，清空对应 role 的 partial source
      _partialSource[e.role] = null;
    }
    if (e.translatedText != null && e.translatedText!.isNotEmpty) {
      line.translated = e.translatedText;
      line.translatedFinalized = true;
      line.partialTranslated = null;
    }
  }

  /// 跨 role 的字幕时间线（按 requestId 首次到达顺序）。
  List<SubtitleLine> get lines => [
        for (final id in _order)
          () {
            final l = _lines[id]!;
            return SubtitleLine(
              requestId: id,
              role: l.role,
              source: l.source,
              translated: l.translated ?? l.partialTranslated,
              translatedPartial: !l.translatedFinalized &&
                  (l.partialTranslated?.isNotEmpty ?? false),
            );
          }(),
      ];

  /// 该 role 当前正在识别还没定稿的源文。
  String? partialSourceFor(SubtitleRole role) => _partialSource[role];

  bool get isEmpty =>
      _order.isEmpty &&
      _partialSource.values.every((v) => v == null || v.isEmpty);

  void reset() {
    _partialSource.clear();
    _lines.clear();
    _order.clear();
  }
}

class _Line {
  _Line({required this.requestId, required this.role});
  final String requestId;
  final SubtitleRole role;
  String source = '';
  String? translated;
  String? partialTranslated;
  bool sourceFinalized = false;
  bool translatedFinalized = false;
}

/// 一行字幕（一个 [TranslateSubtitleEvent.requestId] 对应一行）。
class SubtitleLine {
  const SubtitleLine({
    required this.requestId,
    required this.role,
    required this.source,
    required this.translated,
    required this.translatedPartial,
  });

  final String requestId;
  final SubtitleRole role;
  final String source;
  final String? translated;

  /// 译文是否仍在流式状态（partial）。
  final bool translatedPartial;
}
