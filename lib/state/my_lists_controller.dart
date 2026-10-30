import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/graphql/models/media_list_entry.dart' show MediaListStatus;
import '../core/utils/app_exception.dart';
import '../data/models/account.dart' show ScoreFormat;
import '../data/models/media.dart';
import '../data/models/media_entry.dart';
import '../data/repositories/tracking_repository.dart';
import 'load_state.dart';
import 'media_providers.dart' show mediaRepositoryProvider;
import 'providers.dart';
import 'tracked_entries_notifier.dart' show optimisticEntriesProvider;

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
  }) async {
    final entry = await _repo.addOrUpdate(
      media: media,
      status: status,
      progress: progress,
      score: score,
      notes: notes,
    );
    _mirror(entry, progress: progress != null, status: true, score: score != null);
    return entry;
  }

  Future<void> setStatus(int mediaId, ListStatus status) async {
    final entry = await _repo.setStatus(mediaId, status);
    _mirror(entry, status: true);
  }

  Future<void> setProgress(int mediaId, int progress) async {
    final entry = await _repo.setProgress(mediaId, progress);
    // The local repo may also change the status (e.g. last episode -> done).
    _mirror(entry, progress: true, status: true);
  }

  Future<void> incrementProgress(int mediaId) async {
    final entry = await _repo.incrementProgress(mediaId);
    _mirror(entry, progress: true, status: true);
  }

  Future<void> setScore(int mediaId, int? score) async {
    final entry = await _repo.setScore(mediaId, score);
    _mirror(entry, score: true);
  }

  /// Local tracking stays the source of truth for the UI (guests keep working
  /// exactly as before). When signed in, the same edit is also synced to
  /// AniList through the debounced, absolute-value optimistic notifier. A sync
  /// failure never fails the local edit; it surfaces via
  /// `entrySyncErrorProvider`.
  ///
  /// Not mirrored yet: removing an entry (needs the AniList list-entry id).
  void _mirror(
    MediaEntry entry, {
    bool progress = false,
    bool status = false,
    bool score = false,
  }) {
    if (ref.read(authRepositoryProvider).accessToken == null) return;
    unawaited(
      ref.read(optimisticEntriesProvider.notifier).applyEdit(
        mediaId: entry.mediaId,
        progress: progress ? entry.progress : null,
        status: status ? _toRemote(entry.status) : null,
        score10: score ? (entry.score ?? 0) : null,
      ),
    );
  }

  static MediaListStatus _toRemote(ListStatus s) => switch (s) {
    ListStatus.watching => MediaListStatus.current,
    ListStatus.planning => MediaListStatus.planning,
    ListStatus.completed => MediaListStatus.completed,
    ListStatus.paused => MediaListStatus.paused,
    ListStatus.dropped => MediaListStatus.dropped,
  };

  Future<void> remove(int mediaId) async {
    await _repo.remove(mediaId);
    if (ref.read(authRepositoryProvider).accessToken == null) return;
    unawaited(ref.read(optimisticEntriesProvider.notifier).removeEntry(mediaId));
  }

  /// Copies the signed-in user's AniList anime and manga lists into the local
  /// list. Only titles that are not tracked locally are added, so nothing the
  /// user already has here is overwritten. Goes straight to the local
  /// repository (not [addTo]) so the import is never echoed back to AniList.
  ///
  /// Returns how many titles were added. Throws [AppException] when signed
  /// out or when AniList cannot be reached.
  Future<int> importFromAniList() async {
    final user = await ref.read(authStateProvider.future);
    final token = ref.read(authRepositoryProvider).accessToken;
    if (user == null || token == null) {
      throw const AppException(
        ErrorKind.unauthorized,
        'Sign in with AniList to import your list',
      );
    }
    final media = ref.read(mediaRepositoryProvider);
    final incoming = <MediaEntry>[];
    for (final type in MediaType.values) {
      final remote = await media.accountList(
        userId: user.id,
        token: token,
        type: type,
      );
      for (final r in remote) {
        final now = DateTime.now();
        final status = _fromRemote(r.status);
        incoming.add(
          MediaEntry(
            mediaId: r.media.id,
            type: r.media.type,
            title: r.media.title,
            coverUrl: r.media.coverUrl,
            totalUnits: r.media.totalUnits,
            status: status,
            progress: r.progress,
            score: _scoreTo10(r.score, r.scoreFormat),
            startedAt: r.progress > 0 ? (r.updatedAt ?? now) : null,
            completedAt: status == ListStatus.completed
                ? (r.updatedAt ?? now)
                : null,
            createdAt: r.updatedAt ?? now,
            updatedAt: r.updatedAt ?? now,
          ),
        );
      }
    }
    return _repo.importEntries(incoming);
  }

  static ListStatus _fromRemote(String wire) => wire.toUpperCase() == 'REPEATING'
      ? ListStatus.watching
      : ListStatus.fromWire(wire);

  /// Converts an AniList score in the user's own format to the local 0-10
  /// scale (null when unrated).
  static int? _scoreTo10(double? score, ScoreFormat format) {
    if (score == null || score <= 0) return null;
    final value = switch (format) {
      ScoreFormat.point100 => score / 10,
      ScoreFormat.point10Decimal || ScoreFormat.point10 => score,
      ScoreFormat.point5 => score * 2,
      ScoreFormat.point3 => score * 3,
    };
    return value.round().clamp(1, 10);
  }

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
