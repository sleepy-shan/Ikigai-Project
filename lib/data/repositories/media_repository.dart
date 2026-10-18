import '../../core/utils/app_exception.dart';
import '../anilist/anilist_client.dart';
import '../anilist/anilist_mapper.dart';
import '../anilist/anilist_queries.dart';
import '../models/account.dart';
import '../models/airing_schedule.dart';
import '../models/media.dart';
import '../models/people.dart';

/// Search/browse criteria passed to [MediaRepository.browse].
class BrowseQuery {
  const BrowseQuery({
    this.type = MediaType.anime,
    this.sort = MediaSort.trending,
    this.search = '',
    this.genre,
    this.status,
    this.format,
    this.season,
    this.seasonYear,
    this.page = 1,
    this.perPage = 24,
  });

  final MediaType type;
  final MediaSort sort;
  final String search;
  final String? genre;
  final MediaStatus? status;
  final MediaFormat? format;
  final MediaSeason? season;
  final int? seasonYear;
  final int page;
  final int perPage;

  /// True when the query has any active filter (used to show "clear" UI).
  bool get hasFilters =>
      search.trim().isNotEmpty ||
      (genre != null && genre!.isNotEmpty) ||
      status != null ||
      format != null ||
      season != null ||
      seasonYear != null;

  BrowseQuery copyWith({
    MediaType? type,
    MediaSort? sort,
    String? search,
    String? genre,
    MediaStatus? status,
    MediaFormat? format,
    MediaSeason? season,
    int? seasonYear,
    int? page,
    int? perPage,
    bool clearFilters = false,
  }) {
    return BrowseQuery(
      type: type ?? this.type,
      sort: sort ?? this.sort,
      search: search ?? this.search,
      // With clearFilters, null explicitly clears the filter.
      genre: clearFilters ? genre : (genre ?? this.genre),
      status: clearFilters ? status : (status ?? this.status),
      format: clearFilters ? format : (format ?? this.format),
      season: clearFilters ? season : (season ?? this.season),
      seasonYear: clearFilters ? seasonYear : (seasonYear ?? this.seasonYear),
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
    );
  }
}

/// Loads public anime/manga metadata from AniList.
///
/// AniList is treated as the source of truth for metadata; this app never
/// re-hosts its data, it only caches transiently in memory.
///
/// Caching: an in-memory TTL cache (default 5 min) keyed by query avoids
/// burning AniList's 90 req/min budget when revisiting rails, retyping a
/// search, or navigating back to a detail page.
class MediaRepository {
  MediaRepository(this._client, {this.cacheTtl = const Duration(minutes: 5)});

  final AniListClient _client;
  final Duration cacheTtl;
  final Map<String, _CacheEntry<dynamic>> _cache = {};

  /// Maximum number of cached responses.
  static const int _maxCacheEntries = 120;

  T? _get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.time) > cacheTtl) {
      _cache.remove(key);
      return null;
    }
    final Object? value = entry.value as Object?;
    if (value is! T) return null;
    // Re-insert so this key becomes the most recently used: Dart maps keep
    // insertion order, so the first key is always the least recently used.
    _cache
      ..remove(key)
      ..[key] = entry;
    return value;
  }

  void _put(String key, Object value) {
    _cache.remove(key);
    if (_cache.length >= _maxCacheEntries) {
      // Expired entries go first (they would never be served anyway)...
      final now = DateTime.now();
      _cache.removeWhere((_, entry) => now.difference(entry.time) > cacheTtl);
      // ...then evict the least recently used until there is room.
      while (_cache.length >= _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    _cache[key] = _CacheEntry(value, DateTime.now());
  }

  void clearCache() => _cache.clear();

  /// Trending rail for the home page.
  Future<MediaPage> trending({
    MediaType type = MediaType.anime,
    int page = 1,
    int perPage = 10,
  }) async {
    final key = 'trending:${type.name}:$page:$perPage';
    final cached = _get<MediaPage>(key);
    if (cached != null) return cached;
    final data = await _client.query(trendingQuery(detail: false), {
      'page': page,
      'perPage': perPage,
      'type': type.anilistValue,
    });
    final result = _page(data, page);
    // Trending is never legitimately empty — an empty page means a
    // degraded API response, so don't cache it (otherwise the home
    // carousel/rails get stuck showing nothing until the TTL expires).
    if (result.items.isNotEmpty) _put(key, result);
    return result;
  }

  /// Browse results with the full filter set.
  ///
  /// Uses the detailed selection so detail data is already available.
  Future<MediaPage> browse(BrowseQuery query) async {
    final key = _browseKey(query);
    final cached = _get<MediaPage>(key);
    if (cached != null) return cached;
    // AniList treats an explicitly-null `status` as "match nothing", so
    // unset filters are omitted from the variables map entirely.
    final variables = <String, dynamic>{
      'page': query.page,
      'perPage': query.perPage,
      'type': query.type.anilistValue,
      'sort': [query.sort.wire],
      if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
      if (query.genre != null && query.genre!.isNotEmpty) 'genre': query.genre,
      if (query.status != null) 'status': query.status!.wire,
      if (query.format != null && query.format != MediaFormat.unknown)
        'format': query.format!.wire,
      if (query.season != null && query.season != MediaSeason.unknown)
        'season': query.season!.wire,
      if (query.seasonYear != null) 'seasonYear': query.seasonYear,
    };

    // Lists use the light selection (relations/recommendations make a
    // 24-item query far too slow on AniList); the detail page fetches
    // those fields for a single title by id.
    final data = await _client.query(browseQuery(detail: false), variables);
    final result = _page(data, query.page);
    // An empty page that still claims more results is a degraded API
    // response, not a real "no results" — don't cache it or filters and
    // rails get stuck empty until the TTL expires.
    if (result.items.isNotEmpty || !result.hasNextPage) _put(key, result);
    return result;
  }

  /// Full detail for one title.
  Future<Media> mediaDetail(int id) async {
    final key = 'detail:$id';
    final cached = _get<Media>(key);
    if (cached != null) return cached;
    final data = await _client.query(kMediaDetailQuery, {'id': id});
    final media = AniListMapper.single(data['Media']);
    if (media == null) {
      throw AppException(ErrorKind.notFound, 'Title $id is unavailable');
    }
    _put(key, media);
    return media;
  }

  /// AniList caps a page at 50 items.
  static const int _maxPerPage = 50;

  /// Safety cap on pages fetched for one schedule window (50 each).
  static const int _maxSchedulePages = 24;

  /// One page of the airing schedule between [from] and [to] (epoch seconds).
  ///
  /// A busy week has far more than one page of episodes; use
  /// [airingScheduleAll] when the whole window is needed.
  Future<List<AiringScheduleItem>> airingSchedule({
    required int from,
    required int to,
    int page = 1,
    int perPage = _maxPerPage,
  }) async => (await _airingPage(from, to, page, perPage)).items;

  /// Every episode airing between [from] and [to] (epoch seconds).
  ///
  /// Follows `pageInfo.hasNextPage` until the window is exhausted (bounded by
  /// [_maxSchedulePages]), so the calendar shows the whole week and "airing
  /// today" shows every episode instead of the first 24 or 50. Individual
  /// pages are cached, so a retry after a mid-way failure (for example a rate
  /// limit on page 8) resumes from the cache instead of starting over.
  Future<List<AiringScheduleItem>> airingScheduleAll({
    required int from,
    required int to,
  }) async {
    final seen = <int>{};
    final all = <AiringScheduleItem>[];
    for (var page = 1; page <= _maxSchedulePages; page++) {
      final result = await _airingPage(from, to, page, _maxPerPage);
      for (final item in result.items) {
        // Pages can shift if the schedule changes between requests.
        if (seen.add(item.id)) all.add(item);
      }
      if (!result.hasNextPage) break;
    }
    all.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    return List.unmodifiable(all);
  }

  Future<_AiringPage> _airingPage(
    int from,
    int to,
    int page,
    int perPage,
  ) async {
    final key = 'airing:$from:$to:$page:$perPage';
    final cached = _get<_AiringPage>(key);
    if (cached != null) return cached;
    final data = await _client.query(kAiringScheduleQuery, {
      'page': page,
      'perPage': perPage,
      'airingAt_greater': from,
      'airingAt_lesser': to,
    });
    final pageJson = _pageMap(data['Page']);
    final result = _AiringPage(
      items: AniListMapper.airingSchedule(pageJson['airingSchedules']),
      hasNextPage: AniListMapper.pageInfo(pageJson, page).hasNextPage,
    );
    _put(key, result);
    return result;
  }

  /// Safety cap on pages fetched for one week of manga releases.
  static const int _maxMangaPages = 4;

  /// Manga whose start date falls in `[from, to)` (local calendar days).
  ///
  /// The window is applied by AniList (`startDate_greater` / `startDate_lesser`),
  /// so every week returns its own titles. The result is popularity-ordered
  /// and capped at [_maxMangaPages] pages; callers group it by day.
  Future<List<Media>> mangaReleases({
    required DateTime from,
    required DateTime to,
  }) async {
    // Both bounds are exclusive FuzzyDateInts (YYYYMMDD), so the lower bound
    // is the day *before* [from].
    final dayBefore = DateTime(from.year, from.month, from.day - 1);
    final greater = _fuzzyInt(dayBefore);
    final lesser = _fuzzyInt(to);
    final seen = <int>{};
    final all = <Media>[];
    for (var page = 1; page <= _maxMangaPages; page++) {
      final key = 'mangaReleases:$greater:$lesser:$page';
      var result = _get<MediaPage>(key);
      if (result == null) {
        final data = await _client.query(kMangaReleasesQuery, {
          'page': page,
          'perPage': _maxPerPage,
          'startDate_greater': greater,
          'startDate_lesser': lesser,
        });
        result = _page(data, page);
        _put(key, result);
      }
      for (final media in result.items) {
        if (seen.add(media.id)) all.add(media);
      }
      if (!result.hasNextPage) break;
    }
    return List.unmodifiable(all);
  }

  static int _fuzzyInt(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  String _browseKey(BrowseQuery q) =>
      'browse:${q.type.name}:${q.sort.name}:${q.search.trim().toLowerCase()}'
      ':${q.genre ?? ''}:${q.status?.name ?? ''}:${q.format?.name ?? ''}'
      ':${q.season?.name ?? ''}:${q.seasonYear ?? 0}:${q.page}:${q.perPage}';

  /// Character ranking/search for the Search > Characters tab.
  ///
  /// An empty [search] returns the favourites ranking (Page 1).
  Future<CharacterPage> searchCharacters({
    String search = '',
    int page = 1,
    int perPage = 16,
  }) async {
    final trimmed = search.trim();
    final key = 'characters:${trimmed.toLowerCase()}:$page:$perPage';
    final cached = _get<CharacterPage>(key);
    if (cached != null) return cached;
    final data = await _client.query(kCharacterSearchQuery, {
      'page': page,
      'perPage': perPage,
      if (trimmed.isNotEmpty) 'search': trimmed,
    });
    final pageJson = _pageMap(data['Page']);
    final info = AniListMapper.pageInfo(pageJson, page);
    final result = CharacterPage(
      items: AniListMapper.characters(pageJson['characters']),
      page: info.page,
      hasNextPage: info.hasNextPage,
    );
    if (result.items.isNotEmpty || !result.hasNextPage) _put(key, result);
    return result;
  }

  /// Staff ranking/search for the Search > Staff tab.
  Future<StaffPage> searchStaff({
    String search = '',
    int page = 1,
    int perPage = 16,
  }) async {
    final trimmed = search.trim();
    final key = 'staff:${trimmed.toLowerCase()}:$page:$perPage';
    final cached = _get<StaffPage>(key);
    if (cached != null) return cached;
    final data = await _client.query(kStaffSearchQuery, {
      'page': page,
      'perPage': perPage,
      if (trimmed.isNotEmpty) 'search': trimmed,
    });
    final pageJson = _pageMap(data['Page']);
    final info = AniListMapper.pageInfo(pageJson, page);
    final result = StaffPage(
      items: AniListMapper.staff(pageJson['staff']),
      page: info.page,
      hasNextPage: info.hasNextPage,
    );
    if (result.items.isNotEmpty || !result.hasNextPage) _put(key, result);
    return result;
  }

  /// Studio ranking/search for the Search > Studios tab.
  Future<StudioPage> searchStudios({
    String search = '',
    int page = 1,
    int perPage = 16,
  }) async {
    final trimmed = search.trim();
    final key = 'studios:${trimmed.toLowerCase()}:$page:$perPage';
    final cached = _get<StudioPage>(key);
    if (cached != null) return cached;
    final data = await _client.query(kStudioSearchQuery, {
      'page': page,
      'perPage': perPage,
      if (trimmed.isNotEmpty) 'search': trimmed,
    });
    final pageJson = _pageMap(data['Page']);
    final info = AniListMapper.pageInfo(pageJson, page);
    final result = StudioPage(
      items: AniListMapper.studios(pageJson['studios']),
      page: info.page,
      hasNextPage: info.hasNextPage,
    );
    if (result.items.isNotEmpty || !result.hasNextPage) _put(key, result);
    return result;
  }

  /// Studio profile plus one page of the titles it produced.
  Future<PersonWorks> studioWorks(
    int id, {
    int page = 1,
    int perPage = 18,
  }) async {
    final key = 'studioWorks:$id:$page:$perPage';
    final cached = _get<PersonWorks>(key);
    if (cached != null) return cached;
    final data = await _client.query(kStudioWorksQuery, {
      'id': id,
      'page': page,
      'perPage': perPage,
    });
    final result = AniListMapper.studioWorks(data['Studio'], page);
    if (result == null) {
      throw AppException(ErrorKind.notFound, 'Studio $id is unavailable');
    }
    _put(key, result);
    return result;
  }

  /// The signed-in user's recent title notifications (needs an AniList
  /// token, so results are never cached).
  Future<List<UserNotification>> notifications({
    required String token,
    int perPage = 30,
  }) async {
    final data = await _client.query(kNotificationsQuery, {
      'perPage': perPage,
    }, token: token);
    return AniListMapper.notifications(_pageMap(data['Page'])['notifications']);
  }

  /// Profile header and anime/manga statistics for the signed-in user.
  Future<ViewerProfile> viewerProfile({required String token}) async {
    final data = await _client.query(
      kViewerProfileQuery,
      const <String, dynamic>{},
      token: token,
    );
    final result = AniListMapper.viewerProfile(data['Viewer']);
    if (result == null) {
      throw const AppException(
        ErrorKind.server,
        'AniList did not return a profile for this account.',
      );
    }
    return result;
  }

  /// One section of the user's AniList anime list.
  ///
  /// [status] is a `MediaListStatus` wire value (for example `CURRENT`); pass
  /// null for the whole collection. Never cached — the list is private and
  /// changes as the user tracks titles.
  Future<List<AccountListEntry>> accountList({
    required int userId,
    required String token,
    String? status,
  }) async {
    final data = await _client.query(kMediaListCollectionQuery, {
      'userId': userId,
      'type': MediaType.anime.anilistValue,
      'status': ?status,
    }, token: token);
    return AniListMapper.accountListEntries(data['MediaListCollection']);
  }

  /// The user's favourited anime (separate from their list statuses).
  Future<MediaPage> favouriteAnime({
    required int userId,
    required String token,
    int page = 1,
    int perPage = 50,
  }) async {
    final data = await _client.query(kFavouriteAnimeQuery, {
      'userId': userId,
      'page': page,
      'perPage': perPage,
    }, token: token);
    return AniListMapper.favouriteAnime(data['User'], page);
  }

  /// The user's recent AniList activity (list updates, posts, messages).
  Future<List<UserActivity>> activities({
    required int userId,
    required String token,
    int perPage = 12,
  }) async {
    final data = await _client.query(kViewerActivityQuery, {
      'userId': userId,
      'perPage': perPage,
    }, token: token);
    return AniListMapper.activities(data['Page']);
  }

  /// Upstream page size and depth used to assemble one staff member's credits.
  static const int _staffUpstreamPages = 3;

  /// Staff profile plus one page of the titles they worked on.
  ///
  /// AniList exposes credits as two independent connections (`characterMedia`
  /// for voice roles, `staffMedia` for production roles) that share one `page`
  /// argument and are each sorted on their own. Paging them in lock-step and
  /// merging per page made page 2 repeat or reorder page 1 and reported a next
  /// page when only one connection had more. Instead the connections are
  /// fetched to a fixed depth, merged, de-duplicated and sorted **once**, and
  /// the app's pages are slices of that single ordered list.
  Future<PersonWorks> staffWorks(
    int id, {
    int page = 1,
    int perPage = 18,
  }) async {
    final all = await _allStaffWorks(id);
    final items = all.works.items;
    final safePage = page < 1 ? 1 : page;
    final start = (safePage - 1) * perPage;
    final end = start + perPage;
    return PersonWorks(
      person: all.person,
      works: MediaPage(
        items: start >= items.length
            ? const []
            : items.sublist(start, end < items.length ? end : items.length),
        page: safePage,
        hasNextPage: end < items.length,
      ),
    );
  }

  Future<PersonWorks> _allStaffWorks(int id) async {
    final key = 'staffAll:$id';
    final cached = _get<PersonWorks>(key);
    if (cached != null) return cached;

    PersonProfile? profile;
    final seen = <int>{};
    final items = <Media>[];
    for (var upstream = 1; upstream <= _staffUpstreamPages; upstream++) {
      final data = await _client.query(kStaffWorksQuery, {
        'id': id,
        'page': upstream,
        'perPage': _maxPerPage,
      });
      final result = AniListMapper.staffWorks(data['Staff'], upstream);
      if (result == null) {
        if (upstream == 1) {
          throw AppException(ErrorKind.notFound, 'Staff $id is unavailable');
        }
        break;
      }
      profile ??= result.person;
      for (final media in result.works.items) {
        if (seen.add(media.id)) items.add(media);
      }
      // `hasNextPage` is true while either connection has more.
      if (!result.works.hasNextPage) break;
    }
    items.sort((a, b) {
      final byPopularity = (b.popularity ?? 0).compareTo(a.popularity ?? 0);
      return byPopularity != 0 ? byPopularity : a.id.compareTo(b.id);
    });
    final all = PersonWorks(
      person: profile!,
      works: MediaPage(items: List.unmodifiable(items), page: 1, hasNextPage: false),
    );
    _put(key, all);
    return all;
  }

  /// Character profile plus one page of the series they appear in.
  Future<PersonWorks> characterWorks(
    int id, {
    int page = 1,
    int perPage = 18,
  }) async {
    final key = 'characterWorks:$id:$page:$perPage';
    final cached = _get<PersonWorks>(key);
    if (cached != null) return cached;
    final data = await _client.query(kCharacterWorksQuery, {
      'id': id,
      'page': page,
      'perPage': perPage,
    });
    final result = AniListMapper.characterWorks(data['Character'], page);
    if (result == null) {
      throw AppException(ErrorKind.notFound, 'Character $id is unavailable');
    }
    _put(key, result);
    return result;
  }

  Map<String, dynamic> _pageMap(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }

  MediaPage _page(Map<String, dynamic> data, int fallbackPage) {
    final raw = data['Page'];
    final Map<String, dynamic> pageJson = raw is Map<String, dynamic>
        ? raw
        : raw is Map
            ? Map<String, dynamic>.from(raw)
            : const {};
    final infoRaw = pageJson['pageInfo'];
    final Map<String, dynamic> info = infoRaw is Map<String, dynamic>
        ? infoRaw
        : infoRaw is Map
            ? Map<String, dynamic>.from(infoRaw)
            : const {};
    return MediaPage(
      items: AniListMapper.mediaList(pageJson['media']),
      page: (info['currentPage'] as num?)?.toInt() ?? fallbackPage,
      hasNextPage: info['hasNextPage'] == true,
    );
  }
}

/// One cached page of the airing schedule.
class _AiringPage {
  const _AiringPage({required this.items, required this.hasNextPage});

  final List<AiringScheduleItem> items;
  final bool hasNextPage;
}

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.time);

  final T value;
  final DateTime time;
}
