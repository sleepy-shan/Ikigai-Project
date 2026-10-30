import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exception.dart';
import '../data/models/media.dart';
import '../data/repositories/media_repository.dart';
import 'load_state.dart';
import 'gql_catalog.dart';

/// A named browse lineup reachable from the home "View all" buttons
/// (`/anime?rail=trending`). Mirrors the sort/status of the matching home rail
/// so the full page lists the same titles, just without the 12-item cap.
enum BrowsePreset {
  airing('airing', 'Currently airing', 'Currently publishing',
      MediaSort.trending, MediaStatus.releasing),
  trending('trending', 'Trending anime', 'Trending manga',
      MediaSort.trending, null),
  popular('popular', 'All-time popular anime', 'All-time popular manga',
      MediaSort.popularity, null),
  topRated('top-rated', 'Top rated anime', 'Top rated manga',
      MediaSort.score, null),
  upcoming('upcoming', 'Upcoming anime', 'Upcoming manga',
      MediaSort.popularity, MediaStatus.notYetReleased),
  topCompleted('top-completed', 'Top completed anime series',
      'Top completed manga series', MediaSort.score, MediaStatus.finished);

  const BrowsePreset(
    this.slug,
    this.animeTitle,
    this.mangaTitle,
    this.sort,
    this.status,
  );

  final String slug;
  final String animeTitle;
  final String mangaTitle;
  final MediaSort sort;
  final MediaStatus? status;

  String titleFor(MediaType type) =>
      type == MediaType.manga ? mangaTitle : animeTitle;

  static BrowsePreset? fromSlug(String? slug) {
    if (slug == null) return null;
    for (final p in values) {
      if (p.slug == slug) return p;
    }
    return null;
  }
}

class BrowseState {
  const BrowseState({
    this.query = const BrowseQuery(),
    this.status = LoadStatus.initial,
    this.items = const [],
    this.hasNextPage = false,
    this.totalItems,
    this.errorMessage,
    this.preset,
  });

  final BrowseQuery query;

  /// Home "View all" lineup currently applied, if any.
  final BrowsePreset? preset;
  final LoadStatus status;

  /// Titles on the page currently shown (one page at a time).
  final List<Media> items;
  final bool hasNextPage;

  /// Total matches across all pages, when the API reports it.
  final int? totalItems;
  final String? errorMessage;

  bool get isFiltered => query.hasFilters;

  /// The page currently shown (1-based).
  int get currentPage => query.page;

  /// Best-known number of pages.
  ///
  /// AniList's `total` is documented as approximate, so it is never allowed
  /// to contradict what the paging flags say: there are at least as many
  /// pages as the current one, plus one more while `hasNextPage` is true.
  int get pageCount {
    final total = totalItems;
    final perPage = query.perPage < 1 ? 1 : query.perPage;
    final byTotal = (total == null || total <= 0)
        ? 1
        : (total + perPage - 1) ~/ perPage;
    final atLeast = hasNextPage ? currentPage + 1 : currentPage;
    return byTotal < atLeast ? atLeast : byTotal;
  }

  /// The home "View all" lineup, but only while the query still matches it
  /// exactly. Manual filter or sort edits make this null, which is what the
  /// header title and the lineup pills key off.
  BrowsePreset? get activePreset {
    final p = preset;
    if (p == null) return null;
    final q = query;
    final untouched = q.sort == p.sort &&
        q.status == p.status &&
        (q.genre == null || q.genre!.isEmpty) &&
        q.format == null &&
        q.season == null &&
        q.seasonYear == null &&
        q.source == null &&
        q.countryOfOrigin == null &&
        q.minScore == null &&
        !q.isAdult &&
        q.search.trim().isEmpty;
    return untouched ? p : null;
  }

  BrowseState copyWith({
    BrowseQuery? query,
    LoadStatus? status,
    List<Media>? items,
    bool? hasNextPage,
    int? totalItems,
    String? errorMessage,
    Object? preset = _keepPreset,
  }) {
    return BrowseState(
      query: query ?? this.query,
      status: status ?? this.status,
      items: items ?? this.items,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      totalItems: totalItems ?? this.totalItems,
      errorMessage: errorMessage,
      preset: identical(preset, _keepPreset)
          ? this.preset
          : preset as BrowsePreset?,
    );
  }
}

const Object _keepPreset = Object();

/// Drives the Anime and Manga browse screens: filters + page-by-page results.
///
/// Smart state: a monotonic [_requestId] discards stale responses when
/// filters change rapidly or the reader flips pages quickly.
class BrowseController extends Notifier<BrowseState> {
  BrowseController(this.mediaType);

  final MediaType mediaType;
  int _requestId = 0;
  GqlCatalog get _repo => ref.read(gqlCatalogProvider);

  @override
  BrowseState build() {
    // Re-fetch whenever the media type changes (route change).
    Future.microtask(load);
    return BrowseState(query: BrowseQuery(type: mediaType));
  }

  /// Loads the page in `state.query.page`, replacing what is shown.
  Future<void> load() async {
    final id = ++_requestId;
    state = state.copyWith(status: LoadStatus.loading, errorMessage: null);
    try {
      final page = await _repo.browse(state.query);
      if (id != _requestId) return; // superseded by a newer request.
      // A page past the end (the API total is only approximate): fall back
      // to the first page instead of showing an empty state.
      if (page.items.isEmpty && state.query.page > 1) {
        state = state.copyWith(query: state.query.copyWith(page: 1));
        return await load();
      }
      state = state.copyWith(
        status: LoadStatus.success,
        query: state.query.copyWith(page: page.page),
        items: page.items,
        hasNextPage: page.hasNextPage,
        totalItems: page.total,
        errorMessage: null,
      );
    } on AppException catch (error) {
      if (id != _requestId) return;
      state = state.copyWith(
        status: LoadStatus.error,
        errorMessage: error.userMessage,
      );
    } catch (error) {
      if (id != _requestId) return;
      state = state.copyWith(
        status: LoadStatus.error,
        errorMessage: 'Could not load titles: $error',
      );
    }
  }

  /// Shows [page] (1-based). Ignored when it is already the page on screen.
  Future<void> goToPage(int page) async {
    final target = page < 1 ? 1 : page;
    if (target == state.query.page && state.status == LoadStatus.success) {
      return;
    }
    state = state.copyWith(query: state.query.copyWith(page: target));
    await load();
  }

  /// Applies the whole filter set at once and performs a single reload.
  Future<void> applyFilters({
    String? genre,
    MediaStatus? status,
    MediaFormat? format,
    MediaSeason? season,
    int? seasonYear,
    MediaSort? sort,
  }) async {
    state = state.copyWith(
      query: state.query.copyWith(
        genre: genre,
        status: status,
        format: format,
        season: season,
        seasonYear: seasonYear,
        sort: sort ?? state.query.sort,
        clearFilters: true,
        page: 1,
      ),
    );
    await load();
  }

  /// Replaces the whole query (filters, sort, search) and reloads once from
  /// page 1. Used by the filter sidebar and the mobile filter sheet.
  Future<void> applyQuery(BrowseQuery query) async {
    state = state.copyWith(
      query: query.copyWith(type: mediaType, page: 1),
    );
    await load();
  }

  Future<void> setStatus(MediaStatus? status) async {
    final q = state.query;
    state = state.copyWith(
      query: q.copyWith(
        page: 1,
        genre: q.genre,
        status: status,
        format: q.format,
        season: q.season,
        seasonYear: q.seasonYear,
        clearFilters: true,
      ),
    );
    await load();
  }

  Future<void> setGenre(String? genre) async {
    final q = state.query;
    state = state.copyWith(
      query: q.copyWith(
        page: 1,
        genre: genre,
        status: q.status,
        format: q.format,
        season: q.season,
        seasonYear: q.seasonYear,
        clearFilters: true,
      ),
    );
    await load();
  }

  Future<void> setFormat(MediaFormat? format) async {
    final q = state.query;
    state = state.copyWith(
      query: q.copyWith(
        page: 1,
        genre: q.genre,
        status: q.status,
        format: format,
        season: q.season,
        seasonYear: q.seasonYear,
        clearFilters: true,
      ),
    );
    await load();
  }

  Future<void> setSeason(MediaSeason? season) async {
    final q = state.query;
    state = state.copyWith(
      query: q.copyWith(
        // A new filter starts from the first page, not page N of new results.
        page: 1,
        genre: q.genre,
        status: q.status,
        format: q.format,
        // With clearFilters, a null season now really removes the filter.
        season: season,
        seasonYear: q.seasonYear,
        clearFilters: true,
      ),
    );
    await load();
  }

  Future<void> setYear(int? year) async {
    final q = state.query;
    state = state.copyWith(
      query: q.copyWith(
        page: 1,
        genre: q.genre,
        status: q.status,
        format: q.format,
        season: q.season,
        seasonYear: year,
        clearFilters: true,
      ),
    );
    await load();
  }

  Future<void> setSource(MediaSource? source) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, source: source),
    );
    await load();
  }

  Future<void> setCountry(String? countryCode) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, countryOfOrigin: countryCode),
    );
    await load();
  }

  /// [minScore] is on AniList's 0-100 scale; null removes the filter.
  Future<void> setMinScore(int? minScore) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, minScore: minScore),
    );
    await load();
  }

  Future<void> setAdult(bool isAdult) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, isAdult: isAdult),
    );
    await load();
  }

  Future<void> setSort(MediaSort sort) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, sort: sort),
    );
    await load();
  }

  /// Drops every filter. While a lineup is applied this returns to that
  /// lineup (its sort and status are part of what it is), not to a bare query.
  Future<void> clearFilters() async {
    final lineup = state.preset;
    if (lineup != null) return applyPreset(lineup);
    state = state.copyWith(
      query: BrowseQuery(type: mediaType, sort: state.query.sort),
    );
    await load();
  }

  /// Replaces the whole query with a home "View all" lineup and reloads.
  Future<void> applyPreset(BrowsePreset preset) async {
    state = state.copyWith(
      preset: preset,
      query: BrowseQuery(
        type: mediaType,
        sort: preset.sort,
        status: preset.status,
      ),
    );
    await load();
  }

  /// Drops a previously applied preset (back to the plain browse page).
  Future<void> clearPreset() async {
    if (state.preset == null) return;
    state = state.copyWith(
      preset: null,
      query: BrowseQuery(type: mediaType),
    );
    await load();
  }

  /// Plain browse page: no lineup, no filters, default sort.
  Future<void> showAll() async {
    state = state.copyWith(preset: null, query: BrowseQuery(type: mediaType));
    await load();
  }

  Future<void> retry() => load();
}

final browseControllerProvider =
    NotifierProvider.family<BrowseController, BrowseState, MediaType>(
      BrowseController.new,
    );
