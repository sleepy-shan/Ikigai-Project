import 'dart:async';
import 'dart:math' as math;

import 'package:graphql_flutter/graphql_flutter.dart' show MutationOptions;
import '../data/graphql/graphql_bootstrap.dart' show FreshnessTracker;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exception.dart';
import '../data/graphql/anilist_documents.dart';
import '../data/graphql/models/media_list_entry.dart';
import 'anime_providers.dart';
import 'graphql_providers.dart';
import 'providers.dart';

/// Optimistic overlay: edits the user just made that AniList has not
/// confirmed yet. The UI never watches this directly; it watches
/// [displayEntryProvider], which prefers the overlay and falls back to the
/// server state. Rollback is therefore "delete the overlay entry", with no
/// snapshot bookkeeping.
class OptimisticEntries extends Notifier<Map<int, MediaListEntry>> {
  final Map<int, Timer> _timers = {};
  final Set<int> _inFlight = {};

  /// Taps within this window collapse into ONE mutation carrying the latest
  /// absolute progress. Ten quick taps cost one request, not ten.
  static const Duration _debounce = Duration(milliseconds: 500);

  @override
  Map<int, MediaListEntry> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    // The overlay belongs to one account.
    ref.listen<int?>(authStateProvider.select((a) => a.value?.id), (_, _) {
      for (final t in _timers.values) {
        t.cancel();
      }
      _timers.clear();
      state = const {};
    });
    return const {};
  }

  /// "+1 episode / chapter". Returns false when the tap was ignored.
  ///
  /// Throws [AppException] (unauthorized) when signed out so the caller can
  /// open the sign-in dialog.
  bool incrementProgress({required int mediaId, int? totalUnits}) {
    if (ref.read(authRepositoryProvider).accessToken == null) {
      throw const AppException(
        ErrorKind.unauthorized,
        'Sign in with AniList to sync your list',
      );
    }

    // Never build on a guess. If the server entry has not loaded yet we would
    // send progress 1 over a real progress of 11. Disable the button while
    // `trackedEntryProvider(id)` is loading, and refuse here too.
    final server = ref.read(trackedEntryProvider(mediaId));
    final MediaListEntry base;
    if (state[mediaId] != null) {
      base = state[mediaId]!;
    } else if (server.hasValue) {
      base = server.requireValue.data ?? MediaListEntry(mediaId: mediaId);
    } else {
      return false;
    }

    final total = (totalUnits != null && totalUnits > 0) ? totalUnits : null;
    final next = total == null
        ? base.progress + 1
        : math.min(base.progress + 1, total);
    if (next == base.progress) return false; // already at the last unit

    final status = (total != null && next >= total)
        ? MediaListStatus.completed
        : (base.status == MediaListStatus.current ||
                base.status == MediaListStatus.repeating)
            ? base.status
            : MediaListStatus.current; // planning/paused/dropped/new -> current

    // 1) Optimistic: UI updates this frame.
    state = {...state, mediaId: base.copyWith(progress: next, status: status)};
    // 2) Sync later, coalesced.
    _schedule(mediaId);
    return true;
  }

  /// Mirrors an edit the user made in the local list to AniList.
  ///
  /// Silent no-op for guests. Only the fields passed are changed: everything
  /// else is taken from the SERVER entry (waited for, never guessed), so
  /// adding a title locally can never overwrite progress or score the user
  /// already has on AniList. If the server entry cannot be read, nothing is
  /// sent.
  ///
  /// [score10] is the local 0-10 score; AniList gets it as POINT_100.
  Future<void> applyEdit({
    required int mediaId,
    int? progress,
    MediaListStatus? status,
    int? score10,
  }) async {
    if (ref.read(authRepositoryProvider).accessToken == null) return;

    MediaListEntry? base = state[mediaId];
    if (base == null) {
      // Keep the autoDispose provider alive while we wait for its first value.
      final sub = ref.listen(trackedEntryProvider(mediaId), (_, _) {});
      try {
        final server = await ref.read(trackedEntryProvider(mediaId).future);
        base = server.data ?? MediaListEntry(mediaId: mediaId);
      } on Object {
        return; // no server truth, no write
      } finally {
        sub.close();
      }
    }
    if (!ref.mounted) return;

    // An edit may have landed while we were waiting; prefer the newest.
    base = state[mediaId] ?? base;
    state = {
      ...state,
      mediaId: base.copyWith(
        progress: progress ?? base.progress,
        status: status ?? base.status,
        score: score10 == null ? base.score : (score10 * 10).toDouble(),
      ),
    };
    _schedule(mediaId);
  }

  /// Forces the next read of the server entry to hit the network. Without
  /// forgetting the freshness stamp, `invalidate` would be answered by the
  /// (now outdated) cache for up to the TTL.
  void _refetchServerEntry(int mediaId) {
    final userId = ref.read(authStateProvider).value?.id;
    if (userId != null) {
      ref.read(gqlStorageProvider).freshness.forget(
        FreshnessTracker.keyFor('MyEntry:$userId', {'id': mediaId}),
      );
    }
    ref.invalidate(trackedEntryProvider(mediaId));
  }

  /// Deletes the AniList entry for [mediaId] (mirror of a local removal).
  ///
  /// Silent no-op for guests and for titles that are not on the user's AniList
  /// list. Any queued edit for the title is dropped first, otherwise it would
  /// re-create the entry a moment later.
  Future<void> removeEntry(int mediaId) async {
    if (ref.read(authRepositoryProvider).accessToken == null) return;

    _timers.remove(mediaId)?.cancel();
    if (state.containsKey(mediaId)) {
      state = {...state}..remove(mediaId);
    }

    int? listEntryId;
    final sub = ref.listen(trackedEntryProvider(mediaId), (_, _) {});
    try {
      final server = await ref.read(trackedEntryProvider(mediaId).future);
      listEntryId = server.data?.id;
    } on Object {
      return; // cannot tell what is on AniList: do not guess
    } finally {
      sub.close();
    }
    if (listEntryId == null || !ref.mounted) return;

    try {
      final result = await ref.read(graphQLClientProvider).mutate(
        MutationOptions(
          document: deleteMediaListEntryDoc,
          variables: {'id': listEntryId},
        ),
      );
      if (result.hasException) throw toAppError(result.exception!);
      if (!ref.mounted) return;
      _refetchServerEntry(mediaId);
    } on Object catch (error) {
      if (!ref.mounted) return;
      ref
          .read(entrySyncErrorProvider.notifier)
          .report(error is AppException ? error : AppException(ErrorKind.unknown, '$error'));
    }
  }

  void _schedule(int mediaId) {
    _timers[mediaId]?.cancel();
    _timers[mediaId] = Timer(_debounce, () => _flush(mediaId));
  }

  Future<void> _flush(int mediaId) async {
    final pending = state[mediaId];
    if (pending == null) return;
    if (_inFlight.contains(mediaId)) {
      _schedule(mediaId); // wait for the current request, then send latest
      return;
    }
    _inFlight.add(mediaId);

    try {
      final result = await ref.read(graphQLClientProvider).mutate(
        MutationOptions(
          document: saveMediaListEntryDoc,
          variables: {
            'mediaId': mediaId,
            'progress': pending.progress, // absolute => safe to retry
            'status': pending.status.wire,
            'scoreRaw': pending.score.round(), // POINT_100
          },
        ),
      );
      final saved = result.data?['SaveMediaListEntry'];
      if (result.hasException || saved == null) {
        throw result.exception != null
            ? toAppError(result.exception!)
            : const AppException(ErrorKind.server, 'AniList did not save the entry');
      }
      if (!ref.mounted) return;

      // The mutation result already updated the cached `MediaList:<id>`, so
      // the server stream re-emits on its own. A brand-new entry is the
      // exception: `Media.mediaListEntry` was null in the cache, so refetch.
      if (pending.isNew) _refetchServerEntry(mediaId);

      // Only drop the overlay if no newer tap arrived meanwhile.
      if (state[mediaId] == pending) {
        state = {...state}..remove(mediaId);
      }
    } on Object catch (error) {
      if (!ref.mounted) return;
      // Roll back ONLY if nothing newer is pending; otherwise the newer
      // value is already scheduled and will retry the whole absolute state.
      if (state[mediaId] == pending) {
        state = {...state}..remove(mediaId);
      }
      ref
          .read(entrySyncErrorProvider.notifier)
          .report(error is AppException ? error : AppException(ErrorKind.unknown, '$error'));
    } finally {
      _inFlight.remove(mediaId);
    }
  }
}

final optimisticEntriesProvider =
    NotifierProvider<OptimisticEntries, Map<int, MediaListEntry>>(
      OptimisticEntries.new,
    );

/// What the "+1" button and progress bar should render.
final displayEntryProvider = Provider.autoDispose
    .family<MediaListEntry?, int>((ref, mediaId) {
      final overlay = ref.watch(
        optimisticEntriesProvider.select((m) => m[mediaId]),
      );
      if (overlay != null) return overlay;
      return ref.watch(trackedEntryProvider(mediaId)).value?.data;
    });

/// One-shot failures from background sync. Listen once near the app shell and
/// show a snackbar:
///   ref.listen(entrySyncErrorProvider, (_, e) { if (e != null) showError(e); });
class EntrySyncError extends Notifier<AppException?> {
  @override
  AppException? build() => null;
  void report(AppException e) => state = e;
}

final entrySyncErrorProvider =
    NotifierProvider<EntrySyncError, AppException?>(EntrySyncError.new);
