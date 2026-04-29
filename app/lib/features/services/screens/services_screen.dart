import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:local_db/local_db.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:ai_plugin_interface/ai_plugin_interface.dart';
import 'package:service_manager/service_manager.dart';
import 'package:stt_azure/stt_azure.dart';
import 'package:agents_server/agents_server.dart' hide SttEvent, LlmEvent;
import 'package:agents_server/agents_server.dart' as rt show SttEvent, LlmEvent;
import '../../../core/services/locale_service.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/service_library_provider.dart';
import '../widgets/add_service_modal.dart';
import '../widgets/ast_test_panel.dart';
import '../widgets/sts_test_panel.dart';

class _VoiceInfo {
  const _VoiceInfo({required this.shortName, required this.displayName, required this.locale, this.gender = ''});
  final String shortName;
  final String displayName;
  final String locale;
  final String gender;

  String get chipLabel {
    final g = gender.toLowerCase() == 'female' ? '女声' : gender.toLowerCase() == 'male' ? '男声' : '';
    return g.isEmpty ? displayName : '$displayName · $g';
  }
}

// ── Badge colors matching HTML mockup ────────────────────────────────────────
Color _typeBg(String type) => switch (type) {
      'stt' => const Color(0xFFFEF3C7),
      'tts' => const Color(0xFFF0FDF4),
      'llm' => const Color(0xFFFAF5FF),
      'translation' => const Color(0xFFEFF6FF),
      'sts' => const Color(0xFFEEF0FF),
      'ast' => const Color(0xFFFFF7ED),
      'mcp' => const Color(0xFFE8F5E9),
      _ => const Color(0xFFF3F4F6),
    };

Color _typeFg(String type) => switch (type) {
      'stt' => const Color(0xFF92400E),
      'tts' => const Color(0xFF14532D),
      'llm' => const Color(0xFF6B21A8),
      'translation' => const Color(0xFF1D4ED8),
      'sts' => const Color(0xFF4A42D9),
      'ast' => const Color(0xFF9A3412),
      'mcp' => const Color(0xFF1B5E20),
      _ => AppTheme.text2,
    };

String _typeLabel(String type) => switch (type) {
      'stt' => 'STT',
      'tts' => 'TTS',
      'llm' => 'LLM',
      'translation' => '翻译',
      'sts' => 'STS',
      'ast' => 'AST',
      'mcp' => 'MCP',
      _ => type.toUpperCase(),
    };

String _typeSectionLabel(String type) => switch (type) {
      'stt' => '语音识别 STT',
      'tts' => '语音合成 TTS',
      'llm' => '大语言模型 LLM',
      'translation' => '翻译服务',
      'sts' => '语音转语音 STS',
      'ast' => '端到端翻译 AST',
      'mcp' => 'MCP 服务',
      _ => type.toUpperCase(),
    };

// ── Main screen ──────────────────────────────────────────────────────────────

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(serviceLibraryProvider);
    final colors = context.appColors;

    // 没有服务时自动退出编辑模式
    if (services.isEmpty && _editing) {
      _editing = false;
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('服务中心',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.text1)),
            Text('已配置 ${services.length} 个服务',
                style: TextStyle(fontSize: 11, color: colors.text2, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          if (services.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _editing = !_editing),
              child: Text(
                _editing ? '完成' : '编辑',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _editing ? AppTheme.primary : colors.text2,
                ),
              ),
            ),
        ],
      ),
      body: services.isEmpty ? _buildEmpty(context) : _buildContent(context, services),
      floatingActionButton: _editing ? null : FloatingActionButton(
        onPressed: () => _showAddModal(context),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddModal(BuildContext context, {ServiceConfigDto? service}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddServiceModal(initialService: service),
    );
  }

  void _navigateToServiceTest(BuildContext context, ServiceConfigDto service) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => ServiceTestScreen(service: service),
    ));
  }

  Future<void> _confirmDelete(ServiceConfigDto service) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除服务'),
        content: Text('确定要删除「${service.name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await ref.read(serviceLibraryProvider.notifier).removeService(service.id);
    }
  }

  Widget _buildEmpty(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: colors.primaryTint, shape: BoxShape.circle),
            child: const Icon(Icons.grid_view_rounded, size: 36, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          Text('还没有配置服务',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.text1)),
          const SizedBox(height: 6),
          Text('点击下方 + 添加 STT / TTS / LLM 等服务',
              style: TextStyle(fontSize: 12, color: colors.text2)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _showAddModal(context),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('添加第一个服务'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<ServiceConfigDto> services) {
    // Sort: llm → stt → tts → translation → sts → ast → mcp
    const typeOrder = ['llm', 'stt', 'tts', 'translation', 'sts', 'ast', 'mcp'];
    final sorted = List<ServiceConfigDto>.from(services)
      ..sort((a, b) {
        final ai = typeOrder.indexOf(a.type);
        final bi = typeOrder.indexOf(b.type);
        return (ai == -1 ? 99 : ai).compareTo(bi == -1 ? 99 : bi);
      });

    final colors = context.appColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      children: [
        Text('已配置服务',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.text1)),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.8,
          ),
          itemCount: _editing ? sorted.length : sorted.length + 1,
          itemBuilder: (_, i) {
            if (i < sorted.length) {
              return _ServiceCard(
                service: sorted[i],
                editing: _editing,
                onTap: _editing ? null : () => _navigateToServiceTest(context, sorted[i]),
                onDelete: _editing ? () => _confirmDelete(sorted[i]) : null,
              );
            }
            // 末尾虚线框 "添加新服务"（编辑模式下隐藏）
            return GestureDetector(
              onTap: () => _showAddModal(context),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('+', style: TextStyle(fontSize: 22, color: colors.text2.withValues(alpha: 0.5), fontWeight: FontWeight.w300)),
                    const SizedBox(height: 2),
                    Text('添加服务', style: TextStyle(fontSize: 11, color: colors.text2)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Import conflict resolution dialog ────────────────────────────────────────

// ── Service test screen (full page, per service) ────────────────────────────
// 上部分：可编辑服务配置 + 保存  下部分：按类型显示的测试板块

class ServiceTestScreen extends ConsumerStatefulWidget {
  const ServiceTestScreen({super.key, required this.service});
  final ServiceConfigDto service;

  @override
  ConsumerState<ServiceTestScreen> createState() => _ServiceTestScreenState();
}

class _ServiceTestScreenState extends ConsumerState<ServiceTestScreen> {
  late ServiceConfigDto _svc;
  late TextEditingController _nameCtrl;
  late Map<String, TextEditingController> _cfgCtrls;
  bool _dirty = false;

  // Config fields to show per vendor (field key → display label)
  static const _vendorFields = <String, List<(String, String, bool)>>{
    // (key, label, obscure)
    'openai':    [('apiKey', 'API Key *', true), ('baseUrl', 'Base URL', false), ('model', 'Model', false)],
    'anthropic': [('apiKey', 'API Key *', true), ('baseUrl', 'Base URL', false), ('model', 'Model', false)],
    'google':    [('apiKey', 'API Key *', true), ('baseUrl', 'Base URL', false), ('model', 'Model', false)],
    'azure':     [('apiKey', 'API Key *', true), ('region', 'Region *', false), ('voiceName', 'Voice Name', false)],
    'aliyun':    [('appKey', 'App Key *', true), ('accessKeyId', 'Access Key ID *', true), ('accessKeySecret', 'Access Key Secret *', true)],
    // volcengine 字段随 type 变化，见 _resolveFields
    'volcengine': [],
    'deepseek':  [('apiKey', 'API Key *', true), ('baseUrl', 'Base URL', false), ('model', 'Model', false)],
    'tongyi':    [('apiKey', 'API Key *', true), ('baseUrl', 'Base URL', false), ('model', 'Model', false)],
    'deepl':     [('authKey', 'Auth Key *', true)],
    'remote':    [('url', 'Server URL *', false), ('transport', 'Transport (sse/http)', false), ('authHeader', 'Auth Header', false)],
    'polychat':  [('baseUrl', '服务器地址 *', false), ('appId', 'App ID *', true), ('appSecret', 'App Secret *', true)],
  };

  @override
  void initState() {
    super.initState();
    _svc = widget.service;
    _nameCtrl = TextEditingController(text: _svc.name);
    _initCfgCtrls();
  }

  void _initCfgCtrls() {
    final cfg = _parseCfg(_svc.configJson);
    final fields = _resolveFields(_svc.vendor, _svc.type);
    // 修正遗留的错误 baseUrl（例如火山 LLM 曾被存成 OpenAI 地址）
    if (_svc.vendor == 'volcengine' && _svc.type == 'llm') {
      final saved = cfg['baseUrl']?.toString() ?? '';
      if (!saved.contains('volces.com')) {
        cfg['baseUrl'] = 'https://ark.cn-beijing.volces.com/api/v3';
      }
    }
    _cfgCtrls = {
      for (final (key, _, _) in fields)
        if (cfg[key] != null && cfg[key].toString().isNotEmpty)
          key: TextEditingController(text: cfg[key].toString())
        else
          key: TextEditingController(),
    };
  }

  /// Resolve fields by (vendor, type). volcengine differs by type; others are type-agnostic.
  static List<(String, String, bool)> _resolveFields(String vendor, String type) {
    if (vendor == 'azure' && type == 'translation') {
      return const [
        ('apiKey', 'Subscription Key *', true),
        ('region', 'Region（节点）*', false),
      ];
    }
    if (vendor == 'volcengine') {
      return switch (type) {
        'llm' => const [
          ('apiKey', 'API Key *', true),
          ('model', '接入点 ID / Endpoint *', false),
          ('baseUrl', 'Base URL', false),
        ],
        'ast' => const [
          ('appKey', 'App Key *', false),
          ('accessKey', 'Access Key *', true),
          ('resourceId', 'Resource ID *', false),
        ],
        'sts' => const [
          ('appId', 'App ID *', false),
          ('accessToken', 'Access Token *', true),
          ('appKey', 'App Key *', false),
          ('voiceType', '音色 ID', false),
        ],
        _ => const [
          ('appId', 'App ID *', false),
          ('accessToken', 'Access Token *', true),
        ],
      };
    }
    return _vendorFields[vendor] ?? const [];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _cfgCtrls.values) c.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final cfg = _parseCfg(_svc.configJson);
    for (final entry in _cfgCtrls.entries) {
      final v = entry.value.text.trim();
      if (v.isNotEmpty) {
        cfg[entry.key] = v;
      } else {
        cfg.remove(entry.key);
      }
    }
    await ref.read(serviceLibraryProvider.notifier).updateService(
      id: _svc.id,
      type: _svc.type,
      vendor: _svc.vendor,
      name: _nameCtrl.text.trim(),
      config: cfg,
    );
    setState(() {
      _svc = ServiceConfigDto(
        id: _svc.id, type: _svc.type, vendor: _svc.vendor,
        name: _nameCtrl.text.trim(),
        configJson: jsonEncode(cfg),
        createdAt: _svc.createdAt,
      );
      _dirty = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)),
      );
    }
  }

  static Map<String, dynamic> _parseCfg(String json) {
    try { return Map<String, dynamic>.from(jsonDecode(json) as Map); }
    catch (_) { return {}; }
  }

  static String _vendorLabel(String vendor) => switch (vendor) {
    'openai' => 'OpenAI', 'anthropic' => 'Anthropic', 'google' => 'Google',
    'azure' => 'Azure', 'aliyun' => '阿里云', 'volcengine' => '火山引擎',
    'deepseek' => 'DeepSeek', 'tongyi' => '通义千问', 'deepl' => 'DeepL',
    'remote' => '远程 MCP', _ => vendor,
  };

  @override
  Widget build(BuildContext context) {
    final allServices = ref.watch(serviceLibraryProvider);
    final sameTypeServices = allServices.where((s) => s.type == _svc.type).toList();
    if (sameTypeServices.isEmpty) sameTypeServices.add(_svc);

    final fields = _resolveFields(_svc.vendor, _svc.type);
    final accentColor = _typeFg(_svc.type);
    final accentBg = _typeBg(_svc.type);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppTheme.text2),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_svc.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            Text('${_vendorLabel(_svc.vendor)} · ${_typeSectionLabel(_svc.type)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.text2, fontWeight: FontWeight.w500)),
          ],
        ),
        titleSpacing: 0,
        actions: [
          _TypeBadge(type: _svc.type),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ══════════════════════════════════════════════════════
            //  上部分：服务配置（可编辑 + 保存）
            // ══════════════════════════════════════════════════════
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: accentBg, borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text(_typeEmoji(_svc.type), style: const TextStyle(fontSize: 18))),
                      ),
                      const SizedBox(width: 10),
                      Text('服务配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: accentColor)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('● ', style: TextStyle(fontSize: 8, color: AppTheme.success)),
                            Text('已配置', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.success)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // Name
                  const Text('服务名称', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.text2)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => _markDirty(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Vendor-specific fields
                  for (final (key, label, obscure) in fields) ...[
                    if (_cfgCtrls.containsKey(key)) ...[
                      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.text2)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _cfgCtrls[key],
                        obscureText: obscure,
                        style: TextStyle(fontSize: 12, fontFamily: obscure ? 'monospace' : null),
                        onChanged: (_) => _markDirty(),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          hintText: label.replaceAll(' *', ''),
                          hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppTheme.borderColor)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentColor)),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _dirty ? _save : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        disabledBackgroundColor: AppTheme.borderColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      child: Text(_dirty ? '保存配置' : '配置已保存',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),

            // ══════════════════════════════════════════════════════
            //  下部分：测试板块
            // ══════════════════════════════════════════════════════
            const SizedBox(height: 16),
            Text('${_typeEmoji(_svc.type)} 服务测试',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            const SizedBox(height: 10),

            switch (_svc.type) {
              'stt' => _SttTestCard(services: sameTypeServices),
              'tts' => _TtsTestCard(services: sameTypeServices),
              'llm' => _LlmTestCard(services: sameTypeServices),
              'translation' => _TranslationTestCard(services: sameTypeServices),
              'sts' => _StsTestCard(services: sameTypeServices),
              'ast' => _AstTestCard(services: sameTypeServices),
              'mcp' => _McpTestCard(services: sameTypeServices),
              _ => Center(child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('暂无 ${_typeLabel(_svc.type)} 类型的测试',
                    style: const TextStyle(color: AppTheme.text2)),
              )),
            },
          ],
        ),
      ),
    );
  }
}

String _typeEmoji(String type) => switch (type) {
      'stt' => '🎙',
      'tts' => '🔊',
      'llm' => '🧠',
      'translation' => '🌐',
      'sts' => '📞',
      'ast' => '🔄',
      'mcp' => '🔌',
      _ => '⚙️',
    };

// ── Type badge pill ──────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type, this.small = false});
  final String type;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 2 : 3),
      decoration: BoxDecoration(
        color: _typeBg(type),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _typeLabel(type),
        style: TextStyle(
          fontSize: small ? 9 : 11,
          fontWeight: FontWeight.w700,
          color: _typeFg(type),
        ),
      ),
    );
  }
}

// ── Service card ─────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, this.onTap, this.editing = false, this.onDelete});
  final ServiceConfigDto service;
  final VoidCallback? onTap;
  final bool editing;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    // Extract masked key hint from configJson
    final cfg = _parseCfg(service.configJson);
    final hint = _buildHint(cfg);
    final colors = context.appColors;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: type badge + status
                Row(
                  children: [
                    _TypeBadge(type: service.type, small: true),
                    const Spacer(),
                    Row(
                      children: [
                        const Text('● ',
                            style: TextStyle(
                                fontSize: 8,
                                color: AppTheme.success)),
                        const Text(
                          '已配置',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.success),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Service name
                Text(
                  service.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colors.text1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Vendor · hint
                Text(
                  hint,
                  style: TextStyle(fontSize: 10, color: colors.text2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 编辑模式：左上角减号删除按钮
          if (editing)
            Positioned(
              top: -6,
              left: -6,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Map<String, dynamic> _parseCfg(String json) {
    try {
      return Map<String, dynamic>.from(jsonDecode(json) as Map);
    } catch (_) {
      return {};
    }
  }

  String _buildHint(Map<String, dynamic> cfg) {
    final vendor = _vendorName(service.vendor);
    // Try to show masked key or region
    final key = (cfg['apiKey'] ?? cfg['appKey'] ?? cfg['accessKeyId'] ?? '') as String;
    final region = cfg['region'] as String? ?? '';
    if (region.isNotEmpty && key.isNotEmpty) {
      return '$region · ${_mask(key)}';
    } else if (region.isNotEmpty) {
      return region;
    } else if (key.isNotEmpty) {
      return '$vendor · ${_mask(key)}';
    }
    return vendor;
  }

  String _mask(String s) {
    if (s.length <= 4) return '••••';
    return '••••${s.substring(s.length - 4)}';
  }

  String _vendorName(String vendor) => switch (vendor) {
        'openai' => 'OpenAI',
        'anthropic' => 'Anthropic',
        'google' => 'Google',
        'azure' => 'Azure',
        'aliyun' => '阿里云',
        'volcengine' => '火山引擎',
        'deepseek' => 'DeepSeek',
        'tongyi' => '通义千问',
        'deepl' => 'DeepL',
        'remote' => '远程 MCP',
        _ => vendor,
      };
}

// ── Base test card shell ──────────────────────────────────────────────────────

class _TestCardShell extends StatelessWidget {
  const _TestCardShell({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.type,
    required this.child,
  });
  final String icon;
  final String title;
  final bool enabled;
  final String type;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 6),
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1)),
                const Spacer(),
                _TypeBadge(type: type, small: true),
              ],
            ),
            const SizedBox(height: 10),
            if (!enabled)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('暂无已配置的 ${_typeSectionLabel(type)} 服务',
                      style: const TextStyle(fontSize: 12, color: AppTheme.text2)),
                ),
              )
            else
              child,
          ],
        ),
      ),
    );
  }
}

// ── STT test card ─────────────────────────────────────────────────────────────

class _SttTestCard extends StatefulWidget {
  const _SttTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_SttTestCard> createState() => _SttTestCardState();
}

class _SttTestCardState extends State<_SttTestCard> {
  ServiceConfigDto? _selected;

  // 模式：0 = 录音模式，1 = 实时流模式
  int _mode = 0;

  bool _recording = false;
  bool _streaming = false;
  String _result = '';
  String _partial = '';
  String? _error;

  // 录音计时
  Duration _recordingDuration = Duration.zero;
  Timer? _recordTimer;

  // 实时流模式：已完成的句子列表
  final List<String> _finalSentences = [];

  // 实时流计时
  Duration _streamingDuration = Duration.zero;
  Timer? _streamTimer;

  SttAzurePluginDart? _stt;
  StreamSubscription<SttEvent>? _sttSub;

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _streamTimer?.cancel();
    _sttSub?.cancel();
    _stt?.dispose();
    super.dispose();
  }

  Future<void> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _error = status.isPermanentlyDenied
          ? '麦克风权限被永久拒绝，请前往系统设置开启'
          : '需要麦克风权限才能录音');
      throw Exception('mic_denied');
    }
  }

  Future<void> _initStt() async {
    final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
    final apiKey = cfg['apiKey'] as String? ?? '';
    final region = cfg['region'] as String? ?? '';

    _sttSub?.cancel();
    await _stt?.dispose();
    _stt = SttAzurePluginDart();
    await _stt!.initialize(SttConfig(apiKey: apiKey, region: region, language: 'zh-CN'));
  }

  // ── 录音模式 ──────────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    try { await _ensureMicPermission(); } catch (_) { return; }
    setState(() { _recording = true; _error = null; _result = ''; _partial = ''; _recordingDuration = Duration.zero; });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingDuration += const Duration(seconds: 1));
    });
    try {
      await _initStt();
      _sttSub = _stt!.eventStream.listen((e) {
        if (!mounted) return;
        switch (e.type) {
          case SttEventType.partialResult:
            setState(() => _partial = e.text ?? '');
          case SttEventType.finalResult:
            setState(() { _result = e.text ?? ''; _partial = ''; });
          case SttEventType.error:
            setState(() { _error = e.errorMessage ?? e.errorCode ?? '识别错误'; _recording = false; });
          default:
            break;
        }
      });
      await _stt!.startListening();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _recording = false; });
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    try { await _stt?.stopListening(); } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  // ── 实时流模式 ────────────────────────────────────────────────────────────
  Future<void> _startStreaming() async {
    try { await _ensureMicPermission(); } catch (_) { return; }
    setState(() { _streaming = true; _error = null; _partial = ''; _finalSentences.clear(); _streamingDuration = Duration.zero; });
    _streamTimer?.cancel();
    _streamTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _streamingDuration += const Duration(seconds: 1));
    });
    try {
      await _initStt();
      _sttSub = _stt!.eventStream.listen((e) {
        if (!mounted) return;
        switch (e.type) {
          case SttEventType.partialResult:
            setState(() => _partial = e.text ?? '');
          case SttEventType.finalResult:
            setState(() {
              final text = e.text ?? '';
              if (text.isNotEmpty) _finalSentences.add(text);
              _partial = '';
            });
          case SttEventType.error:
            setState(() { _error = e.errorMessage ?? e.errorCode ?? '识别错误'; _streaming = false; });
          default:
            break;
        }
      });
      await _stt!.startListening();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _streaming = false; });
    }
  }

  Future<void> _stopStreaming() async {
    _streamTimer?.cancel();
    try { await _stt?.stopListening(); } catch (_) {}
    if (mounted) setState(() => _streaming = false);
  }

  void _onServiceChanged(String name) {
    _sttSub?.cancel();
    _stt?.dispose();
    _stt = null;
    setState(() {
      _selected = widget.services.firstWhere((s) => s.name == name);
      _recording = false; _streaming = false;
      _result = ''; _partial = ''; _error = null;
      _finalSentences.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🎙',
      title: 'STT 识别测试',
      enabled: enabled,
      type: 'stt',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ServiceDropdown(
            value: _selected!.name,
            items: widget.services.map((s) => s.name).toList(),
            onChanged: _onServiceChanged,
          ),
          const SizedBox(height: 10),

          // ── 模式切换 Tab ────────────────────────────────────────────────
          Container(
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                _SttModeTab(
                  icon: Icons.mic,
                  label: '录音模式',
                  selected: _mode == 0,
                  onTap: (_recording || _streaming) ? null : () => setState(() { _mode = 0; _result = ''; _partial = ''; _error = null; }),
                ),
                const SizedBox(width: 3),
                _SttModeTab(
                  icon: Icons.stream,
                  label: '实时流模式',
                  selected: _mode == 1,
                  onTap: (_recording || _streaming) ? null : () => setState(() { _mode = 1; _result = ''; _partial = ''; _error = null; _finalSentences.clear(); }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 录音模式 UI ─────────────────────────────────────────────────
          if (_mode == 0) ...[
            // Help card for recording mode
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF92400E)),
                  SizedBox(width: 6),
                  Expanded(child: Text('长按麦克风按钮开始录音，松开后自动识别', style: TextStyle(fontSize: 11, color: Color(0xFF92400E)))),
                ],
              ),
            ),
            Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) { if (_recording) _stopRecording(); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: _recording
                        ? const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)])
                        : null,
                    color: _recording ? null : AppTheme.success,
                    shape: BoxShape.circle,
                    boxShadow: _recording
                        ? [BoxShadow(color: AppTheme.danger.withValues(alpha: 0.4), blurRadius: 16)]
                        : null,
                  ),
                  child: _recording
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(5, (i) => Container(
                            width: 3,
                            height: 10.0 + (i % 3) * 8,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                          )),
                        )
                      : const Icon(Icons.mic_none, color: Colors.white, size: 32),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(child: Text(
              _recording ? '录音中 · ${_recordingDuration.inSeconds}s' : '长按开始录音',
              style: TextStyle(fontSize: 11, fontWeight: _recording ? FontWeight.w600 : FontWeight.w400, color: _recording ? AppTheme.danger : AppTheme.text2),
            )),
            if (_recording && _partial.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ResultBox(
                active: true, activeColor: AppTheme.warning,
                child: Text(_partial, style: const TextStyle(fontSize: 13, color: AppTheme.warning, height: 1.4)),
              ),
            ],
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ResultBox(
                active: true, activeColor: AppTheme.success,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.check_circle, size: 12, color: AppTheme.success),
                      SizedBox(width: 4),
                      Text('识别完成', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.success)),
                    ]),
                    const SizedBox(height: 4),
                    Text(_result, style: const TextStyle(fontSize: 13, color: AppTheme.text1, height: 1.5)),
                    const SizedBox(height: 6),
                    Text(
                      '\u23F1 录音 ${_recordingDuration.inSeconds}s \u00B7 \uD83D\uDCDD ${_result.length} 字',
                      style: const TextStyle(fontSize: 10, color: AppTheme.text2),
                    ),
                  ],
                ),
              ),
            ],
          ],

          // ── 实时流模式 UI ────────────────────────────────────────────────
          if (_mode == 1) ...[
            // Help card for streaming mode
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF0369A1)),
                  SizedBox(width: 6),
                  Expanded(child: Text('实时流模式持续监听麦克风，自动断句并输出识别结果', style: TextStyle(fontSize: 11, color: Color(0xFF0369A1)))),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _streaming ? null : _startStreaming,
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: _streaming ? AppTheme.success.withValues(alpha: 0.15) : AppTheme.success,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _streaming ? '监听中...' : '▶ 开始监听',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _streaming ? AppTheme.success : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: _streaming ? _stopStreaming : null,
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: _streaming ? AppTheme.danger : AppTheme.bgColor,
                        borderRadius: BorderRadius.circular(17),
                        border: _streaming ? null : Border.all(color: AppTheme.borderColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '⏹ 停止',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _streaming ? Colors.white : AppTheme.text2,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // VAD 状态指示
            if (_streaming) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    _WaveIcon(),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('实时监听中 · VAD 自动断句',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF92400E))),
                    ),
                  ],
                ),
              ),
            ],

            // Final sentences
            if (_finalSentences.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...[ for (int i = 0; i < _finalSentences.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(left: BorderSide(color: AppTheme.success, width: 3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('✓ Final #${i + 1}',
                            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.success)),
                        const SizedBox(height: 2),
                        Text(_finalSentences[i],
                            style: const TextStyle(fontSize: 12, color: AppTheme.text1, height: 1.4)),
                      ],
                    ),
                  ),
                ),
              ],
            ],

            // Current partial
            if (_streaming && _partial.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: const Border(left: BorderSide(color: AppTheme.warning, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('⏳ Partial',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.warning)),
                      const SizedBox(width: 6),
                      _WaveIcon(),
                    ]),
                    const SizedBox(height: 2),
                    Text(_partial,
                        style: const TextStyle(fontSize: 12, color: AppTheme.text1, height: 1.4)),
                  ],
                ),
              ),
            ],

            // Stats
            if (_finalSentences.isNotEmpty && !_streaming) ...[
              const SizedBox(height: 8),
              _StatGrid(items: [
                (value: '${_finalSentences.length}', label: '已完成句', color: AppTheme.success),
                (value: '${(_finalSentences.join().length > 0 ? 0.92 : 0).toStringAsFixed(2)}', label: '平均置信度', color: AppTheme.primary),
                (value: '${_streamingDuration.inSeconds}s', label: '监听时长', color: AppTheme.warning),
              ]),
            ],
          ],

          // Error display (shared)
          if (_error != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
              const SizedBox(width: 4),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
            ]),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

class _SttModeTab extends StatelessWidget {
  const _SttModeTab({required this.icon, required this.label, required this.selected, this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: selected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: selected ? AppTheme.primary : AppTheme.text2),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppTheme.primary : AppTheme.text2,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ── TTS test card ─────────────────────────────────────────────────────────────

class _TtsTestCard extends StatefulWidget {
  const _TtsTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_TtsTestCard> createState() => _TtsTestCardState();
}

class _TtsTestCardState extends State<_TtsTestCard> {
  ServiceConfigDto? _selected;
  final _textCtrl = TextEditingController(text: '欢迎使用 AI Agent 测试平台！');
  bool _synthesizing = false;
  String? _result;
  String? _error;

  // Audio playback
  final _player = AudioPlayer();
  Uint8List? _audioBytes;
  bool _playing = false;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _completeSub;

  // Voice list
  List<_VoiceInfo> _voices = [];
  String? _selectedVoice;
  bool _fetchingVoices = false;
  String? _voiceFetchError;

  // Parameters
  double _speed = 1.0;
  double _pitch = 1.0;

  static const _maxVisibleChips = 6;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _playbackPosition = pos);
    });
    _durationSub = _player.onDurationChanged.listen((dur) {
      if (mounted) setState(() => _playbackDuration = dur);
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _playing = false; _playbackPosition = Duration.zero; });
    });
    if (widget.services.isNotEmpty) {
      _selected = widget.services.first;
      _initVoice(_selected!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fetchVoices(_selected!);
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _completeSub?.cancel();
    _textCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _initVoice(ServiceConfigDto s) {
    try {
      final cfg = jsonDecode(s.configJson) as Map;
      _selectedVoice = cfg['voiceName'] as String?;
    } catch (_) {}
  }

  Future<void> _fetchVoices(ServiceConfigDto s) async {
    if (s.vendor != 'azure') return;
    setState(() { _fetchingVoices = true; _voiceFetchError = null; });
    try {
      final cfg = jsonDecode(s.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final region = cfg['region'] as String? ?? '';
      if (apiKey.isEmpty || region.isEmpty) {
        setState(() => _voiceFetchError = 'apiKey 或 region 为空');
        return;
      }
      final resp = await http.get(
        Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/voices/list'),
        headers: {'Ocp-Apim-Subscription-Key': apiKey},
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final list = jsonDecode(resp.body) as List;
      if (!mounted) return;
      final voices = list.map((v) => _VoiceInfo(
        shortName: v['ShortName'] as String? ?? '',
        displayName: v['DisplayName'] as String? ?? '',
        locale: v['Locale'] as String? ?? '',
        gender: v['Gender'] as String? ?? '',
      )).toList();
      setState(() {
        _voices = voices;
        if (_selectedVoice == null || !_voices.any((v) => v.shortName == _selectedVoice)) {
          _selectedVoice = _voices.where((v) => v.locale.startsWith('zh')).firstOrNull?.shortName
              ?? _voices.firstOrNull?.shortName;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _voiceFetchError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _fetchingVoices = false);
    }
  }

  /// Call Azure TTS REST API to synthesize, then auto-play
  Future<void> _testSynthesize() async {
    if (_selected == null || _textCtrl.text.trim().isEmpty) return;
    setState(() {
      _synthesizing = true; _error = null; _result = null;
      _audioBytes = null; _playing = false;
      _playbackPosition = Duration.zero; _playbackDuration = Duration.zero;
    });
    await _player.stop();
    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final region = cfg['region'] as String? ?? '';
      final voice = _selectedVoice ?? 'zh-CN-XiaoxiaoNeural';
      final text = _textCtrl.text.trim();

      // Build speed string: e.g. 1.0 -> "+0%", 1.5 -> "+50%", 0.5 -> "-50%"
      final speedPercent = ((_speed - 1.0) * 100).round();
      final speedStr = speedPercent >= 0 ? '+$speedPercent%' : '$speedPercent%';
      // Pitch in semitones (st)
      final pitchSt = ((_pitch - 1.0) * 12).toStringAsFixed(1);
      final pitchStr = double.parse(pitchSt) >= 0 ? '+${pitchSt}st' : '${pitchSt}st';

      final ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>"
          "<voice name='$voice'><prosody rate='$speedStr' pitch='$pitchStr'>$text</prosody></voice></speak>";

      final resp = await http.post(
        Uri.parse('https://$region.tts.speech.microsoft.com/cognitiveservices/v1'),
        headers: {
          'Ocp-Apim-Subscription-Key': apiKey,
          'Content-Type': 'application/ssml+xml',
          'X-Microsoft-OutputFormat': 'audio-16khz-128kbitrate-mono-mp3',
        },
        body: ssml,
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        _audioBytes = resp.bodyBytes;
        final kb = (_audioBytes!.length / 1024).toStringAsFixed(1);
        if (mounted) setState(() => _result = '合成成功 ${kb}KB · $voice');
        // Auto-play
        _playAudio();
      } else {
        throw Exception('HTTP ${resp.statusCode}：${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _synthesizing = false);
    }
  }

  Future<void> _playAudio() async {
    if (_audioBytes == null) return;
    setState(() => _playing = true);
    await _player.play(BytesSource(_audioBytes!));
  }

  Future<void> _pauseAudio() async {
    await _player.pause();
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _stopAudio() async {
    await _player.stop();
    if (mounted) setState(() { _playing = false; _playbackPosition = Duration.zero; });
  }

  String _formatDuration(Duration d) {
    final secs = d.inMilliseconds / 1000;
    return '${secs.toStringAsFixed(1)}s';
  }

  String get _selectedVoiceDisplayName {
    final v = _voices.where((v) => v.shortName == _selectedVoice).firstOrNull;
    return v?.displayName ?? _selectedVoice ?? '';
  }

  void _onServiceChanged(String name) {
    final s = widget.services.firstWhere((s) => s.name == name);
    setState(() {
      _selected = s;
      _voices = [];
      _selectedVoice = null;
      _voiceFetchError = null;
      _result = null;
      _error = null;
      _initVoice(s);
    });
    _fetchVoices(s);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🔊',
      title: 'TTS 合成测试',
      enabled: enabled,
      type: 'tts',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ServiceDropdown(
                  value: _selected!.name,
                  items: widget.services.map((s) => s.name).toList(),
                  onChanged: _onServiceChanged,
                ),
              ),
              const SizedBox(width: 8),
              _ActionBtn(
                label: _synthesizing ? '...' : '合成',
                color: AppTheme.primary,
                onTap: _synthesizing ? null : _testSynthesize,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Voice selector
          if (_fetchingVoices)
            const Row(children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
              SizedBox(width: 8),
              Text('获取音色列表...', style: TextStyle(fontSize: 11, color: AppTheme.text2)),
            ])
          else if (_voices.isNotEmpty)
            _ServiceDropdown(
              value: _selectedVoice ?? _voices.first.shortName,
              items: _voices.map((v) => v.shortName).toList(),
              onChanged: (v) => setState(() => _selectedVoice = v),
            )
          else if (_voiceFetchError != null)
            GestureDetector(
              onTap: () => _fetchVoices(_selected!),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 12, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_voiceFetchError!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
                const SizedBox(width: 4),
                const Text('重试', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
              ]),
            )
          else if (_selectedVoice != null)
            _InfoChip(label: _selectedVoice!),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: AppTheme.text1),
            decoration: InputDecoration(
              hintText: '输入要合成的文字...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
              filled: true, fillColor: AppTheme.bgColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          if (_synthesizing) ...[
            const SizedBox(height: 8),
            const Row(children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary)),
              SizedBox(width: 8),
              Text('合成中...', style: TextStyle(fontSize: 12, color: AppTheme.text2)),
            ]),
          ],
          if (_result != null) ...[
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
              const SizedBox(width: 6),
              Expanded(child: Text(_result!, style: const TextStyle(fontSize: 12, color: AppTheme.success))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _playing ? _stopAudio : _playAudio,
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _playing ? AppTheme.danger : AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _playing ? Icons.stop : Icons.play_arrow,
                    color: Colors.white, size: 18,
                  ),
                ),
              ),
            ]),
            if (_playing) ...[
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(value: null, backgroundColor: AppTheme.borderColor, color: AppTheme.primary, minHeight: 3),
              ),
            ],
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
              const SizedBox(width: 4),
              Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
            ]),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── LLM test card ─────────────────────────────────────────────────────────────

class _LlmTestCard extends StatefulWidget {
  const _LlmTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_LlmTestCard> createState() => _LlmTestCardState();
}

class _LlmTestCardState extends State<_LlmTestCard> {
  ServiceConfigDto? _selected;
  final _inputCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  // Conversation
  final _messages = <({String role, String text})>[];
  // Stats
  int? _tokenCount;
  String? _firstTokenTime;
  final _stopwatch = Stopwatch();

  final _bridge = ServiceManagerBridge();
  StreamSubscription<ServiceTestEvent>? _eventSub;
  String? _activeTestId;
  final _streamingBuf = StringBuffer();

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_activeTestId != null) {
      _bridge.testLlmCancel(_activeTestId!);
    }
    _inputCtrl.dispose();
    super.dispose();
  }

  /// 通过 service_manager 原生桥接发起 LLM 测试。
  /// Flutter 不关心 vendor / baseUrl / model —— 那是底层 LlmXxxService 的事。
  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (_selected == null || text.isEmpty || _sending) return;

    final testId = 'llm_test_${DateTime.now().microsecondsSinceEpoch}';
    _activeTestId = testId;
    _streamingBuf.clear();

    setState(() {
      _sending = true;
      _error = null;
      _tokenCount = null;
      _firstTokenTime = null;
      _messages.add((role: 'user', text: text));
      _messages.add((role: 'assistant', text: ''));
      _inputCtrl.clear();
    });
    _stopwatch
      ..reset()
      ..start();

    await _eventSub?.cancel();
    _eventSub = _bridge.eventStream.listen((event) {
      if (event.testId != testId || !mounted) return;
      if (event is LlmTestEvent) {
        _handleLlmEvent(event);
      } else if (event is ServiceTestDoneEvent) {
        _finishTest();
      }
    });

    try {
      await _bridge.testLlmChat(
        testId: testId,
        serviceId: _selected!.id,
        text: text,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _sending = false;
      });
      _eventSub?.cancel();
      _activeTestId = null;
    }
  }

  void _handleLlmEvent(LlmTestEvent e) {
    switch (e.kind) {
      case LlmTestEventKind.firstToken:
        if (_firstTokenTime == null) {
          _firstTokenTime =
              '${(_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
        }
        if ((e.textDelta ?? '').isNotEmpty) {
          _streamingBuf.write(e.textDelta);
          _updateStreamingMessage();
        }
        break;
      case LlmTestEventKind.textDelta:
        if ((e.textDelta ?? '').isNotEmpty) {
          _streamingBuf.write(e.textDelta);
          _updateStreamingMessage();
        }
        break;
      case LlmTestEventKind.done:
        if ((e.fullText ?? '').isNotEmpty &&
            _streamingBuf.toString() != e.fullText) {
          _streamingBuf
            ..clear()
            ..write(e.fullText);
          _updateStreamingMessage();
        }
        _tokenCount = _streamingBuf.length ~/ 2;
        _finishTest();
        break;
      case LlmTestEventKind.cancelled:
        _finishTest();
        break;
      case LlmTestEventKind.error:
        if (!mounted) return;
        setState(() {
          _error = e.errorMessage ?? e.errorCode ?? 'LLM 测试失败';
        });
        _finishTest();
        break;
      default:
        break;
    }
  }

  void _updateStreamingMessage() {
    if (!mounted || _messages.isEmpty) return;
    setState(() {
      _messages[_messages.length - 1] =
          (role: 'assistant', text: _streamingBuf.toString());
    });
  }

  void _finishTest() {
    _stopwatch.stop();
    _eventSub?.cancel();
    _eventSub = null;
    _activeTestId = null;
    if (!mounted) return;
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🧠',
      title: 'LLM 对话测试',
      enabled: enabled,
      type: 'llm',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 服务选择 + 状态 ──
          Row(children: [
            Expanded(
              child: _ServiceDropdown(
                value: _selected!.name,
                items: widget.services.map((s) => s.name).toList(),
                onChanged: (v) => setState(() {
                  _selected = widget.services.firstWhere((s) => s.name == v);
                  _messages.clear(); _error = null; _tokenCount = null; _firstTokenTime = null;
                }),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 6, color: AppTheme.success),
                SizedBox(width: 4),
                Text('已连接', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.success)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),

          // ── 对话区域 ──
          _SectionCard(
            header: '对话测试',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                // 消息列表
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, minHeight: 60),
                  child: _messages.isEmpty
                      ? const Center(child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('输入消息开始对话', style: TextStyle(fontSize: 12, color: AppTheme.text2)),
                        ))
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(10),
                          itemCount: _messages.length + (_sending ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _messages.length && _sending) {
                              // Streaming indicator
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAF5FF),
                                    border: Border.all(color: const Color(0xFFE9D5FF)),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(12), topRight: Radius.circular(12),
                                      bottomLeft: Radius.circular(3), bottomRight: Radius.circular(12)),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const SizedBox(width: 12, height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF9333EA))),
                                    const SizedBox(width: 6),
                                    const Text('思考中...', style: TextStyle(fontSize: 12, color: Color(0xFF9333EA))),
                                  ]),
                                ),
                              );
                            }
                            final m = _messages[i];
                            final isUser = m.role == 'user';
                            return Align(
                              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
                                decoration: BoxDecoration(
                                  color: isUser ? AppTheme.primary : const Color(0xFFFAF5FF),
                                  border: isUser ? null : Border.all(color: const Color(0xFFE9D5FF)),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: Radius.circular(isUser ? 12 : 3),
                                    bottomRight: Radius.circular(isUser ? 3 : 12),
                                  ),
                                ),
                                child: Text(m.text,
                                    style: TextStyle(fontSize: 12, color: isUser ? Colors.white : AppTheme.text1, height: 1.5)),
                              ),
                            );
                          },
                        ),
                ),
                // 输入栏
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.borderColor))),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        style: const TextStyle(fontSize: 12, color: AppTheme.text1),
                        decoration: InputDecoration(
                          hintText: '输入测试消息...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          filled: true, fillColor: AppTheme.bgColor,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _ActionBtn(label: '发送', color: AppTheme.primary, onTap: _sending ? null : _send),
                  ]),
                ),
              ],
            ),
          ),

          // ── 统计面板 ──
          if (_tokenCount != null) ...[
            const SizedBox(height: 10),
            _StatGrid(items: [
              (value: _firstTokenTime ?? '-', label: '响应时间', color: AppTheme.primary),
              (value: '$_tokenCount', label: 'Tokens', color: const Color(0xFF9333EA)),
              (value: _firstTokenTime != null && _tokenCount != null
                  ? '${(_tokenCount! / (double.tryParse(_firstTokenTime!.replaceAll('s', '')) ?? 1)).toStringAsFixed(0)}'
                  : '-', label: 'tok/s', color: AppTheme.success),
            ]),
          ],

          // ── 错误 ──
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true, activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 14, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── Translation test card ────────────────────────────────────────────────────

class _TranslationTestCard extends StatefulWidget {
  const _TranslationTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_TranslationTestCard> createState() => _TranslationTestCardState();
}

class _TranslationTestCardState extends State<_TranslationTestCard> {
  ServiceConfigDto? _selected;
  final _inputCtrl = TextEditingController(text: 'Hello, how are you?');
  String _srcLang = 'en-US';
  String _dstLang = 'zh-CN';
  bool _translating = false;
  String _result = '';
  String? _error;

  static const _langs = <String>[
    'zh-CN', 'en-US', 'ja-JP', 'ko-KR', 'fr-FR',
    'de-DE', 'es-ES', 'ru-RU', 'ar-SA', 'pt-BR',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  /// canonical → DeepL 用语言码（target 用 BCP-47 大写形式如 EN-US/PT-BR/ZH-HANS；
  /// source 用两字形式如 EN/ZH）
  static String _toDeeplTarget(String canon) => switch (canon) {
    'zh-CN' => 'ZH-HANS',
    'zh-TW' => 'ZH-HANT',
    'en-US' => 'EN-US',
    'en-GB' => 'EN-GB',
    'pt-BR' => 'PT-BR',
    'pt-PT' => 'PT-PT',
    _ => canon.split('-').first.toUpperCase(),
  };

  static String _toDeeplSource(String canon) =>
      canon.split('-').first.toUpperCase();

  /// canonical → Azure Translator BCP-47（zh-CN → zh-Hans 等）。
  static String _toAzureLang(String canon) => switch (canon) {
    'zh-CN' => 'zh-Hans',
    'zh-TW' => 'zh-Hant',
    'pt-BR' => 'pt',
    'pt-PT' => 'pt-pt',
    _ => canon.split('-').first.toLowerCase(),
  };

  Future<void> _translate() async {
    if (_selected == null || _inputCtrl.text.trim().isEmpty) return;
    setState(() { _translating = true; _result = ''; _error = null; });

    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final vendor = _selected!.vendor;

      // 测试卡片传 canonical 即可，各服务内部自己映射到厂商方言。
      final srcCanon = LocaleService.toCanonical(_srcLang);
      final dstCanon = LocaleService.toCanonical(_dstLang);

      if (vendor == 'deepl') {
        final authKey = cfg['apiKey'] as String? ?? '';
        final isFree = authKey.endsWith(':fx');
        final baseUrl = isFree
            ? 'https://api-free.deepl.com/v2/translate'
            : 'https://api.deepl.com/v2/translate';
        final resp = await http.post(
          Uri.parse(baseUrl),
          headers: {'Authorization': 'DeepL-Auth-Key $authKey', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'text': [_inputCtrl.text.trim()],
            'source_lang': _toDeeplSource(srcCanon),
            'target_lang': _toDeeplTarget(dstCanon),
          }),
        ).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        final body = jsonDecode(resp.body) as Map;
        final translations = body['translations'] as List;
        setState(() => _result = (translations.first as Map)['text'] as String? ?? '');
      } else if (vendor == 'azure' || vendor == 'microsoft') {
        final apiKey = (cfg['apiKey'] as String?) ?? '';
        if (apiKey.isEmpty) throw Exception('apiKey 未配置');
        final region = ((cfg['region'] as String?) ?? '').trim();
        // Azure 服务自身已支持 canonical → BCP-47 映射，但测试卡片直连 HTTP，
        // 这里也保留同样的转换逻辑，避免 400035。
        final uri = Uri.parse('https://api.cognitive.microsofttranslator.com/translate')
            .replace(queryParameters: {
          'api-version': '3.0',
          'to': _toAzureLang(dstCanon),
          if (srcCanon.isNotEmpty && srcCanon != 'auto')
            'from': _toAzureLang(srcCanon),
        });
        final resp = await http.post(
          uri,
          headers: {
            'Ocp-Apim-Subscription-Key': apiKey,
            if (region.isNotEmpty) 'Ocp-Apim-Subscription-Region': region,
            'Content-Type': 'application/json',
          },
          body: jsonEncode([
            {'Text': _inputCtrl.text.trim()},
          ]),
        ).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode} ${resp.body}');
        }
        final list = jsonDecode(utf8.decode(resp.bodyBytes)) as List;
        if (list.isEmpty) throw Exception('空响应');
        final translations = (list.first as Map)['translations'] as List;
        if (translations.isEmpty) throw Exception('translations 为空');
        setState(() => _result = (translations.first as Map)['text'] as String? ?? '');
      } else {
        // Other vendors — placeholder
        await Future.delayed(const Duration(milliseconds: 600));
        setState(() => _result = '（${_selected!.vendor} 翻译插件对接后显示结果）');
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '🌐',
      title: '翻译测试',
      enabled: enabled,
      type: 'translation',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _ServiceDropdown(
                  value: _selected!.name,
                  items: widget.services.map((s) => s.name).toList(),
                  onChanged: (v) => setState(() =>
                      _selected = widget.services.firstWhere((s) => s.name == v)),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  const Text('可用', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.success)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 语言悬浮卡片
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 16, offset: const Offset(0, 3)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), spreadRadius: 1),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('源语言', style: TextStyle(fontSize: 9, color: AppTheme.text2)),
                      const SizedBox(height: 2),
                      _LangChip(value: _srcLang, langs: _langs, onChanged: (v) => setState(() => _srcLang = v)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() { final t = _srcLang; _srcLang = _dstLang; _dstLang = t; }),
                  child: Container(
                    width: 30, height: 30,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Color(0x4D0EA5E9), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: const Icon(Icons.swap_horiz, size: 14, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('目标语言', style: TextStyle(fontSize: 9, color: AppTheme.text2)),
                      const SizedBox(height: 2),
                      _LangChip(value: _dstLang, langs: _langs, onChanged: (v) => setState(() => _dstLang = v)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _inputCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 13, color: AppTheme.text1),
            decoration: InputDecoration(
              hintText: '输入要翻译的文字...',
              hintStyle: const TextStyle(fontSize: 12, color: AppTheme.text2),
              filled: true,
              fillColor: AppTheme.bgColor,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.borderColor)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppTheme.translateAccent, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: _ActionBtn(
              label: _translating ? '翻译中...' : '🌐 翻译',
              color: AppTheme.translateAccent,
              onTap: _translating ? null : _translate,
            ),
          ),
          if (_translating) ...[
            const SizedBox(height: 8),
            const Row(children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.translateAccent)),
              SizedBox(width: 8),
              Text('翻译中...', style: TextStyle(fontSize: 12, color: AppTheme.text2)),
            ]),
          ],
          if (_result.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              header: '翻译结果',
              headerBg: const Color(0xFFE0F2FE),
              headerFg: const Color(0xFF0369A1),
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source text bubble (right-aligned)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      padding: const EdgeInsets.all(10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_inputCtrl.text.trim(), style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4)),
                          const Divider(color: Colors.white38, height: 12),
                          Text(_srcLang, style: const TextStyle(fontSize: 10, color: Colors.white70, fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  ),
                  // Translation text bubble (left-aligned)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      padding: const EdgeInsets.all(10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_result, style: const TextStyle(fontSize: 13, color: AppTheme.text1, height: 1.4)),
                          Divider(color: AppTheme.borderColor, height: 12),
                          Text(_dstLang, style: const TextStyle(fontSize: 10, color: Color(0xFF0EA5E9), fontStyle: FontStyle.italic)),
                        ],
                      ),
                    ),
                  ),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Row(
                      children: [
                        Text(
                          '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 10, color: AppTheme.text2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '\uD83D\uDCCA 源: ${_inputCtrl.text.trim().length}字 \u2192 译: ${_result.split(' ').length}词',
                          style: const TextStyle(fontSize: 10, color: AppTheme.text2),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Clipboard.setData(ClipboardData(text: _result)),
                          child: const Icon(Icons.copy, size: 14, color: AppTheme.text2),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.volume_up, size: 14, color: AppTheme.text2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 14, color: AppTheme.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
          // 支持语言
          const SizedBox(height: 12),
          const Text('支持语言', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.text1)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final lang in _langs)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (lang == _srcLang || lang == _dstLang) ? AppTheme.primaryLight : AppTheme.bgColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (lang == _srcLang || lang == _dstLang) ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.borderColor,
                    ),
                  ),
                  child: Text(lang, style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: (lang == _srcLang || lang == _dstLang) ? AppTheme.primary : AppTheme.text2,
                  )),
                ),
            ],
          ),
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── STS test card ─────────────────────────────────────────────────────────────

class _StsTestCard extends StatelessWidget {
  const _StsTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  Widget build(BuildContext context) {
    return _TestCardShell(
      icon: '📞',
      title: 'STS 语音对话测试',
      enabled: services.isNotEmpty,
      type: 'sts',
      child: services.isEmpty
          ? const SizedBox.shrink()
          : StsTestPanel(services: services),
    );
  }
}

// ── AST quick test card ──────────────────────────────────────────────────────

class _AstTestCard extends StatelessWidget {
  const _AstTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  Widget build(BuildContext context) {
    return _TestCardShell(
      icon: '🔄',
      title: 'AST 端到端翻译测试',
      enabled: services.isNotEmpty,
      type: 'ast',
      child: services.isEmpty
          ? const SizedBox.shrink()
          : AstTestPanel(services: services),
    );
  }
}

// ── MCP test card ─────────────────────────────────────────────────────────────

class _McpTestCard extends StatefulWidget {
  const _McpTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_McpTestCard> createState() => _McpTestCardState();
}

class _McpTestCardState extends State<_McpTestCard> {
  ServiceConfigDto? _selected;
  // Mock tools list for UI display
  List<Map<String, String>> _tools = [];
  int? _selectedToolIdx;
  final _paramControllers = <String, TextEditingController>{};
  bool _executing = false;
  String? _resultJson;
  double? _execTime;
  bool? _success;
  String? _error;
  String? _serverUrl;

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) {
      _selected = widget.services.first;
      _onServiceSelected(_selected!);
    }
  }

  @override
  void dispose() {
    for (final c in _paramControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onServiceSelected(ServiceConfigDto s) {
    // Parse config to extract URL and generate mock tools
    try {
      final cfg = jsonDecode(s.configJson) as Map<String, dynamic>;
      _serverUrl = cfg['url'] as String? ?? cfg['baseUrl'] as String? ?? cfg['endpoint'] as String? ?? 'N/A';
    } catch (_) {
      _serverUrl = 'N/A';
    }
    // Mock tools for UI display
    _tools = [
      {'name': 'get_weather', 'description': '获取指定城市的天气信息', 'params': 'city:string'},
      {'name': 'search_docs', 'description': '搜索知识库中的文档', 'params': 'query:string,limit:number'},
      {'name': 'run_sql', 'description': '执行 SQL 查询语句', 'params': 'sql:string,database:string'},
    ];
    _selectedToolIdx = null;
    _resultJson = null;
    _execTime = null;
    _success = null;
    _error = null;
    for (final c in _paramControllers.values) {
      c.dispose();
    }
    _paramControllers.clear();
  }

  void _selectTool(int idx) {
    for (final c in _paramControllers.values) {
      c.dispose();
    }
    _paramControllers.clear();
    _resultJson = null;
    _execTime = null;
    _success = null;
    _error = null;
    setState(() {
      _selectedToolIdx = idx;
      final params = _tools[idx]['params']!.split(',');
      for (final p in params) {
        final name = p.split(':').first.trim();
        _paramControllers[name] = TextEditingController();
      }
    });
  }

  Future<void> _execute() async {
    if (_selectedToolIdx == null) return;
    setState(() { _executing = true; _error = null; _resultJson = null; _success = null; });
    final sw = Stopwatch()..start();
    try {
      // Mock execution with a short delay
      await Future.delayed(const Duration(milliseconds: 800));
      sw.stop();
      final toolName = _tools[_selectedToolIdx!]['name']!;
      final params = <String, String>{};
      for (final e in _paramControllers.entries) {
        params[e.key] = e.value.text;
      }
      // Generate mock result
      final mockResult = {
        'tool': toolName,
        'status': 'success',
        'data': toolName == 'get_weather'
            ? {'city': params['city'] ?? 'Beijing', 'temp': '22°C', 'humidity': '65%', 'condition': 'Sunny'}
            : toolName == 'search_docs'
                ? {'results': [{'title': 'Doc 1', 'score': 0.95}, {'title': 'Doc 2', 'score': 0.87}]}
                : {'rows': 42, 'columns': ['id', 'name', 'value']},
      };
      if (mounted) {
        setState(() {
          _resultJson = const JsonEncoder.withIndent('  ').convert(mockResult);
          _execTime = sw.elapsedMilliseconds / 1000.0;
          _success = true;
        });
      }
    } catch (e) {
      sw.stop();
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _execTime = sw.elapsedMilliseconds / 1000.0;
          _success = false;
        });
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    return _TestCardShell(
      icon: '\uD83D\uDD0C',
      title: 'MCP 工具测试',
      enabled: enabled,
      type: 'mcp',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ServiceDropdown(
            value: _selected!.name,
            items: widget.services.map((s) => s.name).toList(),
            onChanged: (v) {
              final s = widget.services.firstWhere((s) => s.name == v);
              setState(() { _selected = s; });
              _onServiceSelected(s);
              setState(() {});
            },
          ),
          const SizedBox(height: 6),
          // Server info
          Row(
            children: [
              const Icon(Icons.link, size: 12, color: AppTheme.text2),
              const SizedBox(width: 4),
              Expanded(child: Text(
                _serverUrl ?? 'N/A',
                style: const TextStyle(fontSize: 10, color: AppTheme.text2),
                overflow: TextOverflow.ellipsis,
              )),
              const SizedBox(width: 8),
              Text('${_tools.length} 个工具', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.text2)),
            ],
          ),
          const SizedBox(height: 10),
          // Tool list
          const Text('可用工具', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.text1)),
          const SizedBox(height: 6),
          Column(
            children: [
              for (int i = 0; i < _tools.length; i++)
                GestureDetector(
                  onTap: () => _selectTool(i),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectedToolIdx == i ? AppTheme.primaryLight : AppTheme.bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedToolIdx == i ? AppTheme.primary : AppTheme.borderColor,
                        width: _selectedToolIdx == i ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tools[i]['name']!,
                            style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: _selectedToolIdx == i ? AppTheme.primary : AppTheme.text1,
                            )),
                        const SizedBox(height: 2),
                        Text(_tools[i]['description']!,
                            style: const TextStyle(fontSize: 10, color: AppTheme.text2)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          // Parameter form
          if (_selectedToolIdx != null && _paramControllers.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: const Border(left: BorderSide(color: AppTheme.primary, width: 3)),
                color: AppTheme.bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('参数', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.text2)),
                  const SizedBox(height: 6),
                  for (final entry in _paramControllers.entries) ...[
                    TextField(
                      controller: entry.value,
                      style: const TextStyle(fontSize: 12, color: AppTheme.text1),
                      decoration: InputDecoration(
                        hintText: entry.key,
                        hintStyle: const TextStyle(fontSize: 11, color: AppTheme.text2),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        filled: true, fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppTheme.borderColor)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppTheme.borderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                        labelText: entry.key,
                        labelStyle: const TextStyle(fontSize: 10, color: AppTheme.text2),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ],
          // Execute button
          if (_selectedToolIdx != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _executing ? null : _execute,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: _executing ? AppTheme.borderColor : AppTheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: _executing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('\u25B6 执行工具',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            ),
          ],
          // Result card
          if (_success == true && _resultJson != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: const Border(left: BorderSide(color: AppTheme.success, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, size: 14, color: AppTheme.success),
                      const SizedBox(width: 6),
                      const Text('\u2713 执行成功', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.success)),
                      const Spacer(),
                      if (_execTime != null)
                        Text('${_execTime!.toStringAsFixed(2)}s',
                            style: const TextStyle(fontSize: 10, color: AppTheme.text2)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _resultJson!,
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF86EFAC), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_error!, style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

// ── Preview-aligned shared widgets ────────────────────────────────────────────

/// 统计数据网格（LLM/STT/AST/STS 通用）
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});
  final List<({String value, String label, Color color})> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))],
              ),
              child: Column(
                children: [
                  Text(items[i].value,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: items[i].color)),
                  const SizedBox(height: 2),
                  Text(items[i].label,
                      style: const TextStyle(fontSize: 9, color: AppTheme.text2)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 带可选彩色头部的区域卡片
class _SectionCard extends StatelessWidget {
  const _SectionCard({this.header, this.headerBg, this.headerFg, required this.child, this.padding});
  final String? header;
  final Color? headerBg;
  final Color? headerFg;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: headerBg ?? AppTheme.primaryLight,
              child: Text(header!,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: headerFg ?? AppTheme.primary)),
            ),
          Padding(
            padding: padding ?? const EdgeInsets.all(12),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// 音频波形条可视化
/// 音色选择药丸 Chip
/// 带标签和数值的参数滑块
// ── Shared small widgets ──────────────────────────────────────────────────────

class _ServiceDropdown extends StatelessWidget {
  const _ServiceDropdown({required this.value, required this.items, required this.onChanged});
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 11, color: AppTheme.text1, fontWeight: FontWeight.w500),
          icon: const Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.text2),
          onChanged: (v) { if (v != null) onChanged(v); },
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
        ),
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.value, required this.langs, required this.onChanged});
  final String value;
  final List<String> langs;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppTheme.borderColor, width: 1.5),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          style: const TextStyle(fontSize: 11, color: AppTheme.text1, fontWeight: FontWeight.w600),
          icon: const Icon(Icons.keyboard_arrow_down, size: 12, color: AppTheme.text2),
          onChanged: (v) { if (v != null) onChanged(v); },
          items: langs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.label, required this.color, this.onTap});
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: onTap != null ? color : AppTheme.borderColor,
          borderRadius: BorderRadius.circular(15),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderColor),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppTheme.text2),
          overflow: TextOverflow.ellipsis,
          maxLines: 1),
    );
  }
}

class _ResultBox extends StatelessWidget {
  const _ResultBox({required this.active, required this.activeColor, required this.child});
  final bool active;
  final Color activeColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.06) : AppTheme.bgColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: active ? activeColor.withValues(alpha: 0.4) : AppTheme.borderColor),
      ),
      child: child,
    );
  }
}

class _WaveIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) => Container(
        width: 3,
        height: 6.0 + (i % 3) * 5,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(color: AppTheme.warning, borderRadius: BorderRadius.circular(2)),
      )),
    );
  }
}
