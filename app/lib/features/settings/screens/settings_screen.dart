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
import 'package:tts_azure/tts_azure.dart';
import '../../../core/security/config_crypto.dart';
import '../../../core/services/config_service.dart';
import '../../../core/services/device_service.dart';
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
  // PolyChat 平台配置
  late final TextEditingController _vtBaseUrlCtrl;
  late final TextEditingController _vtAppIdCtrl;
  late final TextEditingController _vtAppSecretCtrl;
  bool _vtSyncing = false;
  bool _vtInitialized = false;

  // 日志占用大小
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
            style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
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
            content: Text('日志已清空'), backgroundColor: Color(0xFF10B981)),
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
      // 优先走系统分享；用户可以选择保存到文件、AirDrop、邮件等
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '云衍测试平台 日志',
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
    _vtBaseUrlCtrl.dispose();
    _vtAppIdCtrl.dispose();
    _vtAppSecretCtrl.dispose();
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
    final modeStr = mode.name; // earpiece / speaker / auto
    // Android: agents_server channel
    AgentsServerBridge().setAudioOutputMode(modeStr);
    // iOS: tts_azure channel
    TtsAzurePluginDart.setAudioOutputMode(modeStr);
  }

  Future<void> _syncAgents() async {
    await _saveVtConfig();
    setState(() => _vtSyncing = true);
    try {
      final config = ref.read(configServiceProvider).polychat;
      final count =
          await ref.read(polychatServiceProvider).syncAgents(config);
      // Reload agent list and service list after sync
      await ref.read(agentListProvider.notifier).reload();
      await ref.read(serviceLibraryProvider.notifier).reload();
      // Invalidate any open chat agent state so reopened pages re-init from
      // the freshly synced config (语言列表 / agentId 等).
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

  /// 显示导出范围选择弹窗
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

  /// 显示导入范围选择弹窗
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

    // 配置中包含 API Key / App Secret 等敏感字段，强制要求设置密码加密。
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
        subject: '云衍测试平台 配置（已加密）',
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

  /// 设置导出密码（需两次输入一致）。返回 null 表示取消。
  Future<String?> _showExportPasswordDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ExportPasswordDialog(),
    );
  }

  /// 在阻塞 loading 浮层下执行耗时任务，结束后自动关闭。
  /// 用于 PBKDF2 加解密 / DB 批量写入等会让 UI 看起来卡住的步骤。
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

  /// 输入解密密码。返回 null 表示取消。
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

    // 加密格式检测：若是 ai-agent-export-v2 加密文件，提示输入密码并解密。
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
            totalImported += await _runWithLoading(
              '正在导入服务…',
              () => svcNotifier.executeImport(
                newItems: parsed.newItems,
                conflicts: parsed.conflicts,
                overwriteIds: overwriteIds,
              ),
            );
          }
        } else {
          totalImported += await _runWithLoading(
            '正在导入服务…',
            () => svcNotifier.executeImport(
              newItems: parsed.newItems,
              conflicts: [],
              overwriteIds: {},
            ),
          );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('成功导入 $totalImported 项配置'),
        backgroundColor: const Color(0xFF10B981),
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
      for (final c in conflicts) itemId(c): false,
    };

    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
                Text('以下 ${conflicts.length} 项与本地已有配置冲突：',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.text1)),
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
              style:
                  FilledButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('确认导入'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = ref.watch(configServiceProvider);
    _initVtControllers(appConfig.polychat);
    final colors = context.appColors;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // ── 外观 ──
          const _SectionLabel('外观'),
          _SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('主题模式',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: colors.text1)),
                    ),
                    _ThemePill(
                      current: appConfig.themeMode,
                      onChanged: (mode) => ref
                          .read(configServiceProvider.notifier)
                          .setThemeMode(mode),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 播报设置 ──
          const _SectionLabel('播报设置'),
          _SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('音频输出',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: colors.text1)),
                          const SizedBox(height: 2),
                          Text('自动模式：有耳机走系统路由，无耳机走扬声器',
                              style: TextStyle(
                                  fontSize: 11, color: colors.text2)),
                        ],
                      ),
                    ),
                    _AudioOutputPill(
                      current: appConfig.audioOutputMode,
                      onChanged: (mode) => _setAudioOutputMode(mode),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 设备 ──
          const _SectionLabel('设备'),
          _DeviceSection(),

          // ── PolyChat 平台 ──
          const _SectionLabel('PolyChat 平台'),
          _SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _vtBaseUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://your-server.com',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(fontSize: 14, color: colors.text1),
                  onChanged: (_) => _saveVtConfig(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _vtAppIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'App ID',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(fontSize: 14, color: colors.text1),
                  onChanged: (_) => _saveVtConfig(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _vtAppSecretCtrl,
                  decoration: const InputDecoration(
                    labelText: 'App Secret',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  style: TextStyle(fontSize: 14, color: colors.text1),
                  obscureText: true,
                  onChanged: (_) => _saveVtConfig(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _vtSyncing ? null : _syncAgents,
                    icon: _vtSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.sync, size: 18),
                    label: Text(_vtSyncing ? '同步中...' : '同步 Agent'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── 配置管理 ──
          const _SectionLabel('配置管理'),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.file_upload_outlined,
                    color: AppTheme.primary, size: 20),
                title: Text('导出配置',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                subtitle: Text('选择导出 Agent 或服务配置',
                    style: TextStyle(fontSize: 12, color: colors.text2)),
                trailing: Icon(Icons.chevron_right,
                    color: colors.text2, size: 20),
                onTap: () => _showExportScopeDialog(context),
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: const Icon(Icons.file_download_outlined,
                    color: AppTheme.primary, size: 20),
                title: Text('导入配置',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                subtitle: Text('选择导入 Agent 或服务配置',
                    style: TextStyle(fontSize: 12, color: colors.text2)),
                trailing: Icon(Icons.chevron_right,
                    color: colors.text2, size: 20),
                onTap: () => _showImportScopeDialog(context),
              ),
            ],
          ),

          // ── 日志管理 ──
          const _SectionLabel('日志管理'),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined,
                    color: AppTheme.primary, size: 20),
                title: Text('查看日志',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                subtitle: Text('当前占用 ${_formatSize(_logSize)}',
                    style: TextStyle(fontSize: 12, color: colors.text2)),
                trailing: Icon(Icons.chevron_right,
                    color: colors.text2, size: 20),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LogViewerScreen()),
                  );
                  _refreshLogSize();
                },
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: const Icon(Icons.ios_share,
                    color: AppTheme.primary, size: 20),
                title: Text('导出日志',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                subtitle: Text('合并所有日志文件并分享',
                    style: TextStyle(fontSize: 12, color: colors.text2)),
                trailing: Icon(Icons.chevron_right,
                    color: colors.text2, size: 20),
                onTap: _exportLogs,
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined,
                    color: Color(0xFFEF4444), size: 20),
                title: Text('清空日志',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                subtitle: Text('删除所有日志文件',
                    style: TextStyle(fontSize: 12, color: colors.text2)),
                trailing: Icon(Icons.chevron_right,
                    color: colors.text2, size: 20),
                onTap: _clearLogs,
              ),
            ],
          ),

          // ── 关于 ──
          const _SectionLabel('关于'),
          _SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.smart_toy_outlined,
                    color: AppTheme.primary),
                title: Text('云衍测试平台',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                subtitle: Text('v1.0.0',
                    style: TextStyle(fontSize: 12, color: colors.text2)),
              ),
              Divider(height: 1, color: colors.border),
              ListTile(
                leading: const Icon(Icons.code_outlined,
                    color: AppTheme.primary),
                title: Text('开源地址',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.text1)),
                trailing: Icon(Icons.open_in_new,
                    size: 18, color: colors.text2),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Section label ──
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.appColors.text2)),
    );
  }
}

// ── Section card ──
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

// ── Theme mode segmented button ──
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
            icon: Icon(Icons.light_mode_outlined),
            tooltip: '浅色'),
        ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_outlined),
            tooltip: '深色'),
        ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_outlined),
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

// ── 设备区块（厂商选择 + 默认 chat/translate agent） ──
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

    return _SectionCard(
      children: [
        // 设备厂商（标题在上，下拉框单独占一行，避免横向挤压）
        Padding(
          padding:
              const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设备厂商',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colors.text1)),
              const SizedBox(height: 2),
              Text('切换厂商会断开当前设备',
                  style:
                      TextStyle(fontSize: 11, color: colors.text2)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: DropdownButtonFormField<String?>(
                  value: config.deviceVendor,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: colors.border),
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('未选择'),
                    ),
                    ...vendors.map(
                      (v) => DropdownMenuItem<String?>(
                        value: v.key,
                        enabled: v.available,
                        child: Text(
                          v.available
                              ? v.label
                              : '${v.label}（敬请期待）',
                          style: TextStyle(
                            color: v.available ? null : colors.text2,
                          ),
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) {
                    ref
                        .read(configServiceProvider.notifier)
                        .setDeviceVendor(v);
                  },
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.border),

        // 杰理链接方式（仅杰理厂商可见）
        if (config.deviceVendor == 'jieli') ...[
          _JieliConnectWayTile(current: config.jieliConnectWay),
          Divider(height: 1, color: colors.border),
        ],

        // 默认聊天 agent
        _AgentPickerTile(
          icon: Icons.chat_bubble_outline,
          title: '默认聊天 Agent',
          subtitle: '设备唤醒（PTT / 语音唤醒）后自动启动',
          options: chatAgents,
          currentId: config.defaultChatAgentId,
          onChanged: (id) => ref
              .read(configServiceProvider.notifier)
              .setDefaultChatAgentId(id),
        ),
        Divider(height: 1, color: colors.border),

        // 默认翻译 agent
        _AgentPickerTile(
          icon: Icons.translate_outlined,
          title: '默认翻译 Agent',
          subtitle: '设备翻译键触发后自动启动',
          options: translateAgents,
          currentId: config.defaultTranslateAgentId,
          onChanged: (id) => ref
              .read(configServiceProvider.notifier)
              .setDefaultTranslateAgentId(id),
        ),
        Divider(height: 1, color: colors.border),

        // 进入设备管理页
        ListTile(
          leading: const Icon(Icons.bluetooth_searching,
              color: AppTheme.primary, size: 20),
          title: Text('设备扫描与连接',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.text1)),
          subtitle: Text(config.deviceVendor == null
              ? '请先选择厂商'
              : '扫描可用耳机并建立连接',
              style: TextStyle(fontSize: 12, color: colors.text2)),
          trailing:
              Icon(Icons.chevron_right, color: colors.text2, size: 20),
          enabled: config.deviceVendor != null,
          onTap: config.deviceVendor == null
              ? null
              : () => GoRouter.of(context).go('/devices'),
        ),
      ],
    );
  }
}

class _AgentPickerTile extends StatelessWidget {
  const _AgentPickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.options,
    required this.currentId,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<AgentDto> options;
  final String? currentId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final exists = options.any((a) => a.id == currentId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colors.text1)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 11, color: colors.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: DropdownButtonFormField<String?>(
              value: exists ? currentId : null,
              isExpanded: true,
              hint: Text(options.isEmpty ? '无可选 Agent' : '未选择'),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('未选择'),
                ),
                ...options.map(
                  (a) => DropdownMenuItem<String?>(
                    value: a.id,
                    child: Text(a.name,
                        style: TextStyle(color: colors.text1)),
                  ),
                ),
              ],
              onChanged: options.isEmpty ? null : onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 杰理设备链接方式选择（仅 Android 杰理生效）。
class _JieliConnectWayTile extends ConsumerWidget {
  const _JieliConnectWayTile({required this.current});

  final JieliConnectWay current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bluetooth_connected,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('链接方式（杰理）',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colors.text1)),
                    const SizedBox(height: 2),
                    Text('自动按设备广播；BLE / SPP 强制下次连接走该协议',
                        style:
                            TextStyle(fontSize: 11, color: colors.text2)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SegmentedButton<JieliConnectWay>(
            segments: const [
              ButtonSegment(
                value: JieliConnectWay.auto,
                label: Text('自动'),
              ),
              ButtonSegment(
                value: JieliConnectWay.ble,
                label: Text('BLE'),
              ),
              ButtonSegment(
                value: JieliConnectWay.spp,
                label: Text('SPP'),
              ),
            ],
            selected: {current},
            onSelectionChanged: (s) {
              ref
                  .read(configServiceProvider.notifier)
                  .setJieliConnectWay(s.first);
            },
          ),
        ],
      ),
    );
  }
}

// ── Audio output mode segmented button ──
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
            icon: Icon(Icons.auto_mode_outlined, size: 18),
            tooltip: '自动'),
        ButtonSegment(
            value: AudioOutputMode.speaker,
            icon: Icon(Icons.volume_up_outlined, size: 18),
            tooltip: '扬声器'),
        ButtonSegment(
            value: AudioOutputMode.earpiece,
            icon: Icon(Icons.phone_in_talk_outlined, size: 18),
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

// ── 阻塞加载浮层 ───────────────────────────────────────────────────────
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 导出密码对话框 ─────────────────────────────────────────────────────
// 用 StatefulWidget 让 controller 跟随 dialog 生命周期 dispose，
// 避免「await showDialog 返回后立刻 dispose controller」造成的
// `TextEditingController was used after being disposed` 崩溃。
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
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: const Text('确认导出'),
        ),
      ],
    );
  }
}

// ── 导入解密密码对话框 ─────────────────────────────────────────────────
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
          style: FilledButton.styleFrom(backgroundColor: AppTheme.primary),
          child: const Text('解密导入'),
        ),
      ],
    );
  }
}
