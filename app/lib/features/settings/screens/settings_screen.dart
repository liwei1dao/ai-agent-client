import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:agents_server/agents_server.dart';
import 'package:go_router/go_router.dart';
import 'package:local_db/local_db.dart';
import 'package:share_plus/share_plus.dart';
import '../../desktop_assistant/desktop_assistant_avatar_screen.dart';
import '../../desktop_assistant/desktop_assistant_avatars.dart';
import '../../desktop_assistant/desktop_assistant_controller.dart';
import 'package:tts_azure/tts_azure.dart';
import '../../../core/security/config_crypto.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/services/locale_service.dart';
import '../../../core/services/log_service.dart';
import '../../../core/services/voitrans_service.dart' show polychatServiceProvider;
import '../../../shared/themes/app_theme.dart';
import '../../agents/providers/agent_list_provider.dart';
import '../../chat/providers/agent_screen_provider.dart';
import '../../services/providers/service_library_provider.dart';
import 'log_viewer_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _vtBaseUrlCtrl;
  late final TextEditingController _vtAppIdCtrl;
  late final TextEditingController _vtAppSecretCtrl;
  bool _vtSyncing = false;
  bool _vtInitialized = false;
  int _logSize = 0;

  @override
  void initState() {
    super.initState();
    _refreshLogSize();
  }

  Future<void> _refreshLogSize() async {
    final size = await LogService.instance.totalSize();
    if (mounted) setState(() => _logSize = size);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }

  Future<void> _clearLogs() async {
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
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await LogService.instance.clear();
      await _refreshLogSize();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('日志已清空'),
            backgroundColor: Color(0xFF10B981)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('清空失败: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _exportLogs() async {
    try {
      final file = await LogService.instance.exportToFile();
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Unihelper 日志',
        text: '应用日志导出 ${DateTime.now().toIso8601String()}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  @override
  void dispose() {
    if (_vtInitialized) {
      _vtBaseUrlCtrl.dispose();
      _vtAppIdCtrl.dispose();
      _vtAppSecretCtrl.dispose();
    }
    super.dispose();
  }

  void _initVtControllers(PolychatConfig config) {
    if (_vtInitialized) return;
    _vtInitialized = true;
    _vtBaseUrlCtrl = TextEditingController(text: config.baseUrl);
    _vtAppIdCtrl = TextEditingController(text: config.appId);
    _vtAppSecretCtrl = TextEditingController(text: config.appSecret);
  }

  Future<void> _saveVtConfig() async {
    await ref.read(configServiceProvider.notifier).setPolychatConfig(
          PolychatConfig(
            baseUrl: _vtBaseUrlCtrl.text.trim(),
            appId: _vtAppIdCtrl.text.trim(),
            appSecret: _vtAppSecretCtrl.text.trim(),
          ),
        );
  }

  Future<void> _setAudioOutputMode(AudioOutputMode mode) async {
    await ref.read(configServiceProvider.notifier).setAudioOutputMode(mode);
    final modeStr = mode.name;
    AgentsServerBridge().setAudioOutputMode(modeStr);
    TtsAzurePluginDart.setAudioOutputMode(modeStr);
  }

  Future<void> _syncAgents() async {
    await _saveVtConfig();
    setState(() => _vtSyncing = true);
    try {
      final config = ref.read(configServiceProvider).polychat;
      final count =
          await ref.read(polychatServiceProvider).syncAgents(config);
      await ref.read(agentListProvider.notifier).reload();
      await ref.read(serviceLibraryProvider.notifier).reload();
      ref.invalidate(agentScreenProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('同步成功，共 $count 个 Agent'),
              backgroundColor: const Color(0xFF10B981)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('同步失败: $e'),
              backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      if (mounted) setState(() => _vtSyncing = false);
    }
  }

  Future<void> _showExportScopeDialog(BuildContext context) async {
    bool exportAgents = true;
    bool exportServices = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('导出配置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title:
                    const Text('Agent 配置', style: TextStyle(fontSize: 14)),
                value: exportAgents,
                activeColor: AppTheme.primary,
                onChanged: (v) =>
                    setDialogState(() => exportAgents = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('服务配置', style: TextStyle(fontSize: 14)),
                value: exportServices,
                activeColor: AppTheme.primary,
                onChanged: (v) =>
                    setDialogState(() => exportServices = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: (exportAgents || exportServices)
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    if (exportAgents && exportServices) {
      await _exportData(context, 'all');
    } else if (exportAgents) {
      await _exportData(context, 'agents');
    } else if (exportServices) {
      await _exportData(context, 'services');
    }
  }

  Future<void> _showImportScopeDialog(BuildContext context) async {
    bool importAgents = true;
    bool importServices = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('导入配置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('选择要导入的配置类型：',
                    style: TextStyle(fontSize: 13, color: AppTheme.text2)),
              ),
              CheckboxListTile(
                title:
                    const Text('Agent 配置', style: TextStyle(fontSize: 14)),
                value: importAgents,
                activeColor: AppTheme.primary,
                onChanged: (v) =>
                    setDialogState(() => importAgents = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('服务配置', style: TextStyle(fontSize: 14)),
                value: importServices,
                activeColor: AppTheme.primary,
                onChanged: (v) =>
                    setDialogState(() => importServices = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: (importAgents || importServices)
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('选择文件'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    await _importData(context,
        importAgents: importAgents, importServices: importServices);
  }

  Future<void> _exportData(BuildContext context, String scope) async {
    String plainJson;
    int agentsCount = 0;
    int servicesCount = 0;
    String fileName;
    switch (scope) {
      case 'agents':
        plainJson = ref.read(agentListProvider.notifier).exportAgentsJson();
        agentsCount =
            (jsonDecode(plainJson)['agents'] as List?)?.length ?? 0;
        fileName = 'agents_export.json';
        break;
      case 'services':
        plainJson =
            ref.read(serviceLibraryProvider.notifier).exportServicesJson();
        servicesCount =
            (jsonDecode(plainJson)['services'] as List?)?.length ?? 0;
        fileName = 'services_export.json';
        break;
      default:
        final agentsData = jsonDecode(
            ref.read(agentListProvider.notifier).exportAgentsJson());
        final servicesData = jsonDecode(
            ref.read(serviceLibraryProvider.notifier).exportServicesJson());
        agentsCount = (agentsData['agents'] as List?)?.length ?? 0;
        servicesCount = (servicesData['services'] as List?)?.length ?? 0;
        plainJson = jsonEncode({
          'agents': agentsData['agents'],
          'services': servicesData['services'],
        });
        fileName = 'ai_agent_export.json';
    }

    final password = await _showExportPasswordDialog(context);
    if (password == null) return;

    final String exportJson;
    try {
      exportJson = await _runWithLoading(
        '正在加密…',
        () => ConfigCrypto.encryptJson(
          plainJson,
          password,
          meta: {
            'agents': agentsCount,
            'services': servicesCount,
            'exportedAt': DateTime.now().toIso8601String(),
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('加密失败: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
      return;
    }

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(exportJson);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Unihelper 配置（已加密）',
        text: '配置导出 ${DateTime.now().toIso8601String()}（已使用密码加密，导入时需输入相同密码）',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('导出失败: $e'),
            backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<String?> _showExportPasswordDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ExportPasswordDialog(),
    );
  }

  Future<T> _runWithLoading<T>(String label, Future<T> Function() task) async {
    if (!mounted) return task();
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LoadingDialog(label: label),
    );
    try {
      return await task();
    } finally {
      if (navigator.canPop()) navigator.pop();
    }
  }

  Future<String?> _showImportPasswordDialog(BuildContext context,
      {String? hint, String? errorText}) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImportPasswordDialog(
        hint: hint,
        initialError: errorText,
      ),
    );
  }

  Future<void> _importData(BuildContext context,
      {bool importAgents = true, bool importServices = true}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    final rawStr = await file.readAsString();

    String jsonStr = rawStr;
    if (ConfigCrypto.isEncrypted(rawStr)) {
      String? errorText;
      while (true) {
        if (!mounted) return;
        final password = await _showImportPasswordDialog(
          context,
          errorText: errorText,
        );
        if (password == null) return;
        try {
          jsonStr = await _runWithLoading(
            '正在解密…',
            () => ConfigCrypto.decryptJson(rawStr, password),
          );
          break;
        } on ConfigCryptoException catch (e) {
          errorText = e.message;
          continue;
        } catch (e) {
          errorText = '解密失败: $e';
          continue;
        }
      }
    }

    Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('JSON 格式错误，请检查文件内容')),
      );
      return;
    }

    final hasAgents = importAgents &&
        data.containsKey('agents') &&
        (data['agents'] as List).isNotEmpty;
    final hasServices = importServices &&
        data.containsKey('services') &&
        (data['services'] as List).isNotEmpty;

    if (!hasAgents && !hasServices) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件中没有可导入的配置')),
      );
      return;
    }

    int totalImported = 0;
    int svcNew = 0;
    int svcOverwrite = 0;
    int svcSkip = 0;

    if (hasServices) {
      final svcNotifier = ref.read(serviceLibraryProvider.notifier);
      final parsed = svcNotifier.parseImportJson(jsonStr);
      if (parsed.totalCount > 0) {
        if (parsed.hasConflicts && mounted) {
          final overwriteIds = await _showConflictDialog<ImportItem>(
            context,
            conflicts: parsed.conflicts,
            newCount: parsed.newItems.length,
            itemName: (item) => item.name,
            itemSubtitle: (item) =>
                '${item.type.toUpperCase()} · ${item.vendor}',
            itemId: (item) => item.existingId!,
            title: '服务导入冲突',
          );
          if (overwriteIds != null) {
            final r = await _runWithLoading(
              '正在导入服务…',
              () => svcNotifier.executeImport(
                newItems: parsed.newItems,
                conflicts: parsed.conflicts,
                overwriteIds: overwriteIds,
              ),
            );
            svcNew += r.newCount;
            svcOverwrite += r.overwriteCount;
            svcSkip += r.skipCount;
            totalImported += r.totalImported;
          } else {
            svcSkip += parsed.totalCount;
          }
        } else {
          final r = await _runWithLoading(
            '正在导入服务…',
            () => svcNotifier.executeImport(
              newItems: parsed.newItems,
              conflicts: [],
              overwriteIds: {},
            ),
          );
          svcNew += r.newCount;
          svcOverwrite += r.overwriteCount;
          svcSkip += r.skipCount;
          totalImported += r.totalImported;
        }
      }
    }

    if (hasAgents) {
      final agentNotifier = ref.read(agentListProvider.notifier);
      final parsed = agentNotifier.parseImportJson(jsonStr);
      if (parsed.totalCount > 0) {
        if (parsed.hasConflicts && mounted) {
          final overwriteIds = await _showConflictDialog<AgentImportItem>(
            context,
            conflicts: parsed.conflicts,
            newCount: parsed.newItems.length,
            itemName: (item) => item.name,
            itemSubtitle: (item) => item.type.toUpperCase(),
            itemId: (item) => item.existingId!,
            title: 'Agent 导入冲突',
          );
          if (overwriteIds != null) {
            totalImported += await _runWithLoading(
              '正在导入 Agent…',
              () => agentNotifier.executeImport(
                newItems: parsed.newItems,
                conflicts: parsed.conflicts,
                overwriteIds: overwriteIds,
              ),
            );
          }
        } else {
          totalImported += await _runWithLoading(
            '正在导入 Agent…',
            () => agentNotifier.executeImport(
              newItems: parsed.newItems,
              conflicts: [],
              overwriteIds: {},
            ),
          );
        }
      }
    }

    if (!mounted) return;
    final detail = StringBuffer('成功导入 $totalImported 项配置');
    if (hasServices && (svcNew + svcOverwrite + svcSkip) > 0) {
      detail.write('（服务：新增 $svcNew / 覆盖 $svcOverwrite / 跳过 $svcSkip）');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(detail.toString()),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Future<Set<String>?> _showConflictDialog<T>(
    BuildContext context, {
    required List<T> conflicts,
    required int newCount,
    required String Function(T) itemName,
    required String Function(T) itemSubtitle,
    required String Function(T) itemId,
    required String title,
  }) async {
    final overwriteMap = <String, bool>{
      for (final c in conflicts) itemId(c): true,
    };

    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allOverwrite = overwriteMap.values.every((v) => v);
          final allSkip = overwriteMap.values.every((v) => !v);
          return AlertDialog(
            title: Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (newCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('$newCount 项新配置将直接导入',
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.text2)),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '以下 ${conflicts.length} 项与本地已有配置冲突：',
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.text1),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setDialogState(() {
                          final next = !allOverwrite;
                          for (final k in overwriteMap.keys) {
                            overwriteMap[k] = next;
                          }
                        }),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0),
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          allOverwrite
                              ? '全部跳过'
                              : (allSkip ? '全部覆盖' : '全部覆盖'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: conflicts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = conflicts[i];
                        final id = itemId(item);
                        final overwrite = overwriteMap[id] ?? false;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(itemName(item),
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text(itemSubtitle(item),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.text2)),
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () => setDialogState(
                                    () => overwriteMap[id] = !overwrite),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: overwrite
                                        ? AppTheme.primary
                                            .withValues(alpha: 0.1)
                                        : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: overwrite
                                          ? AppTheme.primary
                                          : AppTheme.borderColor,
                                    ),
                                  ),
                                  child: Text(
                                    overwrite ? '覆盖' : '跳过',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: overwrite
                                          ? AppTheme.primary
                                          : AppTheme.text2,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final ids = overwriteMap.entries
                      .where((e) => e.value)
                      .map((e) => e.key)
                      .toSet();
                  Navigator.pop(ctx, ids);
                },
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary),
                child: const Text('确认导入'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPolyChatSection(AppColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 字段区
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: TextField(
              controller: _vtBaseUrlCtrl,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://your-server.com',
                prefixIcon: Icon(Icons.dns_outlined, size: 18),
              ),
              style: TextStyle(fontSize: 14, color: colors.text1),
              onChanged: (_) => _saveVtConfig(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: TextField(
              controller: _vtAppIdCtrl,
              decoration: const InputDecoration(
                labelText: 'App ID',
                prefixIcon: Icon(Icons.badge_outlined, size: 18),
              ),
              style: TextStyle(fontSize: 14, color: colors.text1),
              onChanged: (_) => _saveVtConfig(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: TextField(
              controller: _vtAppSecretCtrl,
              decoration: const InputDecoration(
                labelText: 'App Secret',
                prefixIcon: Icon(Icons.key_outlined, size: 18),
              ),
              style: TextStyle(fontSize: 14, color: colors.text1),
              obscureText: true,
              onChanged: (_) => _saveVtConfig(),
            ),
          ),
          // 同步按钮
          Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton.icon(
              onPressed: _vtSyncing ? null : _syncAgents,
              icon: _vtSyncing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync_rounded, size: 17),
              label: Text(_vtSyncing ? '同步中…' : '同步 Agent'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = ref.watch(configServiceProvider);
    _initVtControllers(appConfig.polychat);
    final colors = context.appColors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
        children: [
          // ── 外观 ──
          _SectionHeader('外观'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.palette_outlined,
                    color: Color(0xFF6C63FF)),
                title: '主题模式',
                trailing: _ThemePill(
                  current: appConfig.themeMode,
                  onChanged: (mode) => ref
                      .read(configServiceProvider.notifier)
                      .setThemeMode(mode),
                ),
              ),
            ],
          ),

          // ── 播报 ──
          _SectionHeader('播报'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.volume_up_outlined,
                    color: Color(0xFF0EA5E9)),
                title: '音频输出',
                subtitle: '自动：有耳机走系统路由，无耳机走扬声器',
                trailing: _AudioOutputPill(
                  current: appConfig.audioOutputMode,
                  onChanged: _setAudioOutputMode,
                ),
              ),
            ],
          ),

          // ── 设备 ──
          _SectionHeader('设备'),
          _DeviceSection(),

          // ── PolyChat 平台 ──
          _SectionHeader('PolyChat 平台'),
          _buildPolyChatSection(colors),

          // ── 配置管理 ──
          _SectionHeader('配置管理'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.file_upload_outlined,
                    color: Color(0xFF10B981)),
                title: '导出配置',
                subtitle: '加密导出 Agent 和服务配置',
                showChevron: true,
                onTap: () => _showExportScopeDialog(context),
              ),
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.file_download_outlined,
                    color: Color(0xFF10B981)),
                title: '导入配置',
                subtitle: '从文件还原 Agent 和服务配置',
                showChevron: true,
                onTap: () => _showImportScopeDialog(context),
              ),
            ],
          ),

          // ── 日志 ──
          _SectionHeader('日志'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.description_outlined,
                    color: Color(0xFFF59E0B)),
                title: '查看日志',
                subtitle: '当前占用 ${_formatSize(_logSize)}',
                showChevron: true,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LogViewerScreen()),
                  );
                  _refreshLogSize();
                },
              ),
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.ios_share,
                    color: Color(0xFFF59E0B)),
                title: '导出日志',
                subtitle: '合并所有日志文件并分享',
                showChevron: true,
                onTap: _exportLogs,
              ),
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.delete_sweep_outlined,
                    color: Color(0xFFEF4444)),
                title: '清空日志',
                subtitle: '删除所有日志文件，不可恢复',
                titleColor: const Color(0xFFEF4444),
                onTap: _clearLogs,
              ),
            ],
          ),

          // ── 关于 ──
          _SectionHeader('关于'),
          _SettingsGroup(
            children: [
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.smart_toy_outlined,
                    color: AppTheme.primary),
                title: 'Unihelper',
                trailing: Text('v1.0.0',
                    style: TextStyle(
                        fontSize: 13, color: colors.text2)),
              ),
              _SettingsTile(
                badge: const _IconBadge(
                    icon: Icons.code_outlined,
                    color: Color(0xFF6B7280)),
                title: '开源地址',
                showChevron: true,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout primitives
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.text2,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final divided = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      divided.add(children[i]);
      if (i < children.length - 1) {
        divided.add(Divider(
          height: 1,
          thickness: 1,
          indent: 58,
          color: colors.border,
        ));
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: divided,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Icon badge
// ─────────────────────────────────────────────────────────────────────────────

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Standard tap / info tile
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.badge,
    required this.title,
    this.subtitle,
    this.trailing,
    this.titleColor,
    this.showChevron = false,
    this.onTap,
  });

  final Widget badge;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? titleColor;
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    Widget? effectiveTrailing = trailing;
    if (showChevron && trailing == null) {
      effectiveTrailing =
          Icon(Icons.chevron_right, size: 20, color: colors.text2);
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            badge,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: titleColor ?? colors.text1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: colors.text2),
                    ),
                  ],
                ],
              ),
            ),
            if (effectiveTrailing != null) ...[
              const SizedBox(width: 8),
              effectiveTrailing,
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Switch tile
// ─────────────────────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.badge,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Widget badge;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          badge,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(fontSize: 12, color: colors.text2)),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppTheme.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dropdown tile (label above, full-width dropdown below)
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.badge,
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Widget badge;
  final String title;
  final String? subtitle;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              badge,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colors.text1)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style:
                              TextStyle(fontSize: 12, color: colors.text2)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<T>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              filled: true,
              fillColor: colors.bg,
            ),
            items: items,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme mode segmented button
// ─────────────────────────────────────────────────────────────────────────────

class _ThemePill extends StatelessWidget {
  const _ThemePill({required this.current, required this.onChanged});
  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_outlined, size: 16),
            tooltip: '浅色'),
        ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined, size: 16),
            tooltip: '深色'),
        ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined, size: 16),
            tooltip: '跟随系统'),
      ],
      selected: {current},
      onSelectionChanged: (v) => onChanged(v.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio output segmented button
// ─────────────────────────────────────────────────────────────────────────────

class _AudioOutputPill extends StatelessWidget {
  const _AudioOutputPill({required this.current, required this.onChanged});
  final AudioOutputMode current;
  final ValueChanged<AudioOutputMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<AudioOutputMode>(
      segments: const [
        ButtonSegment(
            value: AudioOutputMode.auto,
            icon: Icon(Icons.auto_mode_outlined, size: 16),
            tooltip: '自动'),
        ButtonSegment(
            value: AudioOutputMode.speaker,
            icon: Icon(Icons.volume_up_outlined, size: 16),
            tooltip: '扬声器'),
        ButtonSegment(
            value: AudioOutputMode.earpiece,
            icon: Icon(Icons.phone_in_talk_outlined, size: 16),
            tooltip: '听筒'),
      ],
      selected: {current},
      onSelectionChanged: (v) => onChanged(v.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Device section
// ─────────────────────────────────────────────────────────────────────────────

class _DeviceSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final config = ref.watch(configServiceProvider);
    final agents = ref.watch(agentListProvider);
    final vendors = buildVendorOptions();

    final chatAgents =
        agents.where((a) => a.type == 'chat' || a.type == 'sts-chat').toList();
    final translateAgents = agents
        .where((a) => a.type == 'translate' || a.type == 'ast-translate')
        .toList();

    // Build items dynamically, then auto-divide them
    final items = <Widget>[
      // 设备厂商
      _DropdownTile<String?>(
        badge: const _IconBadge(
            icon: Icons.headphones_outlined, color: Color(0xFF8B5CF6)),
        title: '设备厂商',
        subtitle: '切换厂商会断开当前设备',
        value: config.deviceVendor,
        items: [
          const DropdownMenuItem<String?>(
              value: null, child: Text('未选择')),
          ...vendors.map(
            (v) => DropdownMenuItem<String?>(
              value: v.key,
              enabled: v.available,
              child: Text(
                v.available ? v.label : '${v.label}（敬请期待）',
                style: TextStyle(
                  color: v.available ? null : colors.text2,
                ),
              ),
            ),
          ),
        ],
        onChanged: (v) =>
            ref.read(configServiceProvider.notifier).setDeviceVendor(v),
      ),
    ];

    // Android: 桌面悬浮助理
    if (Platform.isAndroid) {
      items.add(_DesktopAssistantTile(enabled: config.desktopAssistantEnabled));
      if (config.desktopAssistantEnabled) {
        items.add(_DesktopAssistantAvatarTile(
            currentKey: config.desktopAssistantAvatar));
      }
    }

    // 杰理专属
    if (config.deviceVendor == 'jieli') {
      items.add(_JieliConnectWayTile(current: config.jieliConnectWay));
      items.add(_JieliUseDeviceAuthTile(enabled: config.jieliUseDeviceAuth));
    }

    // 默认 Agent 选择
    items.add(_AgentPickerTile(
      badge: const _IconBadge(
          icon: Icons.chat_bubble_outline, color: Color(0xFF6C63FF)),
      title: '默认聊天 Agent',
      subtitle: '设备唤醒（PTT / 语音唤醒）后自动启动',
      options: chatAgents,
      currentId: config.defaultChatAgentId,
      onChanged: (id) => ref
          .read(configServiceProvider.notifier)
          .setDefaultChatAgentId(id),
    ));
    items.add(_AgentPickerTile(
      badge: const _IconBadge(
          icon: Icons.translate_outlined, color: Color(0xFF0EA5E9)),
      title: '默认翻译 Agent',
      subtitle: '设备翻译键触发后自动启动',
      options: translateAgents,
      currentId: config.defaultTranslateAgentId,
      onChanged: (id) => ref
          .read(configServiceProvider.notifier)
          .setDefaultTranslateAgentId(id),
    ));
    items.add(_AgentPickerTile(
      badge: const _IconBadge(
          icon: Icons.assistant_outlined, color: Color(0xFF10B981)),
      title: 'AI 助理 Agent',
      subtitle: '在 AI 助理页通过耳机进行语音对话',
      options: chatAgents,
      currentId: config.defaultAssistantAgentId,
      onChanged: (id) => ref
          .read(configServiceProvider.notifier)
          .setDefaultAssistantAgentId(id),
    ));
    items.add(_LangPickerTile(
      badge: const _IconBadge(
          icon: Icons.record_voice_over_outlined, color: Color(0xFFF59E0B)),
      title: 'AI 助理 用户语言',
      subtitle: '决定 STT 识别与 TTS 朗读语种',
      currentCode: config.defaultAssistantUserLanguage,
      onChanged: (code) => ref
          .read(configServiceProvider.notifier)
          .setDefaultAssistantUserLanguage(code),
    ));

    // 设备扫描
    final scanEnabled = config.deviceVendor != null;
    items.add(_SettingsTile(
      badge: _IconBadge(
          icon: Icons.bluetooth_searching,
          color: scanEnabled
              ? const Color(0xFF3B82F6)
              : const Color(0xFFD1D5DB)),
      title: '设备扫描与连接',
      subtitle: scanEnabled ? '扫描可用耳机并建立连接' : '请先选择厂商',
      showChevron: scanEnabled,
      onTap: scanEnabled
          ? () => GoRouter.of(context).go('/devices')
          : null,
    ));

    // Build divided list
    final divided = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      divided.add(items[i]);
      if (i < items.length - 1) {
        divided.add(Divider(
            height: 1, thickness: 1, indent: 58, color: colors.border));
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: divided,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Agent picker (label + dropdown inside device section)
// ─────────────────────────────────────────────────────────────────────────────

class _AgentPickerTile extends StatelessWidget {
  const _AgentPickerTile({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.currentId,
    required this.onChanged,
  });

  final Widget badge;
  final String title;
  final String subtitle;
  final List<AgentDto> options;
  final String? currentId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final exists = options.any((a) => a.id == currentId);
    return _DropdownTile<String?>(
      badge: badge,
      title: title,
      subtitle: subtitle,
      value: exists ? currentId : null,
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child:
              Text(options.isEmpty ? '无可选 Agent' : '未选择',
                  style: TextStyle(color: colors.text2)),
        ),
        ...options.map(
          (a) => DropdownMenuItem<String?>(
            value: a.id,
            child: Text(a.name, style: TextStyle(color: colors.text1)),
          ),
        ),
      ],
      onChanged: options.isEmpty ? null : onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Jieli connect way
// ─────────────────────────────────────────────────────────────────────────────

class _JieliConnectWayTile extends ConsumerWidget {
  const _JieliConnectWayTile({required this.current});
  final JieliConnectWay current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _IconBadge(
                  icon: Icons.bluetooth_connected,
                  color: Color(0xFF3B82F6)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('链接方式（杰理）',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colors.text1)),
                    const SizedBox(height: 2),
                    Text('自动按设备广播；BLE / SPP 强制下次连接走该协议',
                        style: TextStyle(fontSize: 12, color: colors.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<JieliConnectWay>(
            segments: const [
              ButtonSegment(value: JieliConnectWay.auto, label: Text('自动')),
              ButtonSegment(value: JieliConnectWay.ble, label: Text('BLE')),
              ButtonSegment(value: JieliConnectWay.spp, label: Text('SPP')),
            ],
            selected: {current},
            onSelectionChanged: (s) => ref
                .read(configServiceProvider.notifier)
                .setJieliConnectWay(s.first),
            style: const ButtonStyle(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Jieli device auth toggle
// ─────────────────────────────────────────────────────────────────────────────

class _JieliUseDeviceAuthTile extends ConsumerWidget {
  const _JieliUseDeviceAuthTile({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SwitchTile(
      badge: const _IconBadge(
          icon: Icons.verified_user_outlined, color: Color(0xFF8B5CF6)),
      title: 'RCSP 设备认证（杰理）',
      subtitle: enabled
          ? '已开启：仅签名授权的耳机可连接'
          : '已关闭：跳过认证，可调试无签名样机',
      value: enabled,
      onChanged: (v) =>
          ref.read(configServiceProvider.notifier).setJieliUseDeviceAuth(v),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop assistant toggle
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopAssistantTile extends ConsumerWidget {
  const _DesktopAssistantTile({required this.enabled});
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SwitchTile(
      badge: const _IconBadge(
          icon: Icons.smart_toy_outlined, color: Color(0xFF10B981)),
      title: '桌面悬浮助理',
      subtitle: enabled
          ? '已开启：桌面常驻助理形象，app 划掉仍在'
          : '开启后显示可拖动的悬浮助理（需要悬浮窗权限）',
      value: enabled,
      onChanged: (v) async {
        final notifier = ref.read(configServiceProvider.notifier);
        if (!v) {
          notifier.setDesktopAssistantEnabled(false);
          return;
        }
        const controller = DesktopAssistantController();
        var granted = await controller.isPermissionGranted();
        if (!granted) granted = await controller.requestPermission();
        if (granted) {
          notifier.setDesktopAssistantEnabled(true);
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('需要悬浮窗权限才能显示桌面助理'),
          ));
        }
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop assistant avatar tile
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopAssistantAvatarTile extends StatelessWidget {
  const _DesktopAssistantAvatarTile({required this.currentKey});
  final String currentKey;

  @override
  Widget build(BuildContext context) {
    final avatar = desktopAssistantAvatarByKey(currentKey);
    return _SettingsTile(
      badge: const _IconBadge(
          icon: Icons.face_retouching_natural_outlined,
          color: Color(0xFFEC4899)),
      title: '助理形象',
      subtitle: '当前：${avatar.label}',
      showChevron: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => const DesktopAssistantAvatarScreen()),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Language picker tile
// ─────────────────────────────────────────────────────────────────────────────

class _LangPickerTile extends StatelessWidget {
  const _LangPickerTile({
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.currentCode,
    required this.onChanged,
  });

  final Widget badge;
  final String title;
  final String subtitle;
  final String? currentCode;
  final ValueChanged<String?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final colors = context.appColors;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final code in LocaleService.allCodes)
              ListTile(
                title: Text(LocaleService.langNames[code] ?? code,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: colors.text1)),
                subtitle:
                    Text(code, style: TextStyle(color: colors.text2)),
                onTap: () => Navigator.pop(context, code),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final code = currentCode;
    final label =
        code == null ? '未选择' : (LocaleService.langNames[code] ?? code);
    return _SettingsTile(
      badge: badge,
      title: title,
      subtitle: '$subtitle · $label',
      showChevron: true,
      onTap: () => _pick(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading dialog
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export password dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ExportPasswordDialog extends StatefulWidget {
  const _ExportPasswordDialog();

  @override
  State<_ExportPasswordDialog> createState() => _ExportPasswordDialogState();
}

class _ExportPasswordDialogState extends State<_ExportPasswordDialog> {
  final _pwdCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _pwdCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pwdCtrl.text;
    final c = _confirmCtrl.text;
    if (p.length < 6) {
      setState(() => _errorText = '密码长度至少 6 位');
      return;
    }
    if (p != c) {
      setState(() => _errorText = '两次输入的密码不一致');
      return;
    }
    Navigator.pop(context, p);
  }

  void _clearError() {
    if (_errorText != null) setState(() => _errorText = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置导出密码',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '配置中包含 API Key / App Secret 等敏感信息，'
            '将使用 AES-256 + PBKDF2 加密导出。\n'
            '请妥善保管密码，丢失后无法恢复。',
            style: TextStyle(fontSize: 13, color: AppTheme.text2),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdCtrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '密码（至少 6 位）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => _clearError(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            decoration: InputDecoration(
              labelText: '确认密码',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          style:
              FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: const Text('确认导出'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Import password dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ImportPasswordDialog extends StatefulWidget {
  const _ImportPasswordDialog({this.hint, this.initialError});
  final String? hint;
  final String? initialError;

  @override
  State<_ImportPasswordDialog> createState() => _ImportPasswordDialogState();
}

class _ImportPasswordDialogState extends State<_ImportPasswordDialog> {
  final _pwdCtrl = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _errorText = widget.initialError;
  }

  @override
  void dispose() {
    _pwdCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('输入解密密码',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hint ?? '该配置文件已加密，请输入导出时设置的密码。',
            style: const TextStyle(fontSize: 13, color: AppTheme.text2),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pwdCtrl,
            obscureText: true,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(context, v),
            decoration: InputDecoration(
              labelText: '密码',
              isDense: true,
              border: const OutlineInputBorder(),
              errorText: _errorText,
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pwdCtrl.text),
          style:
              FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: const Text('解密导入'),
        ),
      ],
    );
  }
}
