import 'translate_event.dart';

/// 字幕聚合器：按 §3.1 STT 文本约束（partial = 累计快照覆盖 / final = 累加）
/// 对外提供"已确认 + 当前句"的视图，方便 UI 直接显示。
///
/// 用法：
/// ```dart
/// final agg = SubtitleAggregator();
/// session.subtitles.listen(agg.feed);
/// // build:
/// final view = agg.viewOf(SubtitleRole.user);
/// final all = view.committed.join('\n') +
///             (view.currentSource == null ? '' : '\n${view.currentSource}');
/// ```
class SubtitleAggregator {
  final Map<SubtitleRole, _RoleState> _state = {};

  void feed(TranslateSubtitleEvent e) {
    final s = _state.putIfAbsent(e.role, _RoleState.new);
    if (e.stage == SubtitleStage.partial) {
      s.currentSource = e.sourceText;
      s.currentTranslated = e.translatedText;
    } else {
      // finalized
      if (e.sourceText.isNotEmpty) s.committedSource.add(e.sourceText);
      if (e.translatedText != null && e.translatedText!.isNotEmpty) {
        s.committedTranslated.add(e.translatedText!);
      }
      s.currentSource = null;
      s.currentTranslated = null;
    }
  }

  SubtitleView viewOf(SubtitleRole role) {
    final s = _state[role];
    if (s == null) return const SubtitleView.empty();
    return SubtitleView(
      committedSource: List.unmodifiable(s.committedSource),
      committedTranslated: List.unmodifiable(s.committedTranslated),
      currentSource: s.currentSource,
      currentTranslated: s.currentTranslated,
    );
  }

  void reset([SubtitleRole? role]) {
    if (role == null) {
      _state.clear();
    } else {
      _state.remove(role);
    }
  }
}

class _RoleState {
  final List<String> committedSource = [];
  final List<String> committedTranslated = [];
  String? currentSource;
  String? currentTranslated;
}

class SubtitleView {
  const SubtitleView({
    required this.committedSource,
    required this.committedTranslated,
    required this.currentSource,
    required this.currentTranslated,
  });

  const SubtitleView.empty()
      : committedSource = const [],
        committedTranslated = const [],
        currentSource = null,
        currentTranslated = null;

  final List<String> committedSource;
  final List<String> committedTranslated;
  final String? currentSource;
  final String? currentTranslated;

  bool get isEmpty =>
      committedSource.isEmpty &&
      committedTranslated.isEmpty &&
      (currentSource == null || currentSource!.isEmpty) &&
      (currentTranslated == null || currentTranslated!.isEmpty);
}
