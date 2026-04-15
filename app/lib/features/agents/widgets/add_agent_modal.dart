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
  String? _stsId;
  String? _astId;
  late final List<String> _mcpIds;

  // Tags
  late List<String> _tags;
  final TextEditingController _tagCtrl = TextEditingController();

  // Chat / STS-Chat config
  late final TextEditingController _promptCtrl;

  // 音频配置（每个 Agent 独立）
  bool _vadEnabled = true;
  int _silenceTimeout = 3;
  int _speechMinDuration = 300; // ms, 最短说话时长

  // Translate / AST language support (multi-select)
  late Set<String> _srcLangs;
  late Set<String> _dstLangs;

  bool get _isEditing => widget.agent != null;

  // Language codes & display names
  static const _langCodes = ['zh', 'en', 'ja', 'ko', 'fr', 'de', 'es', 'ru', 'ar', 'pt'];
  static const _langNames = {
    'auto': '自动检测',
    'zh': '中文 (ZH)', 'en': 'English (EN)', 'ja': '日语 (JA)', 'ko': '韩语 (KO)',
    'fr': '法语 (FR)', 'de': '德语 (DE)', 'es': '西班牙语 (ES)',
    'ru': '俄语 (RU)', 'ar': '阿拉伯语 (AR)', 'pt': '葡萄牙语 (PT)',
  };
  // Type-specific accent colors
  static const _typeColors = {
    'chat':          (Color(0xFF6C63FF), Color(0xFFEEF0FF), Color(0xFF4A42D9)),
    'translate':     (Color(0xFF0EA5E9), Color(0xFFE0F2FE), Color(0xFF0369A1)),
    'sts-chat':      (Color(0xFFF59E0B), Color(0xFFFFFBEB), Color(0xFFB45309)),
    'ast-translate': (Color(0xFF14B8A6), Color(0xFFF0FDFA), Color(0xFF0F766E)),
  };

  Color get _accentColor => _typeColors[_type]!.$1;

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
      _astId = cfg['astServiceId'] as String?;
      _tags = List<String>.from(cfg['tags'] as List? ?? []);
      _mcpIds = List<String>.from(cfg['mcpServiceIds'] as List? ?? []);
      _vadEnabled = cfg['vadEnabled'] as bool? ?? true;
      _silenceTimeout = cfg['silenceTimeout'] as int? ?? 3;
      _speechMinDuration = cfg['speechMinDuration'] as int? ?? 300;
      _promptCtrl = TextEditingController(
          text: cfg['systemPrompt'] as String? ??
              '你是一位专业的 AI 助手，请简洁准确地回答用户问题。');
      // Backward compat: migrate single srcLang/dstLang → sets
      final srcList = cfg['srcLangs'] as List?;
      final dstList = cfg['dstLangs'] as List?;
      if (srcList != null) {
        _srcLangs = Set<String>.from(srcList);
      } else {
        final old = cfg['srcLang'] as String?;
        _srcLangs = old != null ? {old} : {'zh', 'en'};
      }
      if (dstList != null) {
        _dstLangs = Set<String>.from(dstList);
      } else {
        final old = cfg['dstLang'] as String?;
        _dstLangs = old != null ? {old} : {'en'};
      }
    } else {
      _nameCtrl = TextEditingController();
      _type = 'chat';
      _tags = [];
      _mcpIds = [];
      _promptCtrl = TextEditingController(text: '你是一位专业的 AI 助手，请简洁准确地回答用户问题。');
      _srcLangs = {'auto', 'zh', 'en'};
      _dstLangs = {'en'};
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tagCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  // ── Service picking ─────────────────────────────────────────────────────────

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
    if (result == null) return;

    if (type == 'llm') {
      setState(() => _llmId = result == '__clear__' ? null : result);
    } else if (type == 'translation') {
      setState(() => _translationId = result == '__clear__' ? null : result);
    } else if (type == 'sts') {
      setState(() => _stsId = result == '__clear__' ? null : result);
    } else if (type == 'ast') {
      setState(() => _astId = result == '__clear__' ? null : result);
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

  String _serviceName(String? id, List<ServiceConfigDto> allServices) {
    if (id == null) return '不使用';
    try { return allServices.firstWhere((s) => s.id == id).name; } catch (_) { return '已删除'; }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

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
                  // ── Agent name ──
                  _label('Agent 名称'),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(hintText: '例如：英语学习助手'),
                  ),
                  const SizedBox(height: 16),

                  // ── Tags ──
                  _label('标签（可选）'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ..._tags.map((tag) => Chip(
                        label: Text(tag, style: const TextStyle(fontSize: 12)),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => setState(() => _tags.remove(tag)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppTheme.primaryLight,
                        side: BorderSide.none,
                      )),
                      SizedBox(
                        width: 100,
                        height: 32,
                        child: TextField(
                          controller: _tagCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: '+ 添加标签',
                            hintStyle: TextStyle(fontSize: 12, color: AppTheme.text2),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (v) {
                            final tag = v.trim();
                            if (tag.isNotEmpty && !_tags.contains(tag)) {
                              setState(() => _tags.add(tag));
                            }
                            _tagCtrl.clear();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Type selector (2×2 grid) ──
                  _label('Agent 类型'),
                  Column(children: [
                    Row(children: [
                      _typeBtn('💬 Chat', '三段式 · 聊天', 'chat'),
                      const SizedBox(width: 8),
                      _typeBtn('🌐 Translate', '三段式 · 翻译', 'translate'),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      _typeBtn('🗣️ STS-Chat', '端到端 · 聊天', 'sts-chat'),
                      const SizedBox(width: 8),
                      _typeBtn('🔄 AST-Translate', '端到端 · 翻译', 'ast-translate'),
                    ]),
                  ]),
                  const SizedBox(height: 16),

                  // ══════════════════════════════════════════════════════════
                  //  CHAT: LLM* + STT* + TTS* + MCP + 系统提示词
                  // ══════════════════════════════════════════════════════════
                  if (_type == 'chat') ...[
                    _label('LLM 服务 *'),
                    _serviceRow(
                      label: _llmId != null ? nameOf(_llmId) : '请选择 LLM 服务',
                      hasValue: _llmId != null,
                      isEmpty: services.where((s) => s.type == 'llm').isEmpty,
                      onTap: () => _pickService('llm', _llmId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                    _label('STT 服务 *（语音输入）'),
                    _serviceRow(
                      label: _sttId != null ? nameOf(_sttId) : '请选择 STT 服务',
                      hasValue: _sttId != null,
                      isEmpty: services.where((s) => s.type == 'stt').isEmpty,
                      onTap: () => _pickService('stt', _sttId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                    _label('TTS 服务 *（语音输出）'),
                    _serviceRow(
                      label: _ttsId != null ? nameOf(_ttsId) : '请选择 TTS 服务',
                      hasValue: _ttsId != null,
                      isEmpty: services.where((s) => s.type == 'tts').isEmpty,
                      onTap: () => _pickService('tts', _ttsId, nullable: false),
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
                    _label('系统提示词'),
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: '描述 AI 的角色和行为…'),
                    ),
                    const SizedBox(height: 14),
                    _label('MCP 服务器（可选）'),
                    ..._mcpIds.map((id) => _McpItem(
                      name: nameOf(id),
                      onRemove: () => setState(() => _mcpIds.remove(id)),
                    )),
                    const SizedBox(height: 6),
                    _addMcpButton(AppTheme.primary, AppTheme.primaryLight),
                  ],

                  // ══════════════════════════════════════════════════════════
                  //  TRANSLATE: 翻译服务* + 语言支持 + STT(可选) + TTS(可选)
                  // ══════════════════════════════════════════════════════════
                  if (_type == 'translate') ...[
                    _label('翻译服务 *'),
                    _serviceRow(
                      label: _translationId != null ? nameOf(_translationId) : '请选择翻译服务',
                      hasValue: _translationId != null,
                      isEmpty: services.where((s) => s.type == 'translation').isEmpty,
                      onTap: () => _pickService('translation', _translationId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                    _langMultiSelect('来源语言支持', _srcLangs, includingAuto: true, accent: AppTheme.translateAccent),
                    const SizedBox(height: 14),
                    _langMultiSelect('目标语言支持', _dstLangs, includingAuto: false, accent: AppTheme.translateAccent),
                    const SizedBox(height: 14),
                    _label('STT 服务（语音输入，可选）'),
                    _serviceRow(
                      label: _sttId != null ? nameOf(_sttId) : '不启用语音输入',
                      hasValue: _sttId != null,
                      isEmpty: services.where((s) => s.type == 'stt').isEmpty,
                      onTap: () => _pickService('stt', _sttId),
                    ),
                    const SizedBox(height: 14),
                    _label('TTS 服务（朗读译文，可选）'),
                    _serviceRow(
                      label: _ttsId != null ? nameOf(_ttsId) : '不启用语音朗读',
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
                  ],

                  // ══════════════════════════════════════════════════════════
                  //  STS-CHAT: STS服务* + 系统提示词 + MCP
                  // ══════════════════════════════════════════════════════════
                  if (_type == 'sts-chat') ...[
                    _e2eBanner(
                      bg: const Color(0xFFFFFBEB),
                      border: const Color(0xFFFDE68A),
                      fg: const Color(0xFF92400E),
                      text: '端到端模式：语音输入/输出和 LLM 由单一 STS 服务完成，无需分别配置 STT、LLM、TTS。',
                    ),
                    const SizedBox(height: 14),
                    _label('STS 服务 *'),
                    _serviceRow(
                      label: _stsId != null ? nameOf(_stsId) : '请选择 STS 服务',
                      hasValue: _stsId != null,
                      isEmpty: services.where((s) => s.type == 'sts').isEmpty,
                      onTap: () => _pickService('sts', _stsId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                    _label('系统提示词'),
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: '描述 AI 的角色和行为…'),
                    ),
                    const SizedBox(height: 14),
                    _label('MCP 服务器（可选）'),
                    ..._mcpIds.map((id) => _McpItem(
                      name: nameOf(id),
                      onRemove: () => setState(() => _mcpIds.remove(id)),
                    )),
                    const SizedBox(height: 6),
                    _addMcpButton(const Color(0xFFB45309), const Color(0xFFFFFBEB)),
                  ],

                  // ══════════════════════════════════════════════════════════
                  //  AST-TRANSLATE: AST服务* + 语言支持
                  // ══════════════════════════════════════════════════════════
                  if (_type == 'ast-translate') ...[
                    _e2eBanner(
                      bg: const Color(0xFFF0FDFA),
                      border: const Color(0xFF99F6E4),
                      fg: const Color(0xFF0F766E),
                      text: '端到端模式：语音识别、翻译、语音合成由单一 AST 服务完成，无需分别配置 STT、翻译、TTS。',
                    ),
                    const SizedBox(height: 14),
                    _label('AST 服务 *'),
                    _serviceRow(
                      label: _astId != null ? nameOf(_astId) : '请选择 AST 服务',
                      hasValue: _astId != null,
                      isEmpty: services.where((s) => s.type == 'ast').isEmpty,
                      onTap: () => _pickService('ast', _astId, nullable: false),
                    ),
                    const SizedBox(height: 14),
                    _langMultiSelect('来源语言支持', _srcLangs, includingAuto: false, accent: const Color(0xFF14B8A6)),
                    const SizedBox(height: 14),
                    _langMultiSelect('目标语言支持', _dstLangs, includingAuto: false, accent: const Color(0xFF14B8A6)),
                  ],

                  // ══════════════════════════════════════════════════════════
                  //  音频配置（所有 Agent 类型通用）
                  // ══════════════════════════════════════════════════════════
                  const SizedBox(height: 20),
                  const Divider(color: AppTheme.borderColor),
                  const SizedBox(height: 12),
                  _label('音频配置'),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // VAD 开关
                        Row(
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('语音活动检测 (VAD)',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.text1)),
                                  SizedBox(height: 2),
                                  Text('自动检测说话开始与结束',
                                      style: TextStyle(fontSize: 11, color: AppTheme.text2)),
                                ],
                              ),
                            ),
                            Switch(
                              value: _vadEnabled,
                              activeColor: _accentColor,
                              onChanged: (v) => setState(() => _vadEnabled = v),
                            ),
                          ],
                        ),
                        if (_vadEnabled) ...[
                          const SizedBox(height: 12),
                          // 静音超时
                          Row(
                            children: [
                              const Expanded(
                                child: Text('静音断句超时',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                              ),
                              Text('$_silenceTimeout 秒',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentColor)),
                            ],
                          ),
                          Slider(
                            value: _silenceTimeout.toDouble(),
                            min: 1,
                            max: 10,
                            divisions: 9,
                            activeColor: _accentColor,
                            onChanged: (v) => setState(() => _silenceTimeout = v.round()),
                          ),
                          const SizedBox(height: 8),
                          // 最短说话时长
                          Row(
                            children: [
                              const Expanded(
                                child: Text('最短说话时长',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.text1)),
                              ),
                              Text('$_speechMinDuration ms',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentColor)),
                            ],
                          ),
                          Slider(
                            value: _speechMinDuration.toDouble(),
                            min: 100,
                            max: 1000,
                            divisions: 9,
                            activeColor: _accentColor,
                            onChanged: (v) => setState(() => _speechMinDuration = v.round()),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),

          // ── Footer ──
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
                      backgroundColor: _accentColor,
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

  // ── UI components ───────────────────────────────────────────────────────────

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.text2)),
  );

  Widget _typeBtn(String label, String hint, String value) {
    final sel = _type == value;
    final colors = _typeColors[value]!;
    final (Color accent, Color bg, Color fg) = colors;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? bg : AppTheme.bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: sel ? accent : AppTheme.borderColor,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: sel ? fg : AppTheme.text2,
              )),
              const SizedBox(height: 2),
              Text(hint, style: TextStyle(
                fontSize: 9,
                color: (sel ? fg : AppTheme.text2).withValues(alpha: sel ? 0.7 : 0.6),
              )),
            ],
          ),
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

  /// End-to-end info banner
  Widget _e2eBanner({
    required Color bg,
    required Color border,
    required Color fg,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.5),
      ),
      child: Row(
        children: [
          const Text('⚡', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: fg, height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// Multi-select language chips
  Widget _langMultiSelect(String title, Set<String> selected, {
    required bool includingAuto,
    required Color accent,
  }) {
    final codes = [if (includingAuto) 'auto', ..._langCodes];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(title),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.borderColor),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: codes.map((code) {
              final sel = selected.contains(code);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (sel) {
                      selected.remove(code);
                    } else {
                      selected.add(code);
                    }
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sel ? accent : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: sel ? null : Border.all(color: AppTheme.borderColor, width: 1.5),
                  ),
                  child: Text(
                    _langNames[code] ?? code,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      color: sel ? Colors.white : AppTheme.text2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _addMcpButton(Color accent, Color bg) => GestureDetector(
    onTap: _pickMcp,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, color: accent, size: 16),
          const SizedBox(width: 4),
          Text('添加 MCP 服务器', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
        ],
      ),
    ),
  );

  // ── Config & validation ─────────────────────────────────────────────────────

  Map<String, dynamic> _buildConfig() => {
    if (_tags.isNotEmpty) 'tags': _tags,
    if (_llmId != null) 'llmServiceId': _llmId,
    if (_sttId != null) 'sttServiceId': _sttId,
    if (_ttsId != null) 'ttsServiceId': _ttsId,
    if (_voiceName != null) 'voiceName': _voiceName,
    if (_stsId != null) 'stsServiceId': _stsId,
    if (_astId != null) 'astServiceId': _astId,
    if ((_type == 'chat' || _type == 'sts-chat') && _mcpIds.isNotEmpty) 'mcpServiceIds': _mcpIds,
    if (_type == 'chat' || _type == 'sts-chat') 'systemPrompt': _promptCtrl.text.trim(),
    if (_type == 'translate') ...{
      if (_translationId != null) 'translationServiceId': _translationId,
      'srcLangs': _srcLangs.toList(),
      'dstLangs': _dstLangs.toList(),
    },
    if (_type == 'ast-translate') ...{
      'srcLangs': _srcLangs.toList(),
      'dstLangs': _dstLangs.toList(),
    },
    // 音频配置
    'vadEnabled': _vadEnabled,
    'silenceTimeout': _silenceTimeout,
    'speechMinDuration': _speechMinDuration,
  };

  String? _validate() {
    if (_nameCtrl.text.trim().isEmpty) return '请输入 Agent 名称';
    if (_type == 'chat') {
      if (_llmId == null) return '请选择 LLM 服务';
      if (_sttId == null) return '请选择 STT 服务';
      if (_ttsId == null) return '请选择 TTS 服务';
    }
    if (_type == 'translate') {
      if (_translationId == null) return '请选择翻译服务';
      if (_srcLangs.isEmpty) return '请至少选择一个来源语言';
      if (_dstLangs.isEmpty) return '请至少选择一个目标语言';
    }
    if (_type == 'sts-chat' && _stsId == null) return '请选择 STS 服务';
    if (_type == 'ast-translate') {
      if (_astId == null) return '请选择 AST 服务';
      if (_srcLangs.isEmpty) return '请至少选择一个来源语言';
      if (_dstLangs.isEmpty) return '请至少选择一个目标语言';
    }
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
            decoration: const BoxDecoration(color: Color(0xFF16A34A), shape: BoxShape.circle),
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
