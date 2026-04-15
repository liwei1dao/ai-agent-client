import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/themes/app_theme.dart';
import '../providers/agent_list_provider.dart';
import '../providers/agent_tags_provider.dart';
import '../../services/providers/service_library_provider.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_agent_modal.dart';

class AgentPanelScreen extends ConsumerWidget {
  const AgentPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(filteredAgentListProvider);
    final allTags = ref.watch(allAgentTagsProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final services = ref.watch(serviceLibraryProvider);

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
      ),
      body: CustomScrollView(
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(top: 8)),

          // ── Tag filter bar ──
          if (allTags.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  children: [
                    _TagChip(
                      label: '全部',
                      selected: selectedTag == null,
                      onTap: () =>
                          ref.read(selectedTagProvider.notifier).state = null,
                    ),
                    ...allTags.map((tag) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: _TagChip(
                            label: tag,
                            selected: selectedTag == tag,
                            onTap: () => ref
                                .read(selectedTagProvider.notifier)
                                .state = selectedTag == tag ? null : tag,
                          ),
                        )),
                  ],
                ),
              ),
            ),

          const SliverPadding(padding: EdgeInsets.only(top: 6)),

          // ── Agent list ──
          if (agents.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AgentCard(
                    agent: agents[i],
                    services: services,
                    onTap: () {
                      final type = agents[i].type;
                      final id = agents[i].id;
                      if (type == 'translate' || type == 'ast-translate') {
                        context.push('/agent/$id/translate');
                      } else {
                        context.push('/agent/$id/chat');
                      }
                    },
                    onDelete: () => ref
                        .read(agentListProvider.notifier)
                        .removeAgent(agents[i].id),
                  ),
                  childCount: agents.length,
                ),
              ),
            ),

          // ── Empty state ──
          if (agents.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.only(top: 40),
                  child: Column(
                    children: [
                      Icon(Icons.smart_toy_outlined,
                          size: 48,
                          color: AppTheme.text2.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      Text(
                        selectedTag != null
                            ? '标签「$selectedTag」下没有 Agent'
                            : '还没有 Agent，点击 + 创建',
                        style:
                            const TextStyle(fontSize: 13, color: AppTheme.text2),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Add new agent card ──
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () => _showAddAgent(context),
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 10),
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
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.text2)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
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

// ── Tag filter chip ──────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppTheme.text2,
          ),
        ),
      ),
    );
  }
}
