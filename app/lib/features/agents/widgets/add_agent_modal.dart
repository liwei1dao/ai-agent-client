import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/agent_list_provider.dart';
import '../../services/providers/service_library_provider.dart';

class AddAgentModal extends ConsumerStatefulWidget {
  const AddAgentModal({super.key, this.agent});
  /// If non-null, open in edit mode for this agent.
  final AgentDto? agent;

  @override
  ConsumerState<AddAgentModal> createState() => _AddAgentModalState();
}

class _AddAgentModalState extends ConsumerState<AddAgentModal> {
  late final TextEditingController _nameCtrl;
  late String _type;

  // Selected service IDs
  String? _llmId;
  String? _sttId;
  String? _ttsId;
  String? _voiceName;
  String? _translationId;
  String? _stsId; // 端到端语音服务 (sts / ast)
  late final List<String> _mcpIds;

  // Chat config
  late final TextEditingController _promptCtrl;

  // Translate config
  late String _srcLang;
  late String _dstLang;

  bool get _isEditing => widget.agent != null;

  @override
  void initState() {
    super.initState();
    final a = widget.agent;
    if (a != null) {
      final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
      _nameCtrl = TextEditingController(text: a.name);
      _type = a.type;
      _llmId = cfg['llmServiceId'] as String?;
      _sttId = cfg['sttServiceId'] as String?;
      _ttsId = cfg['ttsServiceId'] as String?;
      _voiceName = cfg['voiceName'] as String?;
      _translationId = cfg['translationServiceId'] as String?;
      _stsId = cfg['stsServiceId'] as String?;
      _mcpIds = List<String>.from(cfg['mcpServiceIds'] as List? ?? []);
      _promptCtrl = TextEditingController(
          text: cfg['systemPrompt'] as String? ??
              '你是一位专业的 AI 助手，请简洁准确地回答用户问题。');
      _srcLang = cfg['srcLang'] as String? ?? '中文';
      _dstLang = cfg['dstLang'] as String? ?? 'English';
    } else {
      _nameCtrl = TextEditingController();
      _type = 'chat';
      _mcpIds = [];
      _promptCtrl = TextEditingController(text: '你是一位专业的 AI 助手，请简洁准确地回答用户问题。');
      _srcLang = '中文';
      _dstLang = 'English';
    }
  }

  static const _langs = ['中文', 'English', '日本語', '한국어', 'Français', 'Deutsch', 'Español', 'Русский', 'العربية'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  /// Shows a bottom-sheet picker for services of [type].
  /// Returns selected service id, '__clear__' for "不使用", or null if dismissed.
  Future<void> _pickService(String type, String? currentId, {bool nullable = true}) async {
    final services = ref.read(serviceLibraryProvider).where((s) => s.type == type).toList();
    if (services.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('没有可用的 ${_typeDisplayName(type)} 服务，请先在服务中心添加')),
      );
      return;
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServicePickerSheet(
        type: type,
        services: services,
        currentId: currentId,
        nullable: nullable,
      ),
    );
    if (result == null) return; // dismissed

    if (type == 'llm') {
      setState(() => _llmId = result == '__clear__' ? null : result);
    } else if (type == 'translation') {
      setState(() => _translationId = result == '__clear__' ? null : result);
    } else if (type == 'sts' || type == 'ast') {
      setState(() => _stsId = result == '__clear__' ? null : result);
    } else if (type == 'stt') {
      setState(() => _sttId = result == '__clear__' ? null : result);
    } else if (type == 'tts') {
      final id = result == '__clear__' ? null : result;
      String? voice;
      if (id != null) {
        try {
          final s = services.firstWhere((s) => s.id == id);
          final cfg = jsonDecode(s.configJson) as Map;
          voice = cfg['voiceName'] as String?;
        } catch (_) {}
      }
      setState(() { _ttsId = id; _voiceName = voice; });
    }
  }

  Future<void> _pickMcp() async {
    final allMcp = ref.read(serviceLibraryProvider).where((s) => s.type == 'mcp').toList();
    final available = allMcp.where((s) => !_mcpIds.contains(s.id)).toList();
    if (available.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(allMcp.isEmpty
            ? '没有可用的 MCP 服务，请先在服务中心添加'
            : '所有 MCP 服务已添加')),
      );
      return;
    }
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ServicePickerSheet(
        type: 'mcp',
        services: available,
        currentId: null,
        nullable: false,
      ),
    );
    if (result != null && result != '__clear__') {
      setState(() => _mcpIds.add(result));
    }
  }

  Future<void> _pickLang(bool isSrc) async {
    final current = isSrc ? _srcLang : _dstLang;
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36, height: 4,
              decoration: BoxDecoration(color: AppTheme.borderColor, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(isSrc ? '源语言' : '目标语言',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            ),
            const Divider(height: 1),
            ..._langs.map((l) => ListTile(
              title: Text(l, style: TextStyle(
                fontSize: 14,
                fontWeight: l == current ? FontWeight.w700 : FontWeight.w400,
                color: l == current ? AppTheme.translateAccent : AppTheme.text1,
              )),
              trailing: l == current ? const Icon(Icons.check, color: AppTheme.translateAccent, size: 18) : null,
              onTap: () => Navigator.pop(ctx, l),
            )),
            SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8),
          ],
        ),
      ),
    );
    if (result != null) {
      setState(() {
        if (isSrc) { _srcLang = result; } else { _dstLang = result; }
      });
    }
  }

  String _serviceName(String? id, List<ServiceConfigDto> allServices) {
    if (id == null) return '不使用';
    try { return allServices.firstWhere((s) => s.id == id).name; } catch (_) { return '已删除'; }
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(serviceLibraryProvider);

    String nameOf(String? id) => _serviceName(id, services);

    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      margin: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppTheme.borderColor, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Text(_isEditing ? '编辑 Agent' : '添加 Agent',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.text1)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: AppTheme.text2, size: 22),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Agent 名称'),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(hintText: '例如：英语学习助手'),
                  ),
                  const SizedBox(height: 16),

                  _label('Agent 类型'),
                  Column(children: [
                    Row(children: [
                      _typeBtn('💬 聊天', 'chat'),
                      const SizedBox(width: 8),
                      _typeBtn('🌐 翻译', 'translate'),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _typeBtn('🎙 端到端对话', 'sts'),
                      const SizedBox(width: 8),
                      _typeBtn('🔄 端到端翻译', 'ast'),
                    ]),
                  ]),
                  const SizedBox(height: 16),

                  // ── LLM 服务（chat / translate 需要）──
                  if (_type == 'chat' || _type == 'translate') ...[
                    _label('LLM 服务 *'),
                    _serviceRow(
                      label: _llmId != null ? nameOf(_llmId) : '请选择 LLM 服务',
                      hasValue: _llmId != null,
                      isEmpty: services.where((s) => s.type == 'llm').isEmpty,
                      onTap: () => _pickService('llm', _llmId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                    _label('STT 服务（语音输入，可选）'),
                    _serviceRow(
                      label: _sttId != null ? nameOf(_sttId) : '不使用',
                      hasValue: _sttId != null,
                      isEmpty: services.where((s) => s.type == 'stt').isEmpty,
                      onTap: () => _pickService('stt', _sttId),
                    ),
                    const SizedBox(height: 14),
                    _label('TTS 服务（语音输出，可选）'),
                    _serviceRow(
                      label: _ttsId != null ? nameOf(_ttsId) : '不使用',
                      hasValue: _ttsId != null,
                      isEmpty: services.where((s) => s.type == 'tts').isEmpty,
                      onTap: () => _pickService('tts', _ttsId),
                    ),
                    if (_ttsId != null && _voiceName != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        const Icon(Icons.record_voice_over, size: 13, color: AppTheme.text2),
                        const SizedBox(width: 5),
                        Text('音色：$_voiceName',
                            style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
                      ]),
                    ],
                    const SizedBox(height: 14),
                  ],

                  // ── STS 服务（sts 需要）──
                  if (_type == 'sts') ...[
                    _label('STS 服务 *（端到端语音对话）'),
                    _serviceRow(
                      label: _stsId != null ? nameOf(_stsId) : '请选择 STS 服务',
                      hasValue: _stsId != null,
                      isEmpty: services.where((s) => s.type == 'sts').isEmpty,
                      onTap: () => _pickService('sts', _stsId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── AST 服务（ast 需要）──
                  if (_type == 'ast') ...[
                    _label('AST 服务 *（端到端同声传译）'),
                    _serviceRow(
                      label: _stsId != null ? nameOf(_stsId) : '请选择 AST 服务',
                      hasValue: _stsId != null,
                      isEmpty: services.where((s) => s.type == 'ast').isEmpty,
                      onTap: () => _pickService('ast', _stsId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Chat-specific: MCP + system prompt ──
                  if (_type == 'chat') ...[
                    _label('MCP 服务（可选）'),
                    ..._mcpIds.map((id) => _McpItem(
                      name: nameOf(id),
                      onRemove: () => setState(() => _mcpIds.remove(id)),
                    )),
                    const SizedBox(height: 6),
                    _addMcpButton(),
                    const SizedBox(height: 16),
                    _label('系统提示词'),
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: '描述 AI 的角色和行为…'),
                    ),
                  ],

                  // ── Translate-specific: translation service + language pair ──
                  if (_type == 'translate') ...[
                    _label('翻译服务（可选，不选则用 LLM 翻译）'),
                    _serviceRow(
                      label: _translationId != null ? nameOf(_translationId) : '不使用',
                      hasValue: _translationId != null,
                      isEmpty: services.where((s) => s.type == 'translation').isEmpty,
                      onTap: () => _pickService('translation', _translationId),
                    ),
                    const SizedBox(height: 16),
                    _label('翻译语言对'),
                    Row(children: [
                      Expanded(child: _langBtn(_srcLang, () => _pickLang(true))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.swap_horiz, color: AppTheme.translateAccent),
                      ),
                      Expanded(child: _langBtn(_dstLang, () => _pickLang(false))),
                    ]),
                  ],

                  // ── ast-specific: language pair ──
                  if (_type == 'ast') ...[
                    _label('翻译语言对'),
                    Row(children: [
                      Expanded(child: _langBtn(_srcLang, () => _pickLang(true))),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.swap_horiz, color: AppTheme.translateAccent),
                      ),
                      Expanded(child: _langBtn(_dstLang, () => _pickLang(false))),
                    ]),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.text2,
                      side: const BorderSide(color: AppTheme.borderColor),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _isEditing ? _save : _create,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: Text(_isEditing ? '保存' : '创建 Agent',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text2)),
  );

  Widget _typeBtn(String label, String value) {
    final sel = _type == value;
    final (Color bg, Color border, Color fg) = switch (value) {
      'chat'      => (AppTheme.primaryLight,         AppTheme.primary,              AppTheme.primaryDark),
      'translate' => (const Color(0xFFE0F2FE),        AppTheme.translateAccent,      const Color(0xFF0369A1)),
      'sts'       => (const Color(0xFFFFF7ED),        const Color(0xFFF97316),       const Color(0xFF9A3412)),
      _           => (const Color(0xFFECFDF5),        const Color(0xFF10B981),       const Color(0xFF065F46)),
    };
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? bg : AppTheme.bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? border : AppTheme.borderColor,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: sel ? fg : AppTheme.text2,
          )),
        ),
      ),
    );
  }

  Widget _serviceRow({
    required String label,
    required bool hasValue,
    required bool isEmpty,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 7, height: 7,
              decoration: BoxDecoration(
                color: hasValue ? AppTheme.success : AppTheme.borderColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: hasValue ? AppTheme.text1 : AppTheme.text2,
                ),
              ),
            ),
            if (isEmpty)
              const Text('未配置', style: TextStyle(fontSize: 11, color: AppTheme.warning))
            else
              const Icon(Icons.keyboard_arrow_down, color: AppTheme.text2, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _addMcpButton() => GestureDetector(
    onTap: _pickMcp,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary),
      ),
      alignment: Alignment.center,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, color: AppTheme.primary, size: 16),
          SizedBox(width: 4),
          Text('添加 MCP 服务', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
        ],
      ),
    ),
  );

  Widget _langBtn(String lang, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.translateAccent, width: 1.5),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(lang, style: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.translateAccent)),
    ),
  );

  Map<String, dynamic> _buildConfig() => {
    if (_llmId != null) 'llmServiceId': _llmId,
    if (_sttId != null) 'sttServiceId': _sttId,
    if (_ttsId != null) 'ttsServiceId': _ttsId,
    if (_voiceName != null) 'voiceName': _voiceName,
    if (_stsId != null) 'stsServiceId': _stsId,
    if (_type == 'chat' && _mcpIds.isNotEmpty) 'mcpServiceIds': _mcpIds,
    if (_type == 'chat') 'systemPrompt': _promptCtrl.text.trim(),
    if (_type == 'translate') ...{
      if (_translationId != null) 'translationServiceId': _translationId,
      'srcLang': _srcLang,
      'dstLang': _dstLang,
    },
    if (_type == 'ast') ...{
      'srcLang': _srcLang,
      'dstLang': _dstLang,
    },
  };

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return '请输入 Agent 名称';
    if ((_type == 'chat' || _type == 'translate') && _llmId == null) return '请选择 LLM 服务';
    if ((_type == 'sts' || _type == 'ast') && _stsId == null) return '请选择 STS 服务';
    return null;
  }

  void _save() {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ref.read(agentListProvider.notifier).updateAgent(
      id: widget.agent!.id,
      name: _nameCtrl.text.trim(),
      type: _type,
      config: _buildConfig(),
    );
    Navigator.pop(context);
  }

  void _create() {
    final err = _validate();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    ref.read(agentListProvider.notifier).addAgent(
      name: _nameCtrl.text.trim(),
      type: _type,
      config: _buildConfig(),
    );
    Navigator.pop(context);
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _typeDisplayName(String type) => switch (type) {
      'stt' => 'STT',
      'tts' => 'TTS',
      'llm' => 'LLM',
      'sts' => 'STS',
      'ast' => 'AST',
      'mcp' => 'MCP',
      'translation' => '翻译',
      _ => type.toUpperCase(),
    };

// ── MCP item row ──────────────────────────────────────────────────────────────

class _McpItem extends StatelessWidget {
  const _McpItem({required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text1))),
          const Text('MCP', style: TextStyle(fontSize: 10, color: AppTheme.text2)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close, size: 16, color: AppTheme.text2),
          ),
        ],
      ),
    );
  }
}

// ── Service picker bottom sheet ───────────────────────────────────────────────

class _ServicePickerSheet extends StatelessWidget {
  const _ServicePickerSheet({
    required this.type,
    required this.services,
    required this.currentId,
    required this.nullable,
  });
  final String type;
  final List<ServiceConfigDto> services;
  final String? currentId;
  final bool nullable;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: AppTheme.borderColor, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              '选择 ${_typeDisplayName(type)} 服务',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.text1),
            ),
          ),
          const Divider(height: 1),
          if (nullable)
            ListTile(
              leading: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: currentId == null ? AppTheme.primary : AppTheme.borderColor,
                  shape: BoxShape.circle,
                ),
              ),
              title: const Text('不使用', style: TextStyle(fontSize: 14, color: AppTheme.text2)),
              trailing: currentId == null ? const Icon(Icons.check, color: AppTheme.primary, size: 18) : null,
              onTap: () => Navigator.pop(context, '__clear__'),
            ),
          ...services.map((s) {
            final sel = s.id == currentId;
            return ListTile(
              leading: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: sel ? AppTheme.primary : AppTheme.borderColor,
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(s.name, style: TextStyle(
                fontSize: 14,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? AppTheme.primary : AppTheme.text1,
              )),
              subtitle: Text(_vendorLabel(s.vendor),
                  style: const TextStyle(fontSize: 11, color: AppTheme.text2)),
              trailing: sel ? const Icon(Icons.check, color: AppTheme.primary, size: 18) : null,
              onTap: () => Navigator.pop(context, s.id),
            );
          }),
          SizedBox(height: MediaQuery.paddingOf(context).bottom + 10),
        ],
      ),
    );
  }

  String _vendorLabel(String vendor) => switch (vendor) {
        'openai' => 'OpenAI',
        'anthropic' => 'Anthropic',
        'google' => 'Google',
        'azure' => 'Azure',
        'aliyun' => '阿里云',
        'doubao' => '火山引擎',
        'deepseek' => 'DeepSeek',
        'tongyi' => '通义千问',
        'deepl' => 'DeepL',
        'remote' => '远程 MCP',
        _ => vendor,
      };
}
