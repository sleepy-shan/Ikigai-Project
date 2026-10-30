import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/app_exception.dart';
import '../data/models/media.dart';
import '../data/models/people.dart';
import '../data/repositories/media_repository.dart';
import 'load_state.dart';
import 'gql_catalog.dart';
import 'media_providers.dart';

/// Search tabs: Anime, Manga, Studios, Staff, Characters.
enum SearchTab { anime, manga, studios, staff, characters }

/// One result set for a search tab.
///
/// Results accumulate as the reader scrolls: [page] is the last page loaded,
/// [items] holds every page so far, and [isAppending] is true only while a
/// follow-up page is being fetched (a fresh search replaces [items] instead).
class TabPage<T> {
  const TabPage({
    this.status = LoadStatus.initial,
    this.items = const [],
    this.page = 1,
    this.hasNextPage = false,
    this.isAppending = false,
    this.errorMessage,
  });

  final LoadStatus status;
  final List<T> items;
  final int page;
  final bool hasNextPage;
  final bool isAppending;
  final String? errorMessage;

  TabPage<T> copyWith({
    LoadStatus? status,
    List<T>? items,
    int? page,
    bool? hasNextPage,
    bool? isAppending,
    String? errorMessage,
  }) {
    return TabPage<T>(
      status: status ?? this.status,
      items: items ?? this.items,
      page: page ?? this.page,
      hasNextPage: hasNextPage ?? this.hasNextPage,
      isAppending: isAppending ?? this.isAppending,
      errorMessage: errorMessage,
    );
  }
}

class SearchState {
  const SearchState({
    this.queries = const {},
    this.tab = SearchTab.anime,
    this.animeSort,
    this.mangaSort,
    this.anime = const TabPage<Media>(),
    this.manga = const TabPage<Media>(),
    this.studios = const TabPage<SearchStudio>(),
    this.staff = const TabPage<SearchStaff>(),
    this.characters = const TabPage<SearchCharacter>(),
  });

  /// Search text per tab: every tab is its own page with its own search bar,
  /// so typing in one never changes what another tab is showing.
  final Map<SearchTab, String> queries;
  final SearchTab tab;

  /// The reader's explicit sort for the Anime / Manga tabs, or null for
  /// automatic (popularity with no text, best match once they type).
  final MediaSort? animeSort;
  final MediaSort? mangaSort;
  final TabPage<Media> anime;
  final TabPage<Media> manga;
  final TabPage<SearchStudio> studios;
  final TabPage<SearchStaff> staff;
  final TabPage<SearchCharacter> characters;

  String queryOf(SearchTab tab) => queries[tab] ?? '';

  /// Search text of the active tab.
  String get query => queryOf(tab);

  /// The sort actually applied to [tab] (Anime / Manga) for its current text.
  MediaSort sortOf(SearchTab tab) => resolveSort(
        tab == SearchTab.manga ? mangaSort : animeSort,
        queryOf(tab),
      );

  /// Automatic sort, and "best match" falling back to popularity when the
  /// text is cleared (relevance needs a search term).
  static MediaSort resolveSort(MediaSort? chosen, String query) {
    final hasQuery = query.trim().isNotEmpty;
    if (chosen == null) {
      return hasQuery ? MediaSort.searchMatch : MediaSort.popularity;
    }
    if (chosen == MediaSort.searchMatch && !hasQuery) {
      return MediaSort.popularity;
    }
    return chosen;
  }

  SearchState copyWith({
    Map<SearchTab, String>? queries,
    SearchTab? tab,
    MediaSort? animeSort,
    bool resetAnimeSort = false,
    MediaSort? mangaSort,
    bool resetMangaSort = false,
    TabPage<Media>? anime,
    TabPage<Media>? manga,
    TabPage<SearchStudio>? studios,
    TabPage<SearchStaff>? staff,
    TabPage<SearchCharacter>? characters,
  }) {
    return SearchState(
      queries: queries ?? this.queries,
      tab: tab ?? this.tab,
      animeSort: resetAnimeSort ? null : (animeSort ?? this.animeSort),
      mangaSort: resetMangaSort ? null : (mangaSort ?? this.mangaSort),
      anime: anime ?? this.anime,
      manga: manga ?? this.manga,
      studios: studios ?? this.studios,
      staff: staff ?? this.staff,
      characters: characters ?? this.characters,
    );
  }
}

/// Search text as it is sent to AniList: trimmed, with inner whitespace
/// collapsed, so "  one   piece " and "one piece" are the same search.
String normalizeSearchText(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Tabbed search across anime, manga, studios, staff, and characters.
///
/// Every tab is an independent search: its own text, its own sort, its own
/// debounce timer and its own result set. A monotonic id per tab discards
/// stale responses when the reader types quickly or changes sort mid-flight,
/// and a request is only sent when the normalised text or sort really
/// changed. Timers are cancelled on dispose.
class SearchController extends Notifier<SearchState> {
  static const Duration _debounce = Duration(milliseconds: 400);
  static const int _mediaPerPage = 30;
  static const int _peoplePerPage = 16;

  final Map<SearchTab, Timer> _timers = {};
  final Map<SearchTab, int> _searchIds = {};

  /// What each tab's current result set was requested with. Further pages
  /// are always fetched with these, never with text typed since.
  final Map<SearchTab, ({String query, MediaSort sort})> _params = {};

  MediaRepository get _repo => ref.read(mediaRepositoryProvider);
  GqlCatalog get _catalog => ref.read(gqlCatalogProvider);

  int _nextId(SearchTab tab) => _searchIds[tab] = (_searchIds[tab] ?? 0) + 1;

  @override
  SearchState build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    Future.microtask(() => _restart(SearchTab.anime, force: true));
    return const SearchState();
  }

  // -- text -----------------------------------------------------------------

  void _setQuery(SearchTab tab, String value) {
    if (state.queryOf(tab) == value) return;
    state = state.copyWith(queries: {...state.queries, tab: value});
  }

  /// Called on every keystroke of [tab]'s search bar; the request fires after
  /// a pause (immediately when the text is cleared).
  void onQueryChanged(SearchTab tab, String value) {
    _setQuery(tab, value);
    _timers.remove(tab)?.cancel();
    if (normalizeSearchText(value).isEmpty) {
      unawaited(_restart(tab));
      return;
    }
    _timers[tab] = Timer(_debounce, () {
      _timers.remove(tab);
      unawaited(_restart(tab));
    });
  }

  /// Enter / search button on [tab]'s search bar.
  Future<void> submit(SearchTab tab, String value) async {
    _timers.remove(tab)?.cancel();
    _setQuery(tab, value);
    await _restart(tab);
  }

  /// Clears only [tab]'s search text and shows its ranking again.
  Future<void> clear(SearchTab tab) async {
    _timers.remove(tab)?.cancel();
    _setQuery(tab, '');
    await _restart(tab);
  }

  /// Opens search on the Anime tab with [query] (links from other pages).
  Future<void> openWithQuery(String query) async {
    _timers.remove(SearchTab.anime)?.cancel();
    state = state.copyWith(
      tab: SearchTab.anime,
      queries: {...state.queries, SearchTab.anime: query},
    );
    await _restart(SearchTab.anime);
  }

  // -- tabs and sort --------------------------------------------------------

  Future<void> setTab(SearchTab tab) async {
    if (state.tab == tab) return;
    state = state.copyWith(tab: tab);
    final status = switch (tab) {
      SearchTab.anime => state.anime.status,
      SearchTab.manga => state.manga.status,
      SearchTab.studios => state.studios.status,
      SearchTab.staff => state.staff.status,
      SearchTab.characters => state.characters.status,
    };
    if (status == LoadStatus.initial) await _restart(tab, force: true);
  }

  Future<void> setAnimeSort(MediaSort sort) async {
    if (state.animeSort == sort) return;
    state = state.copyWith(animeSort: sort);
    await _restart(SearchTab.anime);
  }

  Future<void> setMangaSort(MediaSort sort) async {
    if (state.mangaSort == sort) return;
    state = state.copyWith(mangaSort: sort);
    await _restart(SearchTab.manga);
  }

  // -- loading --------------------------------------------------------------

  ({String query, MediaSort sort}) _wanted(SearchTab tab) {
    final text = normalizeSearchText(state.queryOf(tab));
    final sort = (tab == SearchTab.anime || tab == SearchTab.manga)
        ? state.sortOf(tab)
        : MediaSort.popularity; // unused by the people tabs
    return (query: text, sort: sort);
  }

  LoadStatus _statusOf(SearchTab tab) => switch (tab) {
        SearchTab.anime => state.anime.status,
        SearchTab.manga => state.manga.status,
        SearchTab.studios => state.studios.status,
        SearchTab.staff => state.staff.status,
        SearchTab.characters => state.characters.status,
      };

  /// (Re)starts [tab]'s search from page 1 with its current text and sort.
  ///
  /// Does nothing when that exact search is already showing or in flight
  /// (typing a trailing space, pressing Enter again), unless [force]d or the
  /// last attempt failed.
  Future<void> _restart(SearchTab tab, {bool force = false}) async {
    final wanted = _wanted(tab);
    final current = _params[tab];
    final status = _statusOf(tab);
    if (!force &&
        current != null &&
        current.query == wanted.query &&
        current.sort == wanted.sort &&
        status != LoadStatus.error &&
        status != LoadStatus.initial) {
      return;
    }
    _resetPage(tab);
    _params[tab] = wanted;
    await _fetch(tab, append: false);
  }

  void _resetPage(SearchTab tab) {
    switch (tab) {
      case SearchTab.anime:
        state = state.copyWith(
          anime: state.anime.copyWith(page: 1, hasNextPage: false),
        );
      case SearchTab.manga:
        state = state.copyWith(
          manga: state.manga.copyWith(page: 1, hasNextPage: false),
        );
      case SearchTab.studios:
        state = state.copyWith(
          studios: state.studios.copyWith(page: 1, hasNextPage: false),
        );
      case SearchTab.staff:
        state = state.copyWith(
          staff: state.staff.copyWith(page: 1, hasNextPage: false),
        );
      case SearchTab.characters:
        state = state.copyWith(
          characters:
              state.characters.copyWith(page: 1, hasNextPage: false),
        );
    }
  }

  /// Re-runs the active tab's search (the "Retry" button of an error state).
  Future<void> runSearch() => _restart(state.tab, force: true);

  /// Fetches the next page of the active tab and appends it (infinite
  /// scroll). Safe to call on every scroll tick: it does nothing while a
  /// request is in flight, after an error (use [retryLoadMore]) or when there
  /// is no further page.
  Future<void> loadMore() async {
    final active = _activeLoad();
    if (!active.hasNext || active.status != LoadStatus.success) return;
    await _fetch(state.tab, append: true);
  }

  /// Retries a failed "load more" request.
  Future<void> retryLoadMore() => _fetch(state.tab, append: true);

  ({bool hasNext, LoadStatus status}) _activeLoad() => switch (state.tab) {
        SearchTab.anime => (
            hasNext: state.anime.hasNextPage,
            status: state.anime.status,
          ),
        SearchTab.manga => (
            hasNext: state.manga.hasNextPage,
            status: state.manga.status,
          ),
        SearchTab.studios => (
            hasNext: state.studios.hasNextPage,
            status: state.studios.status,
          ),
        SearchTab.staff => (
            hasNext: state.staff.hasNextPage,
            status: state.staff.status,
          ),
        SearchTab.characters => (
            hasNext: state.characters.hasNextPage,
            status: state.characters.status,
          ),
      };

  /// Shared loader for every tab.
  ///
  /// A fresh search keeps the previous results on screen until the new first
  /// page arrives; an append adds to them. Responses that arrive after a newer
  /// request for the same tab started are dropped, and appended items are
  /// de-duplicated by id because AniList rankings can shift between pages.
  Future<void> _fetch(SearchTab tab, {required bool append}) async {
    final params = _params[tab] ?? _wanted(tab);
    final text = params.query;
    switch (tab) {
      case SearchTab.anime:
      case SearchTab.manga:
        final isManga = tab == SearchTab.manga;
        await _fetchInto<Media>(
          tab,
          append: append,
          read: () => isManga ? state.manga : state.anime,
          write: (p) => state = isManga
              ? state.copyWith(manga: p)
              : state.copyWith(anime: p),
          idOf: (m) => m.id,
          load: (page) async {
            final r = await _catalog.browse(
              BrowseQuery(
                type: isManga ? MediaType.manga : MediaType.anime,
                sort: params.sort,
                search: text,
                page: page,
                perPage: _mediaPerPage,
              ),
            );
            return (items: r.items, page: r.page, hasNext: r.hasNextPage);
          },
        );
      case SearchTab.studios:
        await _fetchInto<SearchStudio>(
          tab,
          append: append,
          read: () => state.studios,
          write: (p) => state = state.copyWith(studios: p),
          idOf: (m) => m.id,
          load: (page) async {
            final r = await _repo.searchStudios(
              search: text,
              page: page,
              perPage: _peoplePerPage,
            );
            return (items: r.items, page: r.page, hasNext: r.hasNextPage);
          },
        );
      case SearchTab.staff:
        await _fetchInto<SearchStaff>(
          tab,
          append: append,
          read: () => state.staff,
          write: (p) => state = state.copyWith(staff: p),
          idOf: (m) => m.id,
          load: (page) async {
            final r = await _repo.searchStaff(
              search: text,
              page: page,
              perPage: _peoplePerPage,
            );
            return (items: r.items, page: r.page, hasNext: r.hasNextPage);
          },
        );
      case SearchTab.characters:
        await _fetchInto<SearchCharacter>(
          tab,
          append: append,
          read: () => state.characters,
          write: (p) => state = state.copyWith(characters: p),
          idOf: (m) => m.id,
          load: (page) async {
            final r = await _repo.searchCharacters(
              search: text,
              page: page,
              perPage: _peoplePerPage,
            );
            return (items: r.items, page: r.page, hasNext: r.hasNextPage);
          },
        );
    }
  }

  Future<void> _fetchInto<T>(
    SearchTab tab, {
    required bool append,
    required TabPage<T> Function() read,
    required void Function(TabPage<T>) write,
    required int Function(T) idOf,
    required Future<({List<T> items, int page, bool hasNext})> Function(
      int page,
    ) load,
  }) async {
    final id = _nextId(tab);
    final target = append ? read().page + 1 : read().page;
    write(
      read().copyWith(
        status: LoadStatus.loading,
        isAppending: append,
        errorMessage: null,
      ),
    );
    try {
      final result = await load(target);
      if ((_searchIds[tab] ?? 0) != id) return;
      var items = result.items;
      if (append) {
        final seen = {for (final e in read().items) idOf(e)};
        items = [
          ...read().items,
          for (final e in result.items)
            if (seen.add(idOf(e))) e,
        ];
      }
      write(
        read().copyWith(
          status: LoadStatus.success,
          items: items,
          page: result.page,
          hasNextPage: result.hasNext,
          isAppending: false,
          errorMessage: null,
        ),
      );
    } on AppException catch (error) {
      if ((_searchIds[tab] ?? 0) != id) return;
      write(
        read().copyWith(
          status: LoadStatus.error,
          isAppending: false,
          errorMessage: error.userMessage,
        ),
      );
    } catch (error) {
      if ((_searchIds[tab] ?? 0) != id) return;
      write(
        read().copyWith(
          status: LoadStatus.error,
          isAppending: false,
          errorMessage: 'Search failed: $error',
        ),
      );
    }
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
