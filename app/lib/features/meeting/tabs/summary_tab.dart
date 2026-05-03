import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/meeting.dart';
import '../models/meeting_detail.dart';
import '../providers/meeting_providers.dart';

class SummaryTab extends ConsumerStatefulWidget {
  const SummaryTab({super.key, required this.meeting, required this.detail});
  final Meeting meeting;
  final MeetingDetail detail;

  @override
  ConsumerState<SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<SummaryTab> {
  late final TextEditingController _summary;
  late final TextEditingController _address;
  late final TextEditingController _personnel;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _summary = TextEditingController(text: widget.detail.summary);
    _address = TextEditingController(text: widget.detail.address);
    _personnel = TextEditingController(text: widget.detail.personnel);
  }

  @override
  void didUpdateWidget(covariant SummaryTab old) {
    super.didUpdateWidget(old);
    if (old.detail.meetingId != widget.detail.meetingId && !_editing) {
      _summary.text = widget.detail.summary;
      _address.text = widget.detail.address;
      _personnel.text = widget.detail.personnel;
    }
  }

  @override
  void dispose() {
    _summary.dispose();
    _address.dispose();
    _personnel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = widget.detail.copyWith(
      summary: _summary.text,
      address: _address.text.trim(),
      personnel: _personnel.text.trim(),
    );
    await ref.read(meetingRepositoryProvider).writeDetail(next);
    ref.invalidate(meetingDetailProvider(widget.meeting.id));
    setState(() => _editing = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      children: [
        _MetaRow(
          icon: Icons.location_on_outlined,
          label: '地点',
          controller: _address,
          editing: _editing,
          colors: colors,
        ),
        const SizedBox(height: 8),
        _MetaRow(
          icon: Icons.group_outlined,
          label: '与会人员',
          controller: _personnel,
          editing: _editing,
          colors: colors,
        ),
        Divider(height: 24, color: colors.border),
        Row(
          children: [
            Text(
              '会议纪要',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.text1,
              ),
            ),
            const Spacer(),
            if (_editing)
              TextButton(
                onPressed: () => setState(() {
                  _editing = false;
                  _summary.text = widget.detail.summary;
                  _address.text = widget.detail.address;
                  _personnel.text = widget.detail.personnel;
                }),
                child: const Text('取消'),
              ),
            TextButton(
              onPressed: () {
                if (_editing) {
                  _save();
                } else {
                  setState(() => _editing = true);
                }
              },
              child: Text(_editing ? '保存' : '编辑'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_editing)
          TextField(
            controller: _summary,
            maxLines: null,
            minLines: 8,
            decoration: const InputDecoration(
              hintText: '请输入会议纪要（支持 Markdown 占位）',
            ),
          )
        else if (widget.detail.summary.isEmpty)
          _emptyHint(colors)
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              widget.detail.summary,
              style: TextStyle(
                color: colors.text1,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        const SizedBox(height: 16),
        if (!_editing)
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AI 生成纪要 — Round 5 接入后端')),
              );
            },
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: const Text('AI 生成纪要'),
          ),
      ],
    );
  }

  Widget _emptyHint(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(Icons.edit_note,
              color: colors.text2.withValues(alpha: 0.6), size: 36),
          const SizedBox(height: 8),
          Text('暂无纪要',
              style: TextStyle(color: colors.text1, fontSize: 14)),
          const SizedBox(height: 4),
          Text('点击右上角"编辑"手动输入，或点击下方"AI 生成"',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.text2, fontSize: 12)),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.controller,
    required this.editing,
    required this.colors,
  });
  final IconData icon;
  final String label;
  final TextEditingController controller;
  final bool editing;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colors.text2, size: 18),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text('$label：',
              style: TextStyle(color: colors.text2, fontSize: 13)),
        ),
        Expanded(
          child: editing
              ? TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                  style: TextStyle(color: colors.text1, fontSize: 13),
                )
              : Text(
                  controller.text.isEmpty ? '—' : controller.text,
                  style: TextStyle(color: colors.text1, fontSize: 13),
                ),
        ),
      ],
    );
  }
}
