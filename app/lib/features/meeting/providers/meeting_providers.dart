import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../../auth/services/app_config_service.dart';
import '../data/meeting_repository.dart';
import '../data/meeting_storage.dart';
import '../models/meeting.dart';
import '../models/meeting_detail.dart';
import '../models/template.dart';
import '../services/cos_uploader.dart';
import '../services/meeting_api.dart';
import '../services/meeting_remote_service.dart';
import '../services/meeting_upload_coordinator.dart';

final meetingStorageProvider = Provider<MeetingStorage>((_) => MeetingStorage());

final meetingApiProvider = Provider<MeetingApi>((_) => MeetingApi.create());

final meetingRemoteServiceProvider =
    Provider<MeetingRemoteService>((_) => MeetingRemoteService());

final cosUploaderProvider = Provider<CosUploader>(
    (ref) => CosUploader(ref.watch(appConfigServiceProvider)));

final meetingUploadCoordinatorProvider =
    Provider<MeetingUploadCoordinator>((ref) {
  final coord = MeetingUploadCoordinator(
    repo: ref.watch(meetingRepositoryProvider),
    remote: ref.watch(meetingRemoteServiceProvider),
    cos: ref.watch(cosUploaderProvider),
    readAuth: () => ref.read(authProvider),
  );
  ref.onDispose(coord.dispose);
  return coord;
});

final meetingRepositoryProvider = Provider<MeetingRepository>((ref) {
  final repo = MeetingRepository(ref.watch(meetingStorageProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// Live list of meetings.
final meetingListProvider =
    AsyncNotifierProvider<MeetingListNotifier, List<Meeting>>(
        MeetingListNotifier.new);

class MeetingListNotifier extends AsyncNotifier<List<Meeting>> {
  @override
  Future<List<Meeting>> build() async {
    final repo = ref.watch(meetingRepositoryProvider);
    final sub = repo.changes.listen((list) {
      state = AsyncData(list);
    });
    ref.onDispose(sub.cancel);
    return repo.list();
  }

  Future<void> refresh() async {
    final repo = ref.read(meetingRepositoryProvider);
    final list = await repo.list(forceReload: true);
    state = AsyncData(list);
  }

  Future<void> add(Meeting m) async {
    await ref.read(meetingRepositoryProvider).upsert(m);
  }

  Future<void> delete(String id) async {
    await ref.read(meetingRepositoryProvider).delete(id);
  }

  Future<void> deleteMany(Iterable<String> ids) async {
    await ref.read(meetingRepositoryProvider).deleteMany(ids);
  }

  Future<void> rename(String id, String title) async {
    await ref.read(meetingRepositoryProvider).rename(id, title);
  }

  Future<void> toggleMark(String id) async {
    await ref.read(meetingRepositoryProvider).toggleMark(id);
  }
}

/// Detail per meeting id.
final meetingDetailProvider = FutureProvider.family
    .autoDispose<MeetingDetail, String>((ref, id) async {
  final repo = ref.watch(meetingRepositoryProvider);
  return repo.readDetail(id);
});

/// Templates (builtin + custom).
final meetingTemplatesProvider =
    FutureProvider.autoDispose<List<MeetingTemplate>>((ref) async {
  final repo = ref.watch(meetingRepositoryProvider);
  return repo.listTemplates();
});

/// Filter / search ui state for the home screen.
class MeetingListFilter {
  const MeetingListFilter({
    this.query = '',
    this.markedOnly = false,
    this.audioType,
  });

  final String query;
  final bool markedOnly;
  final MeetingAudioType? audioType;

  MeetingListFilter copyWith({
    String? query,
    bool? markedOnly,
    MeetingAudioType? Function()? audioType,
  }) =>
      MeetingListFilter(
        query: query ?? this.query,
        markedOnly: markedOnly ?? this.markedOnly,
        audioType: audioType == null ? this.audioType : audioType(),
      );
}

final meetingListFilterProvider =
    StateProvider<MeetingListFilter>((_) => const MeetingListFilter());

/// Filtered list view derived from [meetingListProvider] and the filter.
final filteredMeetingListProvider = Provider<AsyncValue<List<Meeting>>>((ref) {
  final asyncList = ref.watch(meetingListProvider);
  final filter = ref.watch(meetingListFilterProvider);
  return asyncList.whenData((list) {
    Iterable<Meeting> it = list;
    if (filter.query.isNotEmpty) {
      final q = filter.query.toLowerCase();
      it = it.where((m) => m.title.toLowerCase().contains(q));
    }
    if (filter.markedOnly) it = it.where((m) => m.marked);
    if (filter.audioType != null) {
      it = it.where((m) => m.audioType == filter.audioType);
    }
    return it.toList();
  });
});

/// Multi-select state for the home list.
final meetingSelectionProvider =
    StateNotifierProvider<MeetingSelectionNotifier, MeetingSelectionState>(
        (_) => MeetingSelectionNotifier());

class MeetingSelectionState {
  const MeetingSelectionState({this.active = false, this.ids = const {}});
  final bool active;
  final Set<String> ids;

  MeetingSelectionState copyWith({bool? active, Set<String>? ids}) =>
      MeetingSelectionState(
          active: active ?? this.active, ids: ids ?? this.ids);
}

class MeetingSelectionNotifier extends StateNotifier<MeetingSelectionState> {
  MeetingSelectionNotifier() : super(const MeetingSelectionState());

  void enter(String firstId) {
    state = MeetingSelectionState(active: true, ids: {firstId});
  }

  void exit() => state = const MeetingSelectionState();

  void toggle(String id) {
    final next = {...state.ids};
    if (!next.add(id)) next.remove(id);
    if (next.isEmpty) {
      state = const MeetingSelectionState();
    } else {
      state = state.copyWith(ids: next);
    }
  }

  void selectAll(Iterable<String> ids) {
    state = state.copyWith(active: true, ids: ids.toSet());
  }
}
