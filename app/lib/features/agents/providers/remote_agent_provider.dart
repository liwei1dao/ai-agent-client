import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_db/local_db.dart';
import 'agent_list_provider.dart';
import '../../settings/providers/settings_provider.dart';

bool _isRemoteAgent(AgentDto agent) {
  try {
    final cfg = jsonDecode(agent.configJson) as Map<String, dynamic>;
    return cfg['source'] == 'voitrans';
  } catch (_) {
    return false;
  }
}

/// 本地 Agent（用户手动创建）
final localAgentListProvider = Provider<List<AgentDto>>((ref) {
  final all = ref.watch(agentListProvider);
  return all.where((a) => !_isRemoteAgent(a)).toList();
});

/// 远程 Agent（VoiTrans 平台同步）
final remoteAgentListProvider = Provider<List<AgentDto>>((ref) {
  final all = ref.watch(agentListProvider);
  return all.where(_isRemoteAgent).toList();
});

/// 远程 Agent 同步状态
class RemoteSyncState {
  const RemoteSyncState({
    this.syncing = false,
    this.lastError,
    this.lastSyncCount,
  });

  final bool syncing;
  final String? lastError;
  final int? lastSyncCount;

  RemoteSyncState copyWith({
    bool? syncing,
    String? lastError,
    int? lastSyncCount,
    bool clearError = false,
  }) =>
      RemoteSyncState(
        syncing: syncing ?? this.syncing,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastSyncCount: lastSyncCount ?? this.lastSyncCount,
      );
}

final remoteSyncStateProvider =
    StateNotifierProvider<RemoteSyncNotifier, RemoteSyncState>((ref) {
  return RemoteSyncNotifier(ref);
});

class RemoteSyncNotifier extends StateNotifier<RemoteSyncState> {
  RemoteSyncNotifier(this._ref) : super(const RemoteSyncState());
  final Ref _ref;

  Future<void> sync() async {
    if (state.syncing) return;
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final count =
          await _ref.read(settingsProvider.notifier).syncVoitransAgents();
      // 刷新 agent 列表
      await _ref.read(agentListProvider.notifier).reload();
      state = RemoteSyncState(lastSyncCount: count);
    } catch (e) {
      state = RemoteSyncState(lastError: e.toString());
    }
  }
}
