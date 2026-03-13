import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/service_library_provider.dart';

class AddServiceModal extends ConsumerStatefulWidget {
  const AddServiceModal({super.key});

  @override
  ConsumerState<AddServiceModal> createState() => _AddServiceModalState();
}

class _AddServiceModalState extends ConsumerState<AddServiceModal> {
  final _nameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _regionController = TextEditingController();
  String _type = 'llm';
  String _vendor = 'openai';
  bool _saving = false;

  static const _vendorsByType = {
    'stt': ['azure', 'aliyun', 'google', 'doubao'],
    'tts': ['azure', 'aliyun', 'google', 'doubao'],
    'llm': ['openai', 'coze'],
    'sts': ['doubao'],
    'translation': ['deepl', 'aliyun', 'google'],
  };

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _vendorsByType[_type] ?? [];
    if (!vendors.contains(_vendor)) _vendor = vendors.first;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('添加服务', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),

            // 类型选择
            Text('服务类型', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['stt', 'tts', 'llm', 'sts', 'translation'].map((t) {
                return ChoiceChip(
                  label: Text(t.toUpperCase()),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    _type = t;
                    _vendor = _vendorsByType[t]!.first;
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // 厂商选择
            Text('服务商', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: vendors.map((v) {
                return ChoiceChip(
                  label: Text(v),
                  selected: _vendor == v,
                  onSelected: (_) => setState(() => _vendor = v),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // 名称
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '名称（自定义标识）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // API Key
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            // Region（仅 Azure 类需要）
            if (_vendor == 'azure')
              Column(
                children: [
                  TextField(
                    controller: _regionController,
                    decoration: const InputDecoration(
                      labelText: 'Region（如 eastus）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _apiKeyController.text.trim().isEmpty) return;
    setState(() => _saving = true);

    await ref.read(serviceLibraryProvider.notifier).addService(
          type: _type,
          vendor: _vendor,
          name: name,
          config: {
            'apiKey': _apiKeyController.text.trim(),
            if (_regionController.text.trim().isNotEmpty)
              'region': _regionController.text.trim(),
          },
        );

    if (mounted) Navigator.of(context).pop();
  }
}
