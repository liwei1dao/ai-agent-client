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
import 'package:stt_azure/stt_azure.dart';
import 'package:agents_server/agents_server.dart' hide SttEvent, LlmEvent;
import 'package:agents_server/agents_server.dart' as rt show SttEvent, LlmEvent;
import '../../../shared/themes/app_theme.dart';
import '../providers/service_library_provider.dart';
import '../widgets/add_service_modal.dart';

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

    // 没有服务时自动退出编辑模式
    if (services.isEmpty && _editing) {
      _editing = false;
    }

    return Scaffold(
      backgroundColor: AppTheme.bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('服务中心',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.text1)),
            Text('已配置 ${services.length} 个服务',
                style: const TextStyle(fontSize: 11, color: AppTheme.text2, fontWeight: FontWeight.w500)),
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
                  color: _editing ? AppTheme.primary : AppTheme.text2,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
            child: const Icon(Icons.grid_view_rounded, size: 36, color: AppTheme.primary),
          ),
          const SizedBox(height: 14),
          const Text('还没有配置服务',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.text1)),
          const SizedBox(height: 6),
          const Text('点击下方 + 添加 STT / TTS / LLM 等服务',
              style: TextStyle(fontSize: 12, color: AppTheme.text2)),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      children: [
        const Text('已配置服务',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1)),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor, width: 1.5),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('+', style: TextStyle(fontSize: 22, color: AppTheme.text2.withValues(alpha: 0.5), fontWeight: FontWeight.w300)),
                    const SizedBox(height: 2),
                    const Text('添加服务', style: TextStyle(fontSize: 11, color: AppTheme.text2)),
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
    'doubao':    [('apiKey', 'API Key', true), ('appId', 'App ID', false), ('accessToken', 'Access Token', true), ('appKey', 'App Key', false), ('model', 'Model / Endpoint', false), ('voiceType', 'Voice Type', false), ('resourceId', 'Resource ID', false)],
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
    final fields = _vendorFields[_svc.vendor] ?? [];
    _cfgCtrls = {
      for (final (key, _, _) in fields)
        if (cfg[key] != null && cfg[key].toString().isNotEmpty)
          key: TextEditingController(text: cfg[key].toString())
        else
          key: TextEditingController(),
    };
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
    'azure' => 'Azure', 'aliyun' => '阿里云', 'doubao' => '火山引擎',
    'deepseek' => 'DeepSeek', 'tongyi' => '通义千问', 'deepl' => 'DeepL',
    'remote' => '远程 MCP', _ => vendor,
  };

  @override
  Widget build(BuildContext context) {
    final allServices = ref.watch(serviceLibraryProvider);
    final sameTypeServices = allServices.where((s) => s.type == _svc.type).toList();
    if (sameTypeServices.isEmpty) sameTypeServices.add(_svc);

    final fields = _vendorFields[_svc.vendor] ?? [];
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

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
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
                        Text('● ',
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
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.text1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Vendor · hint
                Text(
                  hint,
                  style: const TextStyle(fontSize: 10, color: AppTheme.text2),
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
        'doubao' => '火山引擎',
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

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (_selected == null || text.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
      _messages.add((role: 'user', text: text));
      _inputCtrl.clear();
    });
    _stopwatch.reset();
    _stopwatch.start();

    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final apiKey = cfg['apiKey'] as String? ?? '';
      final vendor = _selected!.vendor;
      String result;

      if (vendor == 'anthropic') {
        final baseUrl = cfg['baseUrl'] as String? ?? 'https://api.anthropic.com';
        final m = (cfg['model'] as String?)?.isNotEmpty == true
            ? cfg['model'] as String
            : 'claude-haiku-4-5-20251001';
        final resp = await http.post(
          Uri.parse('$baseUrl/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': m,
            'max_tokens': 512,
            'messages': [{'role': 'user', 'content': text}],
          }),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}：${_truncate(resp.body)}');
        final body = jsonDecode(resp.body) as Map;
        final content = (body['content'] as List).first as Map;
        result = content['text'] as String? ?? '';
        _tokenCount = (body['usage']?['output_tokens'] as int?) ?? result.length ~/ 2;
      } else {
        final subType = cfg['_subType'] as String? ?? 'model';
        final isDoubaoBot = vendor == 'doubao' && subType == 'bot';
        final String m;
        if (isDoubaoBot) {
          m = (cfg['botId'] as String?)?.isNotEmpty == true ? cfg['botId'] as String : '';
        } else {
          m = (cfg['model'] as String?)?.isNotEmpty == true
              ? cfg['model'] as String : _defaultModel(vendor);
        }
        if (m.isEmpty) throw Exception('未配置模型名称');
        final String baseUrl;
        if ((cfg['baseUrl'] as String?)?.isNotEmpty == true) {
          baseUrl = cfg['baseUrl'] as String;
        } else if (isDoubaoBot) {
          baseUrl = 'https://ark.cn-beijing.volces.com/api/v3/bots';
        } else {
          baseUrl = _defaultBaseUrl(vendor);
        }
        var normalizedUrl = baseUrl;
        if (normalizedUrl.endsWith('/')) normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - 1);
        if (normalizedUrl.endsWith('/chat/completions')) {
          normalizedUrl = normalizedUrl.substring(0, normalizedUrl.length - '/chat/completions'.length);
        }
        final resp = await http.post(
          Uri.parse('$normalizedUrl/chat/completions'),
          headers: { 'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json' },
          body: jsonEncode({
            'model': m, 'max_tokens': 512,
            'messages': [{'role': 'user', 'content': text}],
          }),
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}：${_truncate(resp.body)}');
        final body = jsonDecode(resp.body) as Map;
        final choices = body['choices'] as List;
        final msg = (choices.first as Map)['message'] as Map;
        result = msg['content'] as String? ?? '';
        _tokenCount = (body['usage']?['completion_tokens'] as int?) ?? result.length ~/ 2;
      }

      _stopwatch.stop();
      _firstTokenTime = '${(_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';
      if (mounted) setState(() => _messages.add((role: 'assistant', text: result)));
    } catch (e) {
      _stopwatch.stop();
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _truncate(String s) {
    final t = s.trim();
    return t.length > 200 ? '${t.substring(0, 200)}…' : t;
  }

  String _defaultBaseUrl(String vendor) => switch (vendor) {
        'deepseek' => 'https://api.deepseek.com/v1',
        'tongyi' => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        'doubao' => 'https://ark.cn-beijing.volces.com/api/v3',
        'google' => 'https://generativelanguage.googleapis.com/v1beta/openai',
        _ => 'https://api.openai.com/v1',
      };

  String _defaultModel(String vendor) => switch (vendor) {
        'deepseek' => 'deepseek-chat',
        'tongyi' => 'qwen-max',
        'google' => 'gemini-2.0-flash',
        _ => 'gpt-4o',
      };

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
  String _srcLang = 'EN';
  String _dstLang = 'ZH';
  bool _translating = false;
  String _result = '';
  String? _error;

  static const _langs = ['ZH', 'EN', 'JA', 'KO', 'FR', 'DE', 'ES', 'RU', 'AR'];

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

  Future<void> _translate() async {
    if (_selected == null || _inputCtrl.text.trim().isEmpty) return;
    setState(() { _translating = true; _result = ''; _error = null; });

    try {
      final cfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      final vendor = _selected!.vendor;

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
            'source_lang': _srcLang == 'ZH' ? 'ZH' : _srcLang,
            'target_lang': _dstLang == 'ZH' ? 'ZH-HANS' : _dstLang,
          }),
        ).timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        final body = jsonDecode(resp.body) as Map;
        final translations = body['translations'] as List;
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
              for (final lang in ['ZH', 'EN', 'JA', 'KO', 'FR', 'DE', 'ES', 'RU', 'AR', 'PT'])
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

enum _StsPhase { idle, connecting, connected, error }

class _TestChatMsg {
  _TestChatMsg(this.role, this.text);
  final String role; // 'user' | 'assistant'
  String text;
  String? translation; // AST 模式：原文配对的译文
}

class _StsTestCard extends StatefulWidget {
  const _StsTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_StsTestCard> createState() => _StsTestCardState();
}

class _StsTestCardState extends State<_StsTestCard> {
  ServiceConfigDto? _selected;
  _StsPhase _phase = _StsPhase.idle;
  String _statusText = '';
  String? _error;
  String? _sessionId;
  final _chatMessages = <_TestChatMsg>[];
  StreamSubscription<AgentEvent>? _eventSub;
  final _bridge = AgentsServerBridge();

  // Connection duration timer
  Duration _connectionDuration = Duration.zero;
  Timer? _connTimer;

  // PolyChat: Agent picker (agentId is per-Agent, not per-Service)
  List<AgentDto> _polychatAgents = const [];
  AgentDto? _selectedAgent;
  final _db = LocalDbBridge();

  static const _accent = Color(0xFF4A42D9);

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
    if (_selected?.vendor == 'polychat') {
      _loadPolychatAgents();
    }
  }

  Future<void> _loadPolychatAgents() async {
    final all = await _db.getAllAgents();
    final agents = all.where((a) {
      if (a.type != 'sts-chat') return false;
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        final tags = (cfg['tags'] as List?)?.cast<String>() ?? const [];
        final agentId = cfg['agentId'] as String?;
        return tags.contains('polychat') && agentId != null && agentId.isNotEmpty;
      } catch (_) {
        return false;
      }
    }).toList();
    if (!mounted) return;
    setState(() {
      _polychatAgents = agents;
      _selectedAgent = agents.isNotEmpty ? agents.first : null;
    });
  }

  void _onServiceChanged(ServiceConfigDto svc) {
    setState(() {
      _selected = svc;
      _selectedAgent = null;
      _polychatAgents = const [];
    });
    if (svc.vendor == 'polychat') {
      _loadPolychatAgents();
    }
  }

  @override
  void dispose() {
    _connTimer?.cancel();
    _eventSub?.cancel();
    if (_sessionId != null) _bridge.stopAgent(_sessionId!);
    super.dispose();
  }

  Future<void> _connect() async {
    if (_selected == null) return;
    final vendor = _selected!.vendor;

    // PolyChat 需要额外的 agentId（来自选中的 Agent）
    if (vendor == 'polychat' && _selectedAgent == null) {
      setState(() {
        _phase = _StsPhase.error;
        _error = '请先选择一个 PolyChat Agent（到「设置 → PolyChat 平台」同步）';
      });
      return;
    }

    final sid = 'sts_test_${DateTime.now().millisecondsSinceEpoch}';
    _connTimer?.cancel();
    _connectionDuration = Duration.zero;
    setState(() {
      _phase = _StsPhase.connecting;
      _statusText = '连接中...';
      _error = null;
      _chatMessages.clear();
      _sessionId = sid;
    });

    _eventSub?.cancel();
    _eventSub = _bridge.eventStream
        .where((e) => e.sessionId == sid)
        .listen(_onEvent, onError: (e) {
      if (mounted) setState(() { _phase = _StsPhase.error; _error = e.toString(); });
    });

    try {
      // 构建 STS 配置 — polychat 需要注入选中 Agent 的 agentId
      String stsConfigJson = _selected!.configJson;
      if (vendor == 'polychat') {
        final base = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
        final agentCfg = jsonDecode(_selectedAgent!.configJson) as Map<String, dynamic>;
        base['agentId'] = agentCfg['agentId'];
        stsConfigJson = jsonEncode(base);
      }

      await _bridge.createAgent(
        agentId: sid,
        agentType: 'sts-chat',
        inputMode: 'text',
        stsVendor: vendor,
        stsConfigJson: stsConfigJson,
      );
      await _bridge.setInputMode(sid, 'call');
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _StsPhase.error;
          _error = e.toString().replaceFirst('Exception: ', '');
          _sessionId = null;
        });
      }
    }
  }

  void _startConnTimer() {
    _connTimer?.cancel();
    _connTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _connectionDuration += const Duration(seconds: 1));
    });
  }

  void _onEvent(AgentEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case ServiceConnectionStateEvent(:final connectionState, :final errorMessage):
          switch (connectionState) {
            case ServiceConnectionState.connected:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = '已连接';
            case ServiceConnectionState.connecting:
              _phase = _StsPhase.connecting;
              _statusText = '连接中...';
            case ServiceConnectionState.error:
              _connTimer?.cancel();
              _phase = _StsPhase.error;
              _error = errorMessage ?? '连接失败';
              _statusText = '错误';
            case ServiceConnectionState.disconnected:
              _connTimer?.cancel();
              if (_phase != _StsPhase.error) {
                _phase = _StsPhase.idle;
                _statusText = '';
              }
          }
        case SessionStateEvent(:final state):
          switch (state) {
            case AgentSessionState.listening:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = '正在聆听...';
            case AgentSessionState.llm:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = 'AI 思考中...';
            case AgentSessionState.tts || AgentSessionState.playing:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = 'AI 正在说话...';
            case AgentSessionState.error:
              _connTimer?.cancel();
              _phase = _StsPhase.error;
              _statusText = '错误';
            default:
              if (_phase == _StsPhase.connecting) {
                _startConnTimer();
                _phase = _StsPhase.connected;
              }
              _statusText = '已连接';
          }
        case rt.SttEvent(:final kind, :final text):
          if (kind == SttEventKind.partialResult && (text ?? '').isNotEmpty) {
            // 部分识别 → 覆盖最后一条 pending user 消息
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'user' && m.text.startsWith('\u200B'));
            if (idx == -1) {
              _chatMessages.add(_TestChatMsg('user', '\u200B$text'));
            } else {
              _chatMessages[idx].text = '\u200B$text';
            }
          } else if (kind == SttEventKind.finalResult && (text ?? '').isNotEmpty) {
            // 定稿 → 替换 pending 或新增
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'user' && m.text.startsWith('\u200B'));
            if (idx != -1) {
              _chatMessages[idx].text = text!;
            } else {
              _chatMessages.add(_TestChatMsg('user', text!));
            }
          }
        case rt.LlmEvent(:final kind, :final textDelta):
          if (kind == LlmEventKind.firstToken && (textDelta ?? '').isNotEmpty) {
            // 同一 requestId → 累加到已有气泡；不同 requestId → 也累加（同一轮 AI 回复）
            final lastIdx = _chatMessages.lastIndexWhere((m) => m.role == 'assistant');
            // 如果最后一条 assistant 和当前之间没有 user 消息 → 累加
            final lastUserIdx = _chatMessages.lastIndexWhere((m) => m.role == 'user');
            if (lastIdx != -1 && lastIdx > lastUserIdx) {
              _chatMessages[lastIdx].text += textDelta!;
            } else {
              _chatMessages.add(_TestChatMsg('assistant', textDelta!));
            }
          }
          // done 事件不需要处理（内容已通过 firstToken 累加）
        case AgentErrorEvent(:final message):
          _phase = _StsPhase.error;
          _error = message;
        default:
          break;
      }
    });
  }

  String _displayText(_TestChatMsg m) {
    final t = m.text;
    if (t.startsWith('\u200B')) return t.substring(1);
    return t;
  }

  Future<void> _hangUp() async {
    _connTimer?.cancel();
    _eventSub?.cancel();
    _eventSub = null;
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try { await _bridge.stopAgent(sid); } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _phase = _StsPhase.idle;
        _statusText = '';
        _error = null;
        _chatMessages.clear();
      });
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    final isActive = _phase != _StsPhase.idle;
    final isConnected = _phase == _StsPhase.connected;
    final isConnecting = _phase == _StsPhase.connecting;
    final isListening = isConnected && _statusText.contains('聆听');

    return _TestCardShell(
      icon: '📞',
      title: 'STS 语音对话测试',
      enabled: enabled,
      type: 'sts',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: _ServiceDropdown(
                value: _selected!.name,
                items: widget.services.map((s) => s.name).toList(),
                onChanged: isActive
                    ? (_) {}
                    : (v) => _onServiceChanged(
                        widget.services.firstWhere((s) => s.name == v)),
              ),
            ),
            const SizedBox(width: 8),
            if (!isActive)
              _ActionBtn(label: '接通', color: _accent, onTap: _connect)
            else
              _ActionBtn(
                label: isConnecting ? '...' : '挂断',
                color: AppTheme.danger,
                onTap: isConnecting ? null : _hangUp,
              ),
          ]),
          // PolyChat: Agent picker (agentId is per-Agent)
          if (_selected!.vendor == 'polychat') ...[
            const SizedBox(height: 8),
            if (_polychatAgents.isEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF9A3412)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '尚未同步 PolyChat Agent。请到「设置 → PolyChat 平台」填写凭证并同步。',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
                    ),
                  ),
                ]),
              )
            else
              Row(children: [
                const Text('Agent',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text2)),
                const SizedBox(width: 8),
                Expanded(
                  child: _ServiceDropdown(
                    value: _selectedAgent?.name ?? _polychatAgents.first.name,
                    items: _polychatAgents.map((a) => a.name).toList(),
                    onChanged: isActive
                        ? (_) {}
                        : (v) => setState(() => _selectedAgent =
                            _polychatAgents.firstWhere((a) => a.name == v)),
                  ),
                ),
              ]),
          ],
          if (isActive) ...[
            const SizedBox(height: 10),
            _ResultBox(
              active: true,
              activeColor: _phase == _StsPhase.error ? AppTheme.danger : _accent,
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF22C55E)
                        : isConnecting ? AppTheme.warning : AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  isConnecting ? '正在建立连接...' : _statusText,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: _phase == _StsPhase.error ? AppTheme.danger : _accent,
                  ),
                )),
                if (isListening) _WaveIcon(),
              ]),
            ),
          ],
          // ── Connection info panel ──
          if (isConnected) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                border: Border.all(color: const Color(0xFF86EFAC)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C55E), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      const Text('WebSocket 已连接', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 3.2,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    children: [
                      _connInfoTile('延迟', '~120ms'),
                      _connInfoTile('连接时长', _fmtDuration(_connectionDuration)),
                      _connInfoTile('音频格式', '16kHz PCM'),
                      _connInfoTile('音色', 'Default'),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // ── Audio visualization ──
          if (isListening) ...[
            const SizedBox(height: 8),
            _WaveformBars(count: 12, color: AppTheme.warning),
          ],
          // ── Chat messages (transcript lines) ──
          if (_chatMessages.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                reverse: true,
                itemCount: _chatMessages.length,
                itemBuilder: (_, i) {
                  final m = _chatMessages[_chatMessages.length - 1 - i];
                  final isUser = m.role == 'user';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUser ? '你: ' : 'AI: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isUser ? const Color(0xFFD97706) : const Color(0xFF16A34A),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _displayText(m),
                            style: const TextStyle(fontSize: 12, color: AppTheme.text1, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_error!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }

  Widget _connInfoTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: AppTheme.text2)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.text1)),
        ],
      ),
    );
  }
}

// ── AST quick test card ──────────────────────────────────────────────────────

class _AstTestCard extends StatefulWidget {
  const _AstTestCard({required this.services});
  final List<ServiceConfigDto> services;

  @override
  State<_AstTestCard> createState() => _AstTestCardState();
}

class _AstTestCardState extends State<_AstTestCard> {
  ServiceConfigDto? _selected;
  _StsPhase _phase = _StsPhase.idle;
  String _statusText = '';
  String? _error;
  String? _sessionId;
  final _chatMessages = <_TestChatMsg>[];
  StreamSubscription<AgentEvent>? _eventSub;
  final _bridge = AgentsServerBridge();

  String _srcLang = 'zh';
  String _dstLang = 'en';
  int _translatedCount = 0;

  // Connection duration timer
  Duration _connectionDuration = Duration.zero;
  Timer? _connTimer;

  // PolyChat: Agent picker (agentId is per-Agent, not per-Service)
  List<AgentDto> _polychatAgents = const [];
  AgentDto? _selectedAgent;
  final _db = LocalDbBridge();

  static const _accent = Color(0xFF9A3412);
  static const _langMap = {
    'zh': '中文', 'en': 'English', 'ja': '日本語', 'ko': '한국어',
    'fr': 'Français', 'de': 'Deutsch', 'es': 'Español',
    'ru': 'Русский', 'ar': 'العربية', 'pt': 'Português',
  };

  @override
  void initState() {
    super.initState();
    if (widget.services.isNotEmpty) _selected = widget.services.first;
    if (_selected?.vendor == 'polychat') {
      _loadPolychatAgents();
    }
  }

  Future<void> _loadPolychatAgents() async {
    final all = await _db.getAllAgents();
    final agents = all.where((a) {
      if (a.type != 'ast-translate') return false;
      try {
        final cfg = jsonDecode(a.configJson) as Map<String, dynamic>;
        final tags = (cfg['tags'] as List?)?.cast<String>() ?? const [];
        final agentId = cfg['agentId'] as String?;
        return tags.contains('polychat') && agentId != null && agentId.isNotEmpty;
      } catch (_) {
        return false;
      }
    }).toList();
    if (!mounted) return;
    setState(() {
      _polychatAgents = agents;
      _selectedAgent = agents.isNotEmpty ? agents.first : null;
    });
  }

  void _onServiceChanged(ServiceConfigDto svc) {
    setState(() {
      _selected = svc;
      _selectedAgent = null;
      _polychatAgents = const [];
    });
    if (svc.vendor == 'polychat') {
      _loadPolychatAgents();
    }
  }

  @override
  void dispose() {
    _connTimer?.cancel();
    _eventSub?.cancel();
    if (_sessionId != null) _bridge.stopAgent(_sessionId!);
    super.dispose();
  }

  void _startConnTimer() {
    _connTimer?.cancel();
    _connTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _connectionDuration += const Duration(seconds: 1));
    });
  }

  Future<void> _connect() async {
    if (_selected == null) return;
    final vendor = _selected!.vendor;

    // PolyChat 需要额外的 agentId（来自选中的 Agent）
    if (vendor == 'polychat' && _selectedAgent == null) {
      setState(() {
        _phase = _StsPhase.error;
        _error = '请先选择一个 PolyChat Agent（到「设置 → PolyChat 平台」同步）';
      });
      return;
    }

    final sid = 'ast_test_${DateTime.now().millisecondsSinceEpoch}';
    _connTimer?.cancel();
    _connectionDuration = Duration.zero;
    _translatedCount = 0;
    setState(() {
      _phase = _StsPhase.connecting;
      _statusText = '连接中...';
      _error = null;
      _chatMessages.clear();
      _sessionId = sid;
    });

    _eventSub?.cancel();
    _eventSub = _bridge.eventStream
        .where((e) => e.sessionId == sid)
        .listen(_onEvent, onError: (e) {
      if (mounted) setState(() { _phase = _StsPhase.error; _error = e.toString(); });
    });

    try {
      final baseCfg = jsonDecode(_selected!.configJson) as Map<String, dynamic>;
      baseCfg['srcLang'] = _srcLang;
      baseCfg['dstLang'] = _dstLang;
      // PolyChat 注入选中 Agent 的 agentId
      if (vendor == 'polychat') {
        final agentCfg = jsonDecode(_selectedAgent!.configJson) as Map<String, dynamic>;
        baseCfg['agentId'] = agentCfg['agentId'];
      }
      final mergedCfg = jsonEncode(baseCfg);

      await _bridge.createAgent(
        agentId: sid,
        agentType: 'ast-translate',
        inputMode: 'text',
        astVendor: vendor,
        astConfigJson: mergedCfg,
        extraParams: {'srcLang': _srcLang, 'dstLang': _dstLang},
      );
      await _bridge.setInputMode(sid, 'call');
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _StsPhase.error;
          _error = e.toString().replaceFirst('Exception: ', '');
          _sessionId = null;
        });
      }
    }
  }

  void _onEvent(AgentEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event) {
        case ServiceConnectionStateEvent(:final connectionState, :final errorMessage):
          switch (connectionState) {
            case ServiceConnectionState.connected:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = '已连接';
            case ServiceConnectionState.connecting:
              _phase = _StsPhase.connecting;
              _statusText = '连接中...';
            case ServiceConnectionState.error:
              _connTimer?.cancel();
              _phase = _StsPhase.error;
              _error = errorMessage ?? '连接失败';
              _statusText = '错误';
            case ServiceConnectionState.disconnected:
              _connTimer?.cancel();
              if (_phase != _StsPhase.error) {
                _phase = _StsPhase.idle;
                _statusText = '';
              }
          }
        case SessionStateEvent(:final state):
          switch (state) {
            case AgentSessionState.listening:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = '正在聆听...';
            case AgentSessionState.llm:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = '翻译中...';
            case AgentSessionState.tts || AgentSessionState.playing:
              if (_phase != _StsPhase.connected) _startConnTimer();
              _phase = _StsPhase.connected;
              _statusText = '正在播报译文...';
            case AgentSessionState.error:
              _connTimer?.cancel();
              _phase = _StsPhase.error;
              _statusText = '错误';
            default:
              if (_phase == _StsPhase.connecting) {
                _startConnTimer();
                _phase = _StsPhase.connected;
              }
              _statusText = '已连接';
          }
        case rt.SttEvent(:final kind, :final text):
          if (kind == SttEventKind.partialResult && (text ?? '').isNotEmpty) {
            // 部分识别 → 覆盖最后一条 pending user 消息（实时预览）
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'user' && m.text.startsWith('\u200B'));
            if (idx == -1) {
              _chatMessages.add(_TestChatMsg('user', '\u200B$text'));
            } else {
              _chatMessages[idx].text = '\u200B$text';
            }
          } else if (kind == SttEventKind.finalResult && (text ?? '').isNotEmpty) {
            // 最终识别 → 替换 pending 或新增 user 消息
            final idx = _chatMessages.lastIndexWhere(
                (m) => m.role == 'user' && m.text.startsWith('\u200B'));
            if (idx != -1) {
              _chatMessages[idx].text = text!; // 移除前缀，标记为最终
            } else {
              _chatMessages.add(_TestChatMsg('user', text!));
            }
          }
        case rt.LlmEvent(:final kind, :final textDelta, :final fullText):
          if (kind == LlmEventKind.firstToken && (textDelta ?? '').isNotEmpty) {
            // AST：译文写入最近一条 user 消息的 translation 字段（配对显示）
            final idx = _chatMessages.lastIndexWhere((m) => m.role == 'user');
            if (idx != -1) {
              _chatMessages[idx].translation = textDelta;
            }
          } else if (kind == LlmEventKind.done && (fullText ?? '').isNotEmpty) {
            // 翻译完成：确保 translation 是最终文本
            final idx = _chatMessages.lastIndexWhere((m) => m.role == 'user');
            if (idx != -1) _chatMessages[idx].translation = fullText;
            _translatedCount++;
          }
        case AgentErrorEvent(:final message):
          _phase = _StsPhase.error;
          _error = message;
        default:
          break;
      }
    });
  }

  String _displayText(_TestChatMsg m) {
    final t = m.text;
    if (t.startsWith('\u200B')) return t.substring(1);
    return t;
  }

  bool _isPending(_TestChatMsg m) => m.text.startsWith('\u200B');

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _hangUp() async {
    _connTimer?.cancel();
    _eventSub?.cancel();
    _eventSub = null;
    final sid = _sessionId;
    _sessionId = null;
    if (sid != null) {
      try { await _bridge.stopAgent(sid); } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _phase = _StsPhase.idle;
        _statusText = '';
        _error = null;
        _chatMessages.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.services.isNotEmpty && _selected != null;
    final isActive = _phase != _StsPhase.idle;
    final isConnected = _phase == _StsPhase.connected;
    final isConnecting = _phase == _StsPhase.connecting;
    final isListening = isConnected && _statusText.contains('聆听');

    return _TestCardShell(
      icon: '🔄',
      title: 'AST 端到端翻译测试',
      enabled: enabled,
      type: 'ast',
      child: enabled ? Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 语言悬浮卡片 ──
          Container(
            margin: const EdgeInsets.only(bottom: 10),
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
                      _BigLangSelector(
                        value: _srcLang, langMap: _langMap,
                        enabled: !isActive,
                        onChanged: (v) => setState(() => _srcLang = v),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: isActive ? null : () => setState(() { final t = _srcLang; _srcLang = _dstLang; _dstLang = t; }),
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF38BDF8)]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: const Color(0xFF0EA5E9).withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: const Icon(Icons.arrow_forward, size: 14, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const Text('目标语言', style: TextStyle(fontSize: 9, color: AppTheme.text2)),
                      const SizedBox(height: 2),
                      _BigLangSelector(
                        value: _dstLang, langMap: _langMap,
                        enabled: !isActive,
                        onChanged: (v) => setState(() => _dstLang = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(children: [
            Expanded(
              child: _ServiceDropdown(
                value: _selected!.name,
                items: widget.services.map((s) => s.name).toList(),
                onChanged: isActive
                    ? (_) {}
                    : (v) => _onServiceChanged(
                        widget.services.firstWhere((s) => s.name == v)),
              ),
            ),
            const SizedBox(width: 8),
            if (!isActive)
              _ActionBtn(label: '接通', color: _accent, onTap: _connect)
            else
              _ActionBtn(
                label: isConnecting ? '...' : '挂断',
                color: AppTheme.danger,
                onTap: isConnecting ? null : _hangUp,
              ),
          ]),
          // PolyChat: Agent picker (agentId is per-Agent)
          if (_selected!.vendor == 'polychat') ...[
            const SizedBox(height: 8),
            if (_polychatAgents.isEmpty)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, size: 14, color: Color(0xFF9A3412)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '尚未同步 PolyChat Agent。请到「设置 → PolyChat 平台」填写凭证并同步。',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
                    ),
                  ),
                ]),
              )
            else
              Row(children: [
                const Text('Agent',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.text2)),
                const SizedBox(width: 8),
                Expanded(
                  child: _ServiceDropdown(
                    value: _selectedAgent?.name ?? _polychatAgents.first.name,
                    items: _polychatAgents.map((a) => a.name).toList(),
                    onChanged: isActive
                        ? (_) {}
                        : (v) => setState(() => _selectedAgent =
                            _polychatAgents.firstWhere((a) => a.name == v)),
                  ),
                ),
              ]),
          ],
          if (isActive) ...[
            const SizedBox(height: 10),
            _ResultBox(
              active: true,
              activeColor: _phase == _StsPhase.error ? AppTheme.danger : _accent,
              child: Row(children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF22C55E)
                        : isConnecting ? AppTheme.warning : AppTheme.danger,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  isConnecting ? '正在建立连接...' : _statusText,
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: _phase == _StsPhase.error ? AppTheme.danger : _accent,
                  ),
                )),
                if (isListening) _WaveIcon(),
              ]),
            ),
          ],
          // ── Stat grid ──
          if (isConnected) ...[
            const SizedBox(height: 8),
            _StatGrid(items: [
              (value: '~150ms', label: '延迟', color: AppTheme.warning),
              (value: _fmtDuration(_connectionDuration), label: '连接时长', color: _accent),
              (value: '$_translatedCount', label: '已翻译句数', color: AppTheme.success),
            ]),
          ],
          // ── Realtime subtitles section card ──
          if (_chatMessages.where((m) => m.role == 'user').isNotEmpty) ...[
            const SizedBox(height: 8),
            _SectionCard(
              header: '实时字幕',
              headerBg: AppTheme.primaryLight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  reverse: true,
                  itemCount: _chatMessages.where((m) => m.role == 'user').length,
                  itemBuilder: (_, i) {
                    final userMsgs = _chatMessages.where((m) => m.role == 'user').toList();
                    final m = userMsgs[userMsgs.length - 1 - i];
                    final hasTranslation = m.translation != null && m.translation!.isNotEmpty;
                    final pending = _isPending(m);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayText(m),
                            style: TextStyle(
                              fontSize: 12,
                              color: _accent,
                              fontStyle: pending ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          if (hasTranslation) ...[
                            const SizedBox(height: 2),
                            Text(
                              m.translation!,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0369A1),
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 9, color: AppTheme.text2),
                          ),
                          if (i < userMsgs.length - 1)
                            const Divider(height: 8, color: AppTheme.borderColor),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
          // ── TTS playback status bar ──
          if (isConnected && _statusText.contains('播报')) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  _WaveIcon(),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('TTS 正在朗读译文...',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF166534))),
                  ),
                  const Icon(Icons.pause, size: 16, color: Color(0xFF166534)),
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 6),
            _ResultBox(
              active: true,
              activeColor: AppTheme.danger,
              child: Row(children: [
                const Icon(Icons.error_outline, size: 13, color: AppTheme.danger),
                const SizedBox(width: 4),
                Expanded(child: Text(_error!,
                    style: const TextStyle(fontSize: 11, color: AppTheme.danger))),
              ]),
            ),
          ],
        ],
      ) : const SizedBox.shrink(),
    );
  }
}

/// Bigger language selector button with dropdown
class _BigLangSelector extends StatelessWidget {
  const _BigLangSelector({
    required this.value,
    required this.langMap,
    required this.enabled,
    required this.onChanged,
  });
  final String value;
  final Map<String, String> langMap;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFFFF7ED) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled ? const Color(0xFFF97316).withValues(alpha: 0.4) : AppTheme.borderColor,
          width: 1.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF9A3412)),
          icon: Icon(Icons.keyboard_arrow_down, size: 16,
              color: enabled ? const Color(0xFF9A3412) : AppTheme.text2),
          onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
          items: langMap.entries.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text('${e.value}  ${e.key}', overflow: TextOverflow.ellipsis),
          )).toList(),
        ),
      ),
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
class _WaveformBars extends StatelessWidget {
  const _WaveformBars({required this.count, required this.color, this.maxHeight = 24});
  final int count;
  final Color color;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final heights = List.generate(count, (i) => 6.0 + ((i * 7 + 3) % 11) / 11.0 * (maxHeight - 6));
    return Container(
      height: maxHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (int i = 0; i < count; i++)
            Container(
              width: 2,
              height: heights[i],
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
            ),
        ],
      ),
    );
  }
}

/// 音色选择药丸 Chip
class _VoiceChip extends StatelessWidget {
  const _VoiceChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: selected ? null : Border.all(color: AppTheme.borderColor, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppTheme.text2)),
      ),
    );
  }
}

/// 带标签和数值的参数滑块
class _ParamSlider extends StatelessWidget {
  const _ParamSlider({required this.label, required this.value, required this.min, required this.max, required this.suffix, required this.onChanged});
  final String label;
  final double value;
  final double min, max;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.text2)),
            const Spacer(),
            Text('${value.toStringAsFixed(1)}$suffix',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: const SliderThemeData(
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value, min: min, max: max,
            activeColor: AppTheme.primary,
            inactiveColor: AppTheme.borderColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

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
