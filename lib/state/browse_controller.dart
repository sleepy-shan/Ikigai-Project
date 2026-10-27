import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exception.dart';
import '../data/models/media.dart';
import '../data/repositories/media_repository.dart';
import 'load_state.dart';
import 'media_providers.dart';

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
    this.isLoadingMore = false,
    this.errorMessage,
    this.preset,
  });

  final BrowseQuery query;

  /// Home "View all" lineup currently applied, if any.
  final BrowsePreset? preset;
  final LoadStatus status;

  /// Items currently loaded (accumulated across pages).
  final List<Media> items;
  final bool hasNextPage;
  final bool isLoadingMore;
  final String? errorMessage;

  bool get isFiltered => query.hasFilters;

  BrowseState copyWith({
    BrowseQuery? query,
    LoadStatus? status,
    List<Media>? items,
    bool? hasNextPage,
    bool? isLoadingMore,
    String? errorMessage,
    Object? preset = _keepPreset,
  }) {
    return BrowseState(
      query: query ?? this.query,
      status: status ?? this.status,
      items: items ?? this.items,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: errorMessage,
      preset: identical(preset, _keepPreset)
          ? this.preset
          : preset as BrowsePreset?,
    );
  }
}

const Object _keepPreset = Object();

/// Drives the Anime and Manga browse screens: filters + infinite scroll.
///
/// Smart state: a monotonic [_requestId] discards stale responses when
/// filters change rapidly or `loadMore` overlaps a fresh `load`.
class BrowseController extends Notifier<BrowseState> {
  BrowseController(this.mediaType);

  final MediaType mediaType;
  int _requestId = 0;
  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  @override
  BrowseState build() {
    // Re-fetch whenever the media type changes (route change).
    Future.microtask(load);
    return BrowseState(query: BrowseQuery(type: mediaType));
  }

  Future<void> load() async {
    final id = ++_requestId;
    state = state.copyWith(status: LoadStatus.loading, errorMessage: null);
    try {
      final page = await _repo.browse(state.query);
      if (id != _requestId) return; // superseded by a newer request.
      state = state.copyWith(
        status: LoadStatus.success,
        query: state.query.copyWith(page: page.page),
        items: page.items,
        hasNextPage: page.hasNextPage,
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

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasNextPage) return;
    final id = _requestId;
    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.query.page + 1;
      final page = await _repo.browse(state.query.copyWith(page: nextPage));
      if (id != _requestId) return; // a fresh load superseded pagination.
      state = state.copyWith(
        query: state.query.copyWith(page: nextPage),
        items: [...state.items, ...page.items],
        hasNextPage: page.hasNextPage,
        isLoadingMore: false,
      );
    } catch (_) {
      // Keep existing items visible; user can scroll again to retry.
      if (id == _requestId) state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> setSearch(String search) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, search: search),
    );
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

  /// Jumps to [page] (1-based), replacing items instead of accumulating.
  Future<void> goToPage(int page) async {
    final target = page < 1 ? 1 : page;
    if (target == state.query.page &&
        state.status != LoadStatus.initial) {
      return;
    }
    state = state.copyWith(
      query: state.query.copyWith(page: target),
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

  Future<void> setSort(MediaSort sort) async {
    state = state.copyWith(
      query: state.query.copyWith(page: 1, sort: sort),
    );
    await load();
  }

  Future<void> clearFilters() async {
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

  Future<void> retry() => load();
}

final browseControllerProvider =
    NotifierProvider.family<BrowseController, BrowseState, MediaType>(
      BrowseController.new,
    );
