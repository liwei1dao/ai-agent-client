import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/agent_list_provider.dart';
import '../providers/remote_agent_provider.dart';
import '../../services/providers/service_library_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_agent_modal.dart';

class AgentPanelScreen extends ConsumerStatefulWidget {
  const AgentPanelScreen({super.key});

  @override
  ConsumerState<AgentPanelScreen> createState() => _AgentPanelScreenState();
}

class _AgentPanelScreenState extends ConsumerState<AgentPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localAgents = ref.watch(localAgentListProvider);
    final remoteAgents = ref.watch(remoteAgentListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的 Agents',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon:
                const Icon(Icons.add_circle_outline, color: AppTheme.primary),
            onPressed: () => _showAddAgent(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.text2,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 2.5,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.phone_android, size: 15),
                  const SizedBox(width: 5),
                  Text('本地 (${localAgents.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_outlined, size: 15),
                  const SizedBox(width: 5),
                  Text('远程 (${remoteAgents.length})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _LocalAgentTab(),
          _RemoteAgentTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAgent(context),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddAgent(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddAgentModal(),
    );
  }
}

// ── 本地 Agent Tab ──────────────────────────────────────────────────────────

class _LocalAgentTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localAgents = ref.watch(localAgentListProvider);
    final services = ref.watch(serviceLibraryProvider);

    return CustomScrollView(
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 14)),
        if (localAgents.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => AgentCard(
                  agent: localAgents[i],
                  services: services,
                  onTap: () =>
                      context.push('/agent/${localAgents[i].id}/chat'),
                  onDelete: () => ref
                      .read(agentListProvider.notifier)
                      .removeAgent(localAgents[i].id),
                ),
                childCount: localAgents.length,
              ),
            ),
          ),

        // 添加新 Agent 按钮
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverToBoxAdapter(
            child: GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const AddAgentModal(),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppTheme.borderColor,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignInside),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.borderColor,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                ),
                child: Column(
                  children: [
                    Text('+',
                        style: TextStyle(
                            fontSize: 28,
                            color: AppTheme.text2.withValues(alpha: 0.6),
                            fontWeight: FontWeight.w300)),
                    const SizedBox(height: 4),
                    const Text('添加新 Agent',
                        style: TextStyle(fontSize: 12, color: AppTheme.text2)),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }
}

// ── 远程 Agent Tab ──────────────────────────────────────────────────────────

class _RemoteAgentTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteAgents = ref.watch(remoteAgentListProvider);
    final services = ref.watch(serviceLibraryProvider);
    final syncState = ref.watch(remoteSyncStateProvider);
    final settings = ref.watch(settingsProvider);

    return CustomScrollView(
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: 8)),

        // 操作按钮栏
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Row(
              children: [
                // 同步按钮
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    onPressed: syncState.syncing
                        ? null
                        : (settings.isVoitransConfigured
                            ? () => ref
                                .read(remoteSyncStateProvider.notifier)
                                .sync()
                            : null),
                    icon: syncState.syncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : const Icon(Icons.sync, size: 16),
                    label: Text(
                      syncState.syncing ? '同步中' : '同步',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 同步错误提示
        if (syncState.lastError != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: Color(0xFFEF4444)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncState.lastError ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFFDC2626)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 远程 Agent 列表
        if (remoteAgents.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final agent = remoteAgents[i];
                  return AgentCard(
                    agent: agent,
                    services: services,
                    isRemote: true,
                    onTap: () => context.push('/agent/${agent.id}/chat'),
                  );
                },
                childCount: remoteAgents.length,
              ),
            ),
          ),

        // 远程为空时的提示
        if (remoteAgents.isEmpty && !syncState.syncing)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.borderColor,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 36,
                        color: AppTheme.text2.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text(
                      settings.isVoitransConfigured
                          ? '暂无远程 Agent，点击同步按钮获取'
                          : '请先在设置中配置 VoiTrans 平台',
                      style:
                          const TextStyle(fontSize: 13, color: AppTheme.text2),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 同步中加载指示
        if (syncState.syncing)
          const SliverPadding(
            padding: EdgeInsets.symmetric(vertical: 20),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
      ],
    );
  }

}
