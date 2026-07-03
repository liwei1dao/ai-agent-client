import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../../core/services/log_service.dart';

/// 应用内日志面板：
/// - 实时订阅 [LogService.talker.stream]，新日志即时上屏；
/// - 支持按日志级别多选过滤（DEBUG / INFO / WARN / ERROR，含 verbose / critical 归并）；
/// - 关键字搜索；
/// - 暂停 / 继续刷新：暂停期间新日志进入缓冲区，按钮上显示缓冲计数，恢复时一次性追加；
/// - 复制当前可见日志、清空全部历史。
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  /// 内存中保留的最大条目，避免长时间运行后 OOM
  static const int _maxKeepEntries = 5000;

  /// 当前用于渲染的全部条目（含历史 + 实时新增，未做过滤）
  final List<TalkerData> _entries = [];

  /// 暂停期间缓冲新日志，恢复时一次性追加
  final List<TalkerData> _pausedBuffer = [];
  bool _paused = false;

  /// 启用的日志级别（多选）
  final Set<LogLevel> _enabledLevels = {
    LogLevel.verbose,
    LogLevel.debug,
    LogLevel.info,
    LogLevel.warning,
    LogLevel.error,
    LogLevel.critical,
  };

  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  bool _autoScroll = true;
  final ScrollController _scrollCtrl = ScrollController();

  StreamSubscription<TalkerData>? _sub;

  @override
  void initState() {
    super.initState();
    final talker = LogService.instance.talker;
    _entries.addAll(talker.history);
    _sub = talker.stream.listen(_onNewEntry);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── 事件处理 ────────────────────────────────────────────────────────────

  void _onNewEntry(TalkerData data) {
    if (!mounted) return;
    if (_paused) {
      // 仅刷新工具栏上的缓冲计数；列表保持不动
      setState(() => _pausedBuffer.add(data));
      return;
    }
    setState(() {
      _entries.add(data);
      _trim();
    });
    _scrollToEndIfNeeded();
  }

  void _trim() {
    if (_entries.length > _maxKeepEntries) {
      _entries.removeRange(0, _entries.length - _maxKeepEntries);
    }
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      if (!_paused && _pausedBuffer.isNotEmpty) {
        _entries.addAll(_pausedBuffer);
        _pausedBuffer.clear();
        _trim();
      }
    });
    _scrollToEndIfNeeded();
  }

  void _scrollToEndIfNeeded() {
    if (!_autoScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  bool _accept(TalkerData data) {
    final level = data.logLevel ?? LogLevel.info;
    if (!_enabledLevels.contains(level)) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final msg = (data.message ?? '').toLowerCase();
      final title = (data.title ?? '').toLowerCase();
      if (!msg.contains(q) && !title.contains(q)) return false;
    }
    return true;
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('确定要清空所有日志文件和内存历史吗？此操作不可恢复。',
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await LogService.instance.clear();
      if (!mounted) return;
      setState(() {
        _entries.clear();
        _pausedBuffer.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志已清空')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空失败: $e')),
      );
    }
  }

  Future<void> _copyVisible() async {
    final visible = _entries.where(_accept).toList();
    if (visible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前过滤条件下没有可复制的日志')),
      );
      return;
    }
    final text = visible.map((d) => d.generateTextMessage()).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${visible.length} 条日志')),
    );
  }

  // ─── 构建 UI ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _entries.where(_accept).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '日志 (${visible.length}/${_entries.length})',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all, size: 20),
            tooltip: '复制可见日志',
            onPressed: _copyVisible,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            tooltip: '清空全部',
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text('暂无日志',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  )
                : Scrollbar(
                    controller: _scrollCtrl,
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      itemCount: visible.length,
                      itemBuilder: (_, i) => _LogLine(data: visible[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        children: [
          // 第 1 行：搜索框
          SizedBox(
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索关键字（消息内容 / 标签）',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          // 第 2 行：级别过滤 + 暂停 + 自动滚动
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _LevelChip(
                  label: 'DEBUG',
                  selected: _enabledLevels.contains(LogLevel.debug),
                  color: const Color(0xFF94A3B8),
                  onChanged: (v) => _setLevel(
                    [LogLevel.debug, LogLevel.verbose],
                    v,
                  ),
                ),
                const SizedBox(width: 6),
                _LevelChip(
                  label: 'INFO',
                  selected: _enabledLevels.contains(LogLevel.info),
                  color: const Color(0xFF3B82F6),
                  onChanged: (v) => _setLevel([LogLevel.info], v),
                ),
                const SizedBox(width: 6),
                _LevelChip(
                  label: 'WARN',
                  selected: _enabledLevels.contains(LogLevel.warning),
                  color: const Color(0xFFF59E0B),
                  onChanged: (v) => _setLevel([LogLevel.warning], v),
                ),
                const SizedBox(width: 6),
                _LevelChip(
                  label: 'ERROR',
                  selected: _enabledLevels.contains(LogLevel.error),
                  color: const Color(0xFFEF4444),
                  onChanged: (v) => _setLevel(
                    [LogLevel.error, LogLevel.critical],
                    v,
                  ),
                ),
                const SizedBox(width: 14),
                Container(width: 1, color: Colors.grey.shade300),
                const SizedBox(width: 14),
                _PauseButton(
                  paused: _paused,
                  bufferCount: _pausedBuffer.length,
                  onTap: _togglePause,
                ),
                const SizedBox(width: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                        value: _autoScroll,
                        onChanged: (v) => setState(() => _autoScroll = v),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const Text('自动滚动', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setLevel(List<LogLevel> levels, bool enabled) {
    setState(() {
      if (enabled) {
        _enabledLevels.addAll(levels);
      } else {
        _enabledLevels.removeAll(levels);
      }
    });
  }
}

// ─── 子控件 ────────────────────────────────────────────────────────────────

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final bool selected;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: selected ? color : Colors.grey.shade600,
        ),
      ),
      selected: selected,
      onSelected: onChanged,
      showCheckmark: false,
      selectedColor: color.withOpacity(0.15),
      side: BorderSide(
        color: selected ? color : Colors.grey.shade300,
        width: 1,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.paused,
    required this.bufferCount,
    required this.onTap,
  });

  final bool paused;
  final int bufferCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = paused
        ? (bufferCount > 0 ? '继续 (+$bufferCount)' : '继续')
        : '暂停';
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(
        paused ? Icons.play_arrow : Icons.pause,
        size: 16,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        backgroundColor:
            paused ? const Color(0xFFFEF3C7) : null, // 暂停时高亮成琥珀色
        foregroundColor:
            paused ? const Color(0xFFB45309) : null,
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.data});
  final TalkerData data;

  static const Map<LogLevel, _LevelStyle> _styles = {
    LogLevel.error: _LevelStyle(label: 'ERROR', color: Color(0xFFEF4444)),
    LogLevel.critical: _LevelStyle(label: 'CRIT', color: Color(0xFFB91C1C)),
    LogLevel.warning: _LevelStyle(label: 'WARN', color: Color(0xFFF59E0B)),
    LogLevel.info: _LevelStyle(label: 'INFO', color: Color(0xFF3B82F6)),
    LogLevel.debug: _LevelStyle(label: 'DEBUG', color: Color(0xFF94A3B8)),
    LogLevel.verbose: _LevelStyle(label: 'VERB', color: Color(0xFFCBD5E1)),
  };

  @override
  Widget build(BuildContext context) {
    final level = data.logLevel ?? LogLevel.info;
    final style = _styles[level] ??
        const _LevelStyle(label: 'INFO', color: Color(0xFF3B82F6));
    final t = data.time;
    final ts =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
    final msg = data.message ?? data.title ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 6),
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: style.color,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: SelectableText.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$ts ',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                TextSpan(
                  text: '${style.label.padRight(5)} ',
                  style: TextStyle(
                    color: style.color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                TextSpan(
                  text: msg,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    height: 1.4,
                    color: level == LogLevel.error ||
                            level == LogLevel.critical
                        ? style.color
                        : null,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelStyle {
  const _LevelStyle({required this.label, required this.color});
  final String label;
  final Color color;
}
