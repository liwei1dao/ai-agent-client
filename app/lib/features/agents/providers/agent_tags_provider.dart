import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import 'agent_list_provider.dart';

/// Extract tags from an agent's configJson
List<String> agentTags(AgentDto agent) {
  try {
    final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
    final tags = cfg['tags'] as List?;
    return tags?.cast<String>() ?? [];
  } catch (_) {
    return [];
  }
}

/// All unique tags across all agents, sorted alphabetically
final allAgentTagsProvider = Provider<List<String>>((ref) {
  final agents = ref.watch(agentListProvider);
  final tagSet = <String>{};
  for (final agent in agents) {
    tagSet.addAll(agentTags(agent));
  }
  final sorted = tagSet.toList()..sort();
  return sorted;
});

/// Currently selected tag filter (null = show all)
final selectedTagProvider = StateProvider<String?>((ref) => null);

/// Filtered agent list based on selected tag
final filteredAgentListProvider = Provider<List<AgentDto>>((ref) {
  final agents = ref.watch(agentListProvider);
  final selectedTag = ref.watch(selectedTagProvider);
  if (selectedTag == null) return agents;
  return agents.where((a) => agentTags(a).contains(selectedTag)).toList();
});
