import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gql/ast.dart' show DocumentNode;
import 'package:graphql_flutter/graphql_flutter.dart';

import '../core/utils/app_exception.dart';
import '../data/anilist/anilist_mapper.dart';
import '../data/anilist/anilist_queries.dart';
import '../data/graphql/graphql_bootstrap.dart' show FreshnessTracker;
import '../data/models/airing_schedule.dart';
import '../data/models/media.dart';
import '../data/repositories/media_repository.dart' show BrowseQuery;
import 'graphql_providers.dart';

/// Documents that reuse the existing, proven selections from
/// `anilist_queries.dart`, so [AniListMapper] keeps working unchanged. Only the
/// transport and the cache change: requests now go through the GraphQL client
/// (rate gate, 429 pause, retries) and land in the persisted normalized cache.
final DocumentNode _browseDoc = gql(browseQuery(detail: false));
final DocumentNode _airingDoc = gql(kAiringScheduleQuery);
final DocumentNode _mangaReleasesDoc = gql(kMangaReleasesQuery);

/// Detail document (tags, relations, recommendations). Used with [swrQuery].
final DocumentNode mediaDetailDoc = gql(kMediaDetailQuery);

/// Parses `data['Media']` of [mediaDetailDoc]. Null when AniList has no such
/// title (the caller turns that into a not-found error).
Media? parseMediaDetail(Map<String, dynamic> data) =>
    AniListMapper.single(data['Media']);

/// One-shot catalog reads for screens that page imperatively (browse, search,
/// calendar). Same freshness rules as `swrQuery`, without a stream:
///
///  * inside the TTL: answer from the persisted cache, zero requests;
///  * stale or missing: go to the network, write the cache, mark fresh;
///  * network failed: fall back to whatever the cache still has.
class GqlCatalog {
  GqlCatalog(this._client, this._freshness);

  final GraphQLClient _client;
  final FreshnessTracker _freshness;

  /// AniList caps a page at 50 items.
  static const int _maxPerPage = 50;
  static const int _maxSchedulePages = 24;
  static const int _maxMangaPages = 4;

  Future<Map<String, dynamic>?> _read(
    DocumentNode doc,
    Map<String, dynamic> vars,
    FetchPolicy policy,
  ) async {
    final result = await _client.query(
      QueryOptions(
        document: doc,
        variables: vars,
        fetchPolicy: policy,
        errorPolicy: ErrorPolicy.all,
      ),
    );
    if (result.hasException && result.data == null) return null;
    return result.data;
  }

  Future<Map<String, dynamic>> _fetch(
    DocumentNode doc,
    String operation,
    Map<String, dynamic> vars,
    Duration ttl, {
    bool Function(Map<String, dynamic> data)? isUsable,
  }) async {
    final key = FreshnessTracker.keyFor(operation, vars);

    if (_freshness.isFresh(key, ttl)) {
      final cached = await _read(doc, vars, FetchPolicy.cacheOnly);
      if (cached != null) return cached;
    }

    final network = await _client.query(
      QueryOptions(
        document: doc,
        variables: vars,
        fetchPolicy: FetchPolicy.networkOnly,
        errorPolicy: ErrorPolicy.all,
      ),
    );
    final data = network.data;
    if (data != null) {
      // Partial data plus an error, or a degraded empty page, is shown but
      // not marked fresh, so the next visit tries the network again.
      if (!network.hasException && (isUsable?.call(data) ?? true)) {
        _freshness.touch(key);
      }
      return data;
    }

    final stale = await _read(doc, vars, FetchPolicy.cacheOnly);
    if (stale != null) return stale;
    final error = network.exception;
    throw error != null
        ? toAppError(error)
        : const AppException(ErrorKind.server, 'Empty response from AniList');
  }

  // ------------------------------------------------- generic (repository)

  final Map<String, DocumentNode> _parsed = {};

  /// Transport for [MediaRepository]: runs any document string through the
  /// GraphQL client.
  ///
  ///  * With a [token] (user-specific data: notifications, profile, activity,
  ///    the user's list) it always goes to the network: private data must
  ///    never be answered from a cache entry that may be minutes old or
  ///    belong to a previous account.
  ///  * Without one (staff, characters, studios) it follows the same
  ///    persisted freshness window as the other catalog reads.
  Future<Map<String, dynamic>> raw(
    String document,
    Map<String, dynamic> variables, {
    String? token,
  }) async {
    final doc = _parsed.putIfAbsent(document, () => gql(document));
    if (token != null) {
      final result = await _client.query(
        QueryOptions(
          document: doc,
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
          errorPolicy: ErrorPolicy.all,
        ),
      );
      final data = result.data;
      if (data != null) return data;
      final error = result.exception;
      throw error != null
          ? toAppError(error)
          : const AppException(ErrorKind.server, 'Empty response from AniList');
    }
    return _fetch(
      doc,
      'Raw:${_fnv(document)}',
      variables,
      const Duration(minutes: 10),
    );
  }

  /// Stable (cross-run) hash of the document text for freshness keys.
  static String _fnv(String text) {
    var h = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  // --------------------------------------------------------------- browse

  Future<MediaPage> browse(BrowseQuery query) async {
    // AniList treats an explicitly-null filter as "match nothing", so unset
    // filters are omitted from the variables entirely.
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
      if (query.source != null) 'source': query.source!.wire,
      if (query.countryOfOrigin != null)
        'countryOfOrigin': query.countryOfOrigin,
      // AniList's filter is a strict ">", so "≥ 7.5" sends 74.
      if (query.minScore != null) 'minScore': query.minScore! - 1,
      'isAdult': query.isAdult,
    };

    final data = await _fetch(
      _browseDoc,
      'Browse',
      variables,
      // Search results go stale faster than a "top rated" list.
      query.search.trim().isEmpty
          ? const Duration(minutes: 10)
          : const Duration(minutes: 2),
      // An empty page that still claims more results is a degraded response.
      isUsable: (d) {
        final p = _page(d, query.page);
        return p.items.isNotEmpty || !p.hasNextPage;
      },
    );
    return _page(data, query.page);
  }

  // ------------------------------------------------------------- calendar

  /// Every episode airing between [from] and [to] (epoch seconds).
  Future<List<AiringScheduleItem>> airingScheduleAll({
    required int from,
    required int to,
  }) async {
    final seen = <int>{};
    final all = <AiringScheduleItem>[];
    for (var page = 1; page <= _maxSchedulePages; page++) {
      final data = await _fetch(
        _airingDoc,
        'AiringSchedule',
        {
          'page': page,
          'perPage': _maxPerPage,
          'airingAt_greater': from,
          'airingAt_lesser': to,
        },
        const Duration(minutes: 5),
      );
      final pageJson = _pageMap(data['Page']);
      for (final item
          in AniListMapper.airingSchedule(pageJson['airingSchedules'])) {
        if (seen.add(item.id)) all.add(item);
      }
      if (!AniListMapper.pageInfo(pageJson, page).hasNextPage) break;
    }
    all.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    return List.unmodifiable(all);
  }

  /// Manga whose start date falls in `[from, to)` (local calendar days).
  Future<List<Media>> mangaReleases({
    required DateTime from,
    required DateTime to,
  }) async {
    // Both bounds are exclusive FuzzyDateInts (YYYYMMDD).
    final dayBefore = DateTime(from.year, from.month, from.day - 1);
    final greater = _fuzzyInt(dayBefore);
    final lesser = _fuzzyInt(to);
    final seen = <int>{};
    final all = <Media>[];
    for (var page = 1; page <= _maxMangaPages; page++) {
      final data = await _fetch(
        _mangaReleasesDoc,
        'MangaReleases',
        {
          'page': page,
          'perPage': _maxPerPage,
          'startDate_greater': greater,
          'startDate_lesser': lesser,
        },
        const Duration(minutes: 30),
      );
      final result = _page(data, page);
      for (final media in result.items) {
        if (seen.add(media.id)) all.add(media);
      }
      if (!result.hasNextPage) break;
    }
    return List.unmodifiable(all);
  }

  // -------------------------------------------------------------- helpers

  static int _fuzzyInt(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static Map<String, dynamic> _pageMap(Object? raw) => raw is Map
      ? raw.map((k, v) => MapEntry(k.toString(), v))
      : const <String, dynamic>{};

  static MediaPage _page(Map<String, dynamic> data, int fallbackPage) {
    final pageJson = _pageMap(data['Page']);
    final info = pageJson['pageInfo'];
    final infoMap = info is Map ? info : const {};
    return MediaPage(
      items: AniListMapper.mediaList(pageJson['media']),
      page: (infoMap['currentPage'] as num?)?.toInt() ?? fallbackPage,
      hasNextPage: infoMap['hasNextPage'] == true,
      total: (infoMap['total'] as num?)?.toInt(),
    );
  }
}

final gqlCatalogProvider = Provider<GqlCatalog>((ref) {
  return GqlCatalog(
    ref.watch(graphQLClientProvider),
    ref.watch(gqlStorageProvider).freshness,
  );
});
