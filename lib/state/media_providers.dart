import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/anilist/anilist_client.dart';
import '../data/models/account.dart';
import '../data/models/airing_schedule.dart';
import '../data/models/media.dart';
import '../data/models/people.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/media_repository.dart';
import 'providers.dart';

/// Shared AniList HTTP client and repository.
///
/// The client is intentionally kept alive for the app lifetime (single
/// socket pool); [MediaRepository] adds its own TTL cache on top so
/// repeated rail/detail visits do not burn the 90 req/min AniList budget.
final aniListClientProvider = Provider<AniListClient>((ref) {
  final client = AniListClient();
  ref.onDispose(client.close);
  return client;
});

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  // `read` would also work; `watch` keeps rails in sync if the client
  // is ever overridden in tests.
  return MediaRepository(ref.watch(aniListClientProvider));
});

/// Home page rails.
 ///
 /// `autoDispose` so rails are released when the home screen is gone;
 /// data is re-fetched on return (backed by the repository TTL cache,
 /// so revisits are usually instant and network-free).
enum MediaRail {
  trendingAnime,
  trendingManga,
  popularThisSeason,
  airingNow,
  allTimePopular,
  upcoming,
  topRated,
  topCompleted,
  newChapters,
}

final mediaRailProvider =
    FutureProvider.family.autoDispose<MediaPage, (MediaRail, MediaType)>((
      ref,
      key,
    ) async {
  final (rail, type) = key;
  final repo = ref.watch(mediaRepositoryProvider);
  BrowseQuery query({MediaSort sort = MediaSort.trending, MediaStatus? status}) {
    return BrowseQuery(type: type, sort: sort, status: status, perPage: 12);
  }

  switch (rail) {
    case MediaRail.trendingAnime:
    case MediaRail.trendingManga:
      return repo.trending(type: type, perPage: 12);
    case MediaRail.popularThisSeason:
      if (type == MediaType.manga) {
        // Seasons are anime-only on AniList; manga falls back to popularity.
        return repo.browse(query(sort: MediaSort.popularity));
      }
      final now = DateTime.now();
      return repo.browse(
        BrowseQuery(
          type: type,
          sort: MediaSort.popularity,
          // AniList needs a season together with seasonYear for anime.
          season: currentSeason(now.month),
          seasonYear: now.year,
          perPage: 12,
        ),
      );
    case MediaRail.airingNow:
      return repo.browse(query(status: MediaStatus.releasing));
    case MediaRail.allTimePopular:
      return repo.browse(query(sort: MediaSort.popularity));
    case MediaRail.upcoming:
      return repo.browse(
        query(sort: MediaSort.popularity, status: MediaStatus.notYetReleased),
      );
    case MediaRail.topRated:
      return repo.browse(query(sort: MediaSort.score));
    case MediaRail.topCompleted:
      return repo.browse(
        query(sort: MediaSort.score, status: MediaStatus.finished),
      );
    case MediaRail.newChapters:
      return repo.browse(query(sort: MediaSort.updated));
  }
});

/// Every episode airing today (midnight to midnight, local time).
///
/// Follows the schedule's pages (rather than one capped page), so a busy day
/// is complete. `autoDispose` for the same reason as [mediaRailProvider]; the
/// repository TTL cache keeps revisits cheap.
final airingTodayProvider =
    FutureProvider.autoDispose<List<AiringScheduleItem>>((ref) async {
  final repo = ref.watch(mediaRepositoryProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  // Calendar arithmetic, not `Duration(days: 1)` (25h/23h days at DST changes).
  final end = DateTime(now.year, now.month, now.day + 1);
  return repo.airingScheduleAll(
    from: start.millisecondsSinceEpoch ~/ 1000,
    to: end.millisecondsSinceEpoch ~/ 1000,
  );
});

/// Anime season for a calendar month number.
MediaSeason currentSeason(int month) {
  if (month <= 2 || month == 12) return MediaSeason.winter;
  if (month <= 5) return MediaSeason.spring;
  if (month <= 8) return MediaSeason.summer;
  return MediaSeason.fall;
}

/// Media detail for a title id.
final mediaDetailProvider = FutureProvider.family.autoDispose<Media, int>((
  ref,
  id,
) async {
  final repo = ref.watch(mediaRepositoryProvider);
  return repo.mediaDetail(id);
});

/// Staff profile + one page of their titles, keyed by `(staffId, page)`.
final staffWorksProvider =
    FutureProvider.family.autoDispose<PersonWorks, (int, int)>((ref, key) {
  final (id, page) = key;
  return ref.watch(mediaRepositoryProvider).staffWorks(id, page: page);
});

/// Character profile + one page of their series, keyed by `(id, page)`.
final characterWorksProvider =
    FutureProvider.family.autoDispose<PersonWorks, (int, int)>((ref, key) {
  final (id, page) = key;
  return ref.watch(mediaRepositoryProvider).characterWorks(id, page: page);
});

/// Studio profile + one page of its titles, keyed by `(id, page)`.
final studioWorksProvider =
    FutureProvider.family.autoDispose<PersonWorks, (int, int)>((ref, key) {
  final (id, page) = key;
  return ref.watch(mediaRepositoryProvider).studioWorks(id, page: page);
});

/// AniList notifications for the signed-in user (empty for guests).
final notificationsProvider =
    FutureProvider.autoDispose<List<UserNotification>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const [];
  final token = ref.read(authRepositoryProvider).accessToken;
  if (token == null) return const [];
  return ref.watch(mediaRepositoryProvider)
      .notifications(userId: user.id, token: token);
});

/// Last profile statistics this browser saved, so a reload paints the
/// profile panels immediately instead of waiting for AniList.
///
/// Keyed by account (a different user never sees it) and cleared together
/// with the session on sign-out.
final viewerProfileSnapshotProvider = Provider<ViewerProfile?>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final raw = prefs.getString(
    AniListAuthRepository.profileSnapshotKey(user.id),
  );
  if (raw == null || raw.isEmpty) return null;
  try {
    return ViewerProfile.fromJson(jsonDecode(raw));
  } on Object {
    return null; // Corrupt snapshot: ignore and refetch.
  }
});

/// Profile header + anime stats for the signed-in user (null for guests).
///
/// A successful fetch is written back to local storage (see
/// [viewerProfileSnapshotProvider]) so the next cold start shows it at once
/// and a failed refresh degrades to last-known data rather than an empty page.
final viewerProfileProvider =
    FutureProvider.autoDispose<ViewerProfile?>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return null;
  final token = ref.read(authRepositoryProvider).accessToken;
  if (token == null) return null;
  final profile = await ref
      .watch(mediaRepositoryProvider)
      .viewerProfile(userId: user.id, token: token);
  try {
    await ref.read(sharedPreferencesProvider).setString(
      AniListAuthRepository.profileSnapshotKey(user.id),
      jsonEncode(profile.toJson()),
    );
  } on Object {
    // Storage may be full or blocked; the snapshot is an optimization, so a
    // failure here must not fail the request that just succeeded.
  }
  return profile;
});

/// One section of the signed-in user's AniList anime list (empty for guests).
///
/// Keyed by [ProfileSection] so the profile page can prefetch nothing and the
/// list screen fetches exactly the section it is showing.
final accountListProvider =
    FutureProvider.family.autoDispose<List<AccountListEntry>, ProfileSection>((
      ref,
      section,
    ) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const [];
  final token = ref.read(authRepositoryProvider).accessToken;
  if (token == null) return const [];
  final repo = ref.watch(mediaRepositoryProvider);
  if (section.favouritesOnly) {
    final page = await repo.favouriteAnime(userId: user.id, token: token);
    return [
      for (final media in page.items)
        AccountListEntry(media: media, status: ''),
    ];
  }
  return repo.accountList(
    userId: user.id,
    token: token,
    status: section.status,
  );
});

/// The signed-in user's recent AniList activity (empty for guests).
final activityProvider =
    FutureProvider.autoDispose<List<UserActivity>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const [];
  final token = ref.read(authRepositoryProvider).accessToken;
  if (token == null) return const [];
  return ref.watch(mediaRepositoryProvider).activities(userId: user.id, token: token);
});
