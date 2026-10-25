import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/media.dart';
import '../data/models/media_entry.dart';
import '../data/repositories/tracking_repository.dart';
import 'load_state.dart';
import 'providers.dart';

/// Which entries the "My Lists" screen shows.
enum ListsFilter {
  all('All'),
  watching('Watching / Reading'),
  planning('Planning'),
  completed('Completed'),
  paused('Paused'),
  dropped('Dropped');

  const ListsFilter(this.label);

  final String label;

  static ListsFilter fromStatus(ListStatus status) => switch (status) {
    ListStatus.watching => ListsFilter.watching,
    ListStatus.planning => ListsFilter.planning,
    ListStatus.completed => ListsFilter.completed,
    ListStatus.paused => ListsFilter.paused,
    ListStatus.dropped => ListsFilter.dropped,
  };
}

/// Sort orders offered by the "My Lists" screen.
enum ListsSort {
  updated('Recently updated'),
  title('Title'),
  score('Score'),
  progress('Progress');

  const ListsSort(this.label);

  final String label;
}

class MyListsState {
  const MyListsState({
    this.status = LoadStatus.initial,
    this.entries = const [],
    this.filter = ListsFilter.all,
    this.sort = ListsSort.updated,
    this.errorMessage,
  });

  final LoadStatus status;
  final List<MediaEntry> entries;
  final ListsFilter filter;
  final ListsSort sort;
  final String? errorMessage;

  /// Entries after applying the active filter and sort.
  List<MediaEntry> get visibleEntries {
    final filtered = switch (filter) {
      ListsFilter.all => entries,
      ListsFilter.watching => entries.where(
        (e) => e.status == ListStatus.watching,
      ),
      ListsFilter.planning => entries.where(
        (e) => e.status == ListStatus.planning,
      ),
      ListsFilter.completed => entries.where(
        (e) => e.status == ListStatus.completed,
      ),
      ListsFilter.paused => entries.where((e) => e.status == ListStatus.paused),
      ListsFilter.dropped => entries.where(
        (e) => e.status == ListStatus.dropped,
      ),
    };
    final list = [...filtered];
    switch (sort) {
      case ListsSort.updated:
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ListsSort.title:
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case ListsSort.score:
        list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
      case ListsSort.progress:
        list.sort((a, b) {
          final aFrac = a.fraction ?? -1;
          final bFrac = b.fraction ?? -1;
          return bFrac.compareTo(aFrac);
        });
    }
    return list;
  }

  int countFor(ListsFilter target) => switch (target) {
    ListsFilter.all => entries.length,
    _ =>
      entries.where((e) => ListsFilter.fromStatus(e.status) == target).length,
  };

  MediaEntry? entryFor(int mediaId) {
    for (final entry in entries) {
      if (entry.mediaId == mediaId) return entry;
    }
    return null;
  }

  MyListsState copyWith({
    LoadStatus? status,
    List<MediaEntry>? entries,
    ListsFilter? filter,
    ListsSort? sort,
    String? errorMessage,
  }) {
    return MyListsState(
      status: status ?? this.status,
      entries: entries ?? this.entries,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      errorMessage: errorMessage,
    );
  }
}

/// Owns the signed-in user's tracking data.
///
/// Single source of truth for entry state everywhere (detail page, lists,
/// home "continue" rail). Mutations go through [TrackingRepository] which
/// persists them; the repo's stream pushes updates back here.
///
/// Resource handling: the stream subscription is stored and cancelled in
/// [ref.onDispose] so no listener leaks if the provider is ever disposed.
class MyListsController extends Notifier<MyListsState> {
  TrackingRepository get _repo => ref.read(trackingRepositoryProvider);

  @override
  MyListsState build() {
    final sub = _repo.watchEntries().listen(
      (entries) {
        state = state.copyWith(
          status: LoadStatus.success,
          entries: entries,
          errorMessage: null,
        );
      },
      onError: (Object error) {
        state = state.copyWith(
          status: LoadStatus.error,
          errorMessage: 'Could not load your list: $error',
        );
      },
    );
    ref.onDispose(sub.cancel);
    // The stream emits the current entries immediately, so no separate
    // one-shot fetch is needed (avoids the old double-fetch race).
    return const MyListsState(status: LoadStatus.loading);
  }

  void setFilter(ListsFilter filter) => state = state.copyWith(filter: filter);

  void setSort(ListsSort sort) => state = state.copyWith(sort: sort);

  /// Adds or updates the entry for [media].
  Future<MediaEntry> addTo({
    required Media media,
    required ListStatus status,
    int? progress,
    int? score,
    String? notes,
  }) {
    return _repo.addOrUpdate(
      media: media,
      status: status,
      progress: progress,
      score: score,
      notes: notes,
    );
  }

  Future<void> setStatus(int mediaId, ListStatus status) =>
      _repo.setStatus(mediaId, status);

  Future<void> setProgress(int mediaId, int progress) =>
      _repo.setProgress(mediaId, progress);

  Future<void> incrementProgress(int mediaId) =>
      _repo.incrementProgress(mediaId);

  Future<void> setScore(int mediaId, int? score) =>
      _repo.setScore(mediaId, score);

  Future<void> remove(int mediaId) => _repo.remove(mediaId);

  Future<void> clearAll() => _repo.clear();

  Future<void> refresh() async {
    try {
      final entries = await _repo.watchEntries().first;
      state = state.copyWith(
        status: LoadStatus.success,
        entries: entries,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(
        status: LoadStatus.error,
        errorMessage: 'Could not load your list: $error',
      );
    }
  }
}

final myListsControllerProvider =
    NotifierProvider<MyListsController, MyListsState>(MyListsController.new);

/// Filtered + sorted entries, memoized so the O(n log n) work only reruns
/// when entries/filter/sort actually change (not on unrelated rebuilds).
final visibleEntriesProvider = Provider<List<MediaEntry>>((ref) {
  final entries = ref.watch(
    myListsControllerProvider.select((s) => s.entries),
  );
  final filter = ref.watch(myListsControllerProvider.select((s) => s.filter));
  final sort = ref.watch(myListsControllerProvider.select((s) => s.sort));
  final filtered = switch (filter) {
    ListsFilter.all => entries,
    ListsFilter.watching => entries
        .where((e) => e.status == ListStatus.watching)
        .toList(),
    ListsFilter.planning => entries
        .where((e) => e.status == ListStatus.planning)
        .toList(),
    ListsFilter.completed => entries
        .where((e) => e.status == ListStatus.completed)
        .toList(),
    ListsFilter.paused => entries
        .where((e) => e.status == ListStatus.paused)
        .toList(),
    ListsFilter.dropped => entries
        .where((e) => e.status == ListStatus.dropped)
        .toList(),
  };
  final list = [...filtered];
  switch (sort) {
    case ListsSort.updated:
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case ListsSort.title:
      list.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case ListsSort.score:
      list.sort((a, b) => (b.score ?? -1).compareTo(a.score ?? -1));
    case ListsSort.progress:
      list.sort((a, b) {
        final aFrac = a.fraction ?? -1;
        final bFrac = b.fraction ?? -1;
        return bFrac.compareTo(aFrac);
      });
  }
  return list;
});

/// Per-status counts, derived from entries only.
final myListsCountsProvider = Provider<Map<ListsFilter, int>>((ref) {
  final entries = ref.watch(
    myListsControllerProvider.select((s) => s.entries),
  );
  final counts = {for (final f in ListsFilter.values) f: 0};
  counts[ListsFilter.all] = entries.length;
  for (final e in entries) {
    final f = ListsFilter.fromStatus(e.status);
    counts[f] = (counts[f] ?? 0) + 1;
  }
  return counts;
});

/// Entries currently being watched/read, most recent first — powers the
/// "Continue watching / reading" rail on the home dashboard.
///
/// Uses `select` so filter/sort/status-field changes that do not affect
/// entries do not rebuild the rail.
final continueWatchingProvider = Provider<List<MediaEntry>>((ref) {
  final entries = ref.watch(
    myListsControllerProvider.select((s) => s.entries),
  );
  final filtered = entries
      .where((e) => e.status == ListStatus.watching && e.progress > 0)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return filtered;
});
