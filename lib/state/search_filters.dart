import 'package:flutter/foundation.dart';

import '../data/models/media.dart';
import '../data/repositories/media_repository.dart';

/// One removable criterion of [SearchFilters] (an active-filter chip).
enum SearchFilterKey {
  genres,
  season,
  format,
  status,
  yearRange,
  minScore,
  source,
}

const Object _keep = Object();

/// The eight Anime search criteria from the Filters & Criteria panel.
///
/// Immutable value type: the panel edits a draft copy and hands the whole
/// thing back on "Apply", so one apply is one network request.
@immutable
class SearchFilters {
  const SearchFilters({
    this.genres = const [],
    this.season,
    this.seasonYear,
    this.format,
    this.status,
    this.yearFrom,
    this.yearTo,
    this.minScore,
    this.source,
  });

  static const SearchFilters none = SearchFilters();

  /// How many criteria the panel offers (shown as "9 options"): Anime has
  /// eight, Manga five (no season, source or score).
  static int criteriaFor({required bool manga}) => manga ? 5 : 8;

  /// Genres (several allowed).
  final List<String> genres;

  /// Broadcast season (winter … fall) and the single year it applies to.
  final MediaSeason? season;
  final int? seasonYear;
  final MediaFormat? format;
  final MediaStatus? status;

  /// Inclusive start-year range.
  final int? yearFrom;
  final int? yearTo;

  /// Minimum community score on AniList's 0-100 scale.
  final int? minScore;
  final MediaSource? source;

  bool get isEmpty => activeCount == 0;

  /// Number of criteria currently set (season + year and the two range
  /// ends each count once).
  int get activeCount => [
        genres.isNotEmpty,
        season != null || seasonYear != null,
        format != null,
        status != null,
        yearFrom != null || yearTo != null,
        minScore != null,
        source != null,
      ].where((on) => on).length;

  SearchFilters copyWith({
    List<String>? genres,
    Object? season = _keep,
    Object? seasonYear = _keep,
    Object? format = _keep,
    Object? status = _keep,
    Object? yearFrom = _keep,
    Object? yearTo = _keep,
    Object? minScore = _keep,
    Object? source = _keep,
  }) {
    return SearchFilters(
      genres: genres ?? this.genres,
      season: identical(season, _keep) ? this.season : season as MediaSeason?,
      seasonYear:
          identical(seasonYear, _keep) ? this.seasonYear : seasonYear as int?,
      format: identical(format, _keep) ? this.format : format as MediaFormat?,
      status: identical(status, _keep) ? this.status : status as MediaStatus?,
      yearFrom: identical(yearFrom, _keep) ? this.yearFrom : yearFrom as int?,
      yearTo: identical(yearTo, _keep) ? this.yearTo : yearTo as int?,
      minScore: identical(minScore, _keep) ? this.minScore : minScore as int?,
      source: identical(source, _keep) ? this.source : source as MediaSource?,
    );
  }

  /// These filters with one criterion cleared.
  SearchFilters without(SearchFilterKey key) => switch (key) {
        SearchFilterKey.genres => copyWith(genres: const []),
        SearchFilterKey.season => copyWith(season: null, seasonYear: null),
        SearchFilterKey.format => copyWith(format: null),
        SearchFilterKey.status => copyWith(status: null),
        SearchFilterKey.yearRange => copyWith(yearFrom: null, yearTo: null),
        SearchFilterKey.minScore => copyWith(minScore: null),
        SearchFilterKey.source => copyWith(source: null),
      };

  /// The AniList query for these filters plus the search text and sort.
  BrowseQuery toQuery({
    required MediaType type,
    required MediaSort sort,
    String search = '',
    int page = 1,
    int perPage = 30,
  }) {
    // AniList has no season year for manga: a single year there is a
    // start-date range, narrowed by the year range if both are set.
    final isManga = type == MediaType.manga;
    final year = seasonYear;
    var from = yearFrom;
    var to = yearTo;
    if (isManga && year != null) {
      from = from == null || from < year ? year : from;
      to = to == null || to > year ? year : to;
    }
    return BrowseQuery(
      type: type,
      sort: sort,
      search: search,
      genres: genres,
      season: isManga ? null : season,
      seasonYear: isManga ? null : year,
      format: format,
      status: status,
      yearFrom: from,
      yearTo: to,
      minScore: isManga ? null : minScore,
      source: isManga ? null : source,
      page: page,
      perPage: perPage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      listEquals(other.genres, genres) &&
      other.season == season &&
      other.seasonYear == seasonYear &&
      other.format == format &&
      other.status == status &&
      other.yearFrom == yearFrom &&
      other.yearTo == yearTo &&
      other.minScore == minScore &&
      other.source == source;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(genres),
        season,
        seasonYear,
        format,
        status,
        yearFrom,
        yearTo,
        minScore,
        source,
      );
}
