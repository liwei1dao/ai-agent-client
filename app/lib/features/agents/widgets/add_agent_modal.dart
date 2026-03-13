import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/agent_list_provider.dart';

class AddAgentModal extends ConsumerStatefulWidget {
  const AddAgentModal({super.key});

  @override
  ConsumerState<AddAgentModal> createState() => _AddAgentModalState();
}

class _AddAgentModalState extends ConsumerState<AddAgentModal> {
  final _nameController = TextEditingController();
  String _type = 'chat';
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('新建 Agent', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Agent 名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Text('类型', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'chat', label: Text('对话'), icon: Icon(Icons.chat_bubble_outline)),
              ButtonSegment(value: 'translate', label: Text('翻译'), icon: Icon(Icons.translate)),
            ],
            selected: {_type},
            onSelectionChanged: (v) => setState(() => _type = v.first),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('创建'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    await ref.read(agentListProvider.notifier).addAgent(
          name: name,
          type: _type,
          config: {},
        );
    if (mounted) Navigator.of(context).pop();
  }
}
