import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/themes/app_theme.dart';
import '../models/template.dart';
import '../providers/meeting_providers.dart';

/// 模板社区主页 — builtin + 用户自定义。
class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(meetingTemplatesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建模板',
            onPressed: () => context.push('/meeting/templates/edit/new'),
          ),
        ],
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final t = list[i];
            return _TemplateTile(template: t);
          },
        ),
      ),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template});
  final MeetingTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return InkWell(
      onTap: () => context.push('/meeting/templates/${template.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_iconFor(template.icon),
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          template.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.text1),
                        ),
                      ),
                      if (template.builtin)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '内置',
                            style: TextStyle(
                                color: AppTheme.primary, fontSize: 10),
                          ),
                        ),
                    ],
                  ),
                  if (template.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      template.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.text2),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.text2),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String key) => switch (key) {
        'group' => Icons.group_outlined,
        'person_search' => Icons.person_search_outlined,
        'lightbulb' => Icons.lightbulb_outline,
        _ => Icons.description_outlined,
      };
}

/// 模板详情页 — 只读展示。用户模板可编辑/删除。
class TemplateDetailScreen extends ConsumerWidget {
  const TemplateDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(meetingTemplatesProvider);
    return asyncList.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          Scaffold(body: Center(child: Text('加载失败：$e'))),
      data: (list) {
        final t = list.firstWhere(
          (e) => e.id == id,
          orElse: () => const MeetingTemplate(
              id: '', name: '未找到模板', description: '', prompt: ''),
        );
        if (t.id.isEmpty) {
          return const Scaffold(body: Center(child: Text('模板不存在')));
        }
        final colors = context.appColors;
        return Scaffold(
          appBar: AppBar(
            title: Text(t.name),
            actions: [
              if (!t.builtin) ...[
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () =>
                      context.push('/meeting/templates/edit/${t.id}'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.danger),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('删除模板？'),
                        content: const Text('删除后无法恢复'),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, false),
                              child: const Text('取消')),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(ctx, true),
                            child: const Text('删除',
                                style:
                                    TextStyle(color: AppTheme.danger)),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await ref
                        .read(meetingRepositoryProvider)
                        .deleteTemplate(t.id);
                    ref.invalidate(meetingTemplatesProvider);
                    if (context.mounted) context.pop();
                  },
                ),
              ],
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(t.description,
                  style: TextStyle(fontSize: 13, color: colors.text2)),
              const SizedBox(height: 16),
              Text('提示词',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.text2)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  t.prompt,
                  style: TextStyle(
                      color: colors.text1, fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 模板编辑页 — 新建（id == 'new'）或编辑既有用户模板。
class TemplateEditScreen extends ConsumerStatefulWidget {
  const TemplateEditScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<TemplateEditScreen> createState() =>
      _TemplateEditScreenState();
}

class _TemplateEditScreenState extends ConsumerState<TemplateEditScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _prompt = TextEditingController();
  bool _initialized = false;
  String? _id;

  bool get _isNew => widget.id == 'new';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入模板名称')));
      return;
    }
    final id = _id ?? const Uuid().v4();
    final t = MeetingTemplate(
      id: id,
      name: _name.text.trim(),
      description: _desc.text.trim(),
      prompt: _prompt.text.trim(),
    );
    await ref.read(meetingRepositoryProvider).upsertTemplate(t);
    ref.invalidate(meetingTemplatesProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(meetingTemplatesProvider);
    if (!_initialized) {
      asyncList.whenData((list) {
        if (!_isNew) {
          final t = list.firstWhere(
            (e) => e.id == widget.id,
            orElse: () => const MeetingTemplate(
                id: '', name: '', description: '', prompt: ''),
          );
          if (t.id.isNotEmpty) {
            _name.text = t.name;
            _desc.text = t.description;
            _prompt.text = t.prompt;
            _id = t.id;
          }
        }
        _initialized = true;
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建模板' : '编辑模板'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            decoration: const InputDecoration(labelText: '简介'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prompt,
            decoration: const InputDecoration(
              labelText: '提示词',
              hintText: '请将这段会议转写整理成…',
              alignLabelWithHint: true,
            ),
            minLines: 6,
            maxLines: null,
          ),
        ],
      ),
    );
  }
}
