import 'assistant_event.dart';

/// 消息聚合器：按 [requestId] 把 user 提问与 assistant 回复配对到同一行对话。
///
/// 输出 [lines] 是按 requestId 首次出现顺序排列的对话时间线，
/// UI 可直接当作聊天列表渲染（user 右侧气泡 + assistant 左侧气泡）。
/// 用户当前正在说但尚未定稿的源文，可用 [partialUserText] 取出显示"正在听写"状态。
class AssistantMessageAggregator {
  /// 用户当前正在识别但还没拿到 requestId 的源文（STT in-progress）。
  String? _partialUserText;

  /// 已捕获到 requestId 的对话行。
  final Map<String, _Line> _lines = {};

  /// 行的展示顺序（首次见到 requestId 时入列）。
  final List<String> _order = [];

  void feed(AssistantMessageEvent e) {
    final reqId = e.requestId;

    if (e.stage == AssistantMessageStage.partial) {
      if (e.role == AssistantRole.user) {
        // STT partial：覆盖 in-progress 用户源文
        _partialUserText = e.text;
      } else {
        // assistant partial：更新对应行的 partial 回复
        if (reqId == null) return;
        final line = _ensureLine(reqId);
        line.partialAssistant = e.text;
      }
      return;
    }

    // finalized：必带 requestId
    if (reqId == null) return;
    final line = _ensureLine(reqId);
    if (e.role == AssistantRole.user && e.text.isNotEmpty) {
      line.userText = e.text;
      line.userFinalized = true;
      // 用户句定稿，清空 in-progress
      _partialUserText = null;
    }
    if (e.role == AssistantRole.assistant && e.text.isNotEmpty) {
      line.assistantText = e.text;
      line.assistantFinalized = true;
      line.partialAssistant = null;
    }
  }

  _Line _ensureLine(String reqId) {
    var line = _lines[reqId];
    if (line == null) {
      line = _Line(requestId: reqId);
      _lines[reqId] = line;
      _order.add(reqId);
    }
    return line;
  }

  /// 完整对话时间线（按 requestId 首次到达顺序）。
  List<AssistantConversationLine> get lines => [
        for (final id in _order)
          () {
            final l = _lines[id]!;
            return AssistantConversationLine(
              requestId: id,
              userText: l.userText,
              assistantText: l.assistantText ?? l.partialAssistant,
              assistantPartial: !l.assistantFinalized &&
                  (l.partialAssistant?.isNotEmpty ?? false),
            );
          }(),
      ];

  /// 用户当前正在识别但还没定稿的源文（适合显示"正在说话…"气泡）。
  String? get partialUserText => _partialUserText;

  bool get isEmpty =>
      _order.isEmpty && (_partialUserText == null || _partialUserText!.isEmpty);

  void reset() {
    _partialUserText = null;
    _lines.clear();
    _order.clear();
  }
}

class _Line {
  _Line({required this.requestId});
  final String requestId;
  String userText = '';
  String? assistantText;
  String? partialAssistant;
  bool userFinalized = false;
  bool assistantFinalized = false;
}

/// 一行对话（一个 [AssistantMessageEvent.requestId] 对应一行：user 提问 + assistant 回复）。
class AssistantConversationLine {
  const AssistantConversationLine({
    required this.requestId,
    required this.userText,
    required this.assistantText,
    required this.assistantPartial,
  });

  final String requestId;
  final String userText;
  final String? assistantText;

  /// AI 回复是否仍在流式状态（partial）。
  final bool assistantPartial;
}
