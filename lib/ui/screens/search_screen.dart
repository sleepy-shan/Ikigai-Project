import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/models/people.dart';
import '../../state/load_state.dart';
import '../../state/search_controller.dart';
import '../components/media_grid.dart';
import '../components/search_field.dart';
import '../components/app_footer.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

final _favouritesFormat = NumberFormat('#,###');

/// Tabbed search page: Anime, Manga, Studios, Staff, Characters.
///
/// Each tab keeps its own result set and loads further pages automatically
/// as the reader scrolls (infinite scroll). An empty query shows the
/// popularity ranking; typing filters by name with a debounce.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.initialQuery = '', super.key});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  /// One text field and focus node per tab: every tab is its own search.
  late final Map<SearchTab, TextEditingController> _controllers;
  late final Map<SearchTab, FocusNode> _focusNodes;
  late final BouncyScrollController _scrollController;
  bool _showTop = false;

  TextEditingController controllerFor(SearchTab tab) => _controllers[tab]!;
  FocusNode focusNodeFor(SearchTab tab) => _focusNodes[tab]!;

  @override
  void initState() {
    super.initState();
    // The search state outlives this screen, so start each field from the
    // text its tab is actually showing results for.
    final saved = ref.read(searchControllerProvider);
    final initial = widget.initialQuery.trim();
    _controllers = {
      for (final tab in SearchTab.values)
        tab: TextEditingController(
          text: tab == SearchTab.anime && initial.isNotEmpty
              ? widget.initialQuery
              : saved.queryOf(tab),
        ),
    };
    _focusNodes = {for (final tab in SearchTab.values) tab: FocusNode()};
    _scrollController = BouncyScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(searchControllerProvider.notifier);
      if (initial.isNotEmpty) {
        notifier.openWithQuery(widget.initialQuery);
      } else {
        focusNodeFor(ref.read(searchControllerProvider).tab).requestFocus();
      }
      _maybeLoadMore();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final show = _scrollController.offset > 900;
    if (show != _showTop && mounted) setState(() => _showTop = show);
    _maybeLoadMore();
  }

  /// Infinite scroll: ask for the next page once the reader is within a few
  /// screens of the end. Also called after every result change, so a short
  /// first page on a tall window keeps filling until the view scrolls.
  void _maybeLoadMore() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 900) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  void _afterFrame(VoidCallback callback) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery &&
        widget.initialQuery.trim().isNotEmpty &&
        controllerFor(SearchTab.anime).text != widget.initialQuery) {
      controllerFor(SearchTab.anime).text = widget.initialQuery;
      final query = widget.initialQuery;
      // Providers can't be modified while the widget tree is building
      // (didUpdateWidget runs during build), so defer to after the frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(searchControllerProvider.notifier).openWithQuery(query);
      });
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // New results landed (or a page was appended): top up if still near end.
    ref.listen(
      searchControllerProvider.select(_loadSignature),
      (_, _) => _afterFrame(_maybeLoadMore),
    );
    // A different tab, query or sort is a different result set: start at top.
    ref.listen(searchControllerProvider.select(_viewKey), (previous, next) {
      if (previous == null || previous == next) return;
      _afterFrame(() {
        if (_scrollController.hasClients && _scrollController.offset > 0) {
          _scrollController.jumpTo(0);
        }
      });
    });
    return Stack(
      children: [
        SmoothCustomScrollView(
          controller: _scrollController,
          slivers: const [
            SliverToBoxAdapter(child: _SearchHeader()),
            SliverToBoxAdapter(child: _TabSearchField()),
            SliverToBoxAdapter(child: _MediaSortRow()),
            SliverToBoxAdapter(
              child: SizedBox(height: Tokens.space8),
            ),
            _ResultsSlivers(),
            SliverToBoxAdapter(child: _LoadMoreFooter()),
            SliverAppFooter(),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 24,
          child: BackToTopButton(
            visible: _showTop,
            onPressed: () {
              if (_scrollController.hasClients) {
                _scrollController.smoothTo(0);
              }
            },
          ),
        ),
      ],
    );
  }
}

/// Changes whenever the active tab's loading state or item count changes.
(SearchTab, LoadStatus, int) _loadSignature(SearchState s) => switch (s.tab) {
      SearchTab.anime => (s.tab, s.anime.status, s.anime.items.length),
      SearchTab.manga => (s.tab, s.manga.status, s.manga.items.length),
      SearchTab.studios => (s.tab, s.studios.status, s.studios.items.length),
      SearchTab.staff => (s.tab, s.staff.status, s.staff.items.length),
      SearchTab.characters => (
          s.tab,
          s.characters.status,
          s.characters.items.length,
        ),
    };

/// Identifies the visible result set (tab + query + sort).
(SearchTab, String, MediaSort?) _viewKey(SearchState s) => (
      s.tab,
      normalizeSearchText(s.query),
      switch (s.tab) {
        SearchTab.anime || SearchTab.manga => s.sortOf(s.tab),
        _ => null,
      },
    );

/// Title + subtitle + tab bar (Anime / Manga / Studios / Staff / Characters).
class _SearchHeader extends ConsumerWidget {
  const _SearchHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    final controller = ref.read(searchControllerProvider.notifier);

    Widget tabButton(SearchTab value, IconData icon, String label) {
      final selected = tab == value;
      final scheme = theme.colorScheme;
      return TextButton.icon(
        onPressed: selected ? null : () => controller.setTab(value),
        icon: Icon(
          icon,
          size: 18,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        label: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        Tokens.space4,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Search', style: theme.textTheme.headlineMedium),
              Text(
                'Simple when you want it, extremely specific when you need it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final tabs = Wrap(
            spacing: Tokens.space4,
            runSpacing: 0,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              tabButton(SearchTab.anime, Icons.movie_outlined, 'Anime'),
              tabButton(SearchTab.manga, Icons.menu_book_outlined, 'Manga'),
              tabButton(SearchTab.studios, Icons.business_outlined, 'Studios'),
              tabButton(SearchTab.staff, Icons.person_outline, 'Staff'),
              tabButton(
                SearchTab.characters,
                Icons.person_search_outlined,
                'Characters',
              ),
            ],
          );
          if (constraints.maxWidth >= 760) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const Spacer(), tabs],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Tokens.space8,
            children: [
              titleBlock,
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: tabs,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Right-aligned name search field with a per-tab hint.
class _TabSearchField extends ConsumerWidget {
  const _TabSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    final hasQuery = ref.watch(
      searchControllerProvider.select((s) => s.query.isNotEmpty),
    );
    final controller = ref.read(searchControllerProvider.notifier);
    final parent = context.findAncestorStateOfType<_SearchScreenState>();
    if (parent == null) return const SizedBox.shrink();
    final textController = parent.controllerFor(tab);
    final focusNode = parent.focusNodeFor(tab);

    final hint = switch (tab) {
      SearchTab.anime => 'Search anime by name...',
      SearchTab.manga => 'Search manga by name...',
      SearchTab.studios => 'Search studios by name...',
      SearchTab.staff => 'Search staff by name...',
      SearchTab.characters => 'Search characters by name...',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        Tokens.space4,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          // Shared field: the hairline/focus border is drawn once on the
          // outer container, so it always wraps the text, clear button and
          // search action as a single whole outline.
          child: LensSearchField(
            // A separate field (own text, focus and clear button) per tab.
            key: ValueKey(tab),
            controller: textController,
            focusNode: focusNode,
            hintLong: hint,
            hintShort: hint,
            showKbdChip: false,
            showClear: hasQuery,
            onChanged: (value) => controller.onQueryChanged(tab, value),
            onSubmitted: (value) => controller.submit(tab, value),
            onClear: () {
              textController.clear();
              controller.clear(tab);
            },
          ),
        ),
      ),
    );
  }
}

/// Sort selector for the Anime and Manga tabs (other tabs are
/// favourites-ranked).
class _MediaSortRow extends ConsumerWidget {
  const _MediaSortRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    if (tab != SearchTab.anime && tab != SearchTab.manga) {
      return const SizedBox.shrink();
    }
    final isManga = tab == SearchTab.manga;
    // The sort in effect for this tab's text, and whether there is text:
    // "Best match" only exists while searching for something.
    final sort = ref.watch(
      searchControllerProvider.select((s) => s.sortOf(tab)),
    );
    final hasQuery = ref.watch(
      searchControllerProvider.select(
        (s) => normalizeSearchText(s.queryOf(tab)).isNotEmpty,
      ),
    );
    final controller = ref.read(searchControllerProvider.notifier);
    final options = [
      if (hasQuery) MediaSort.searchMatch,
      MediaSort.popularity,
      MediaSort.trending,
      MediaSort.score,
      MediaSort.titleRomaji,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        0,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: DropdownButton<MediaSort>(
            // Each tab keeps its own sort, so rebuild the menu per tab.
            key: ValueKey(tab),
            value: options.contains(sort) ? sort : MediaSort.popularity,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final s in options)
                DropdownMenuItem(
                  value: s,
                  child: Text(
                    s == MediaSort.popularity ? 'Most Popular' : s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (s) {
              if (s == null) return;
              if (isManga) {
                controller.setMangaSort(s);
              } else {
                controller.setAnimeSort(s);
              }
            },
          ),
        ),
      ),
    );
  }
}

/// End-of-list status: a spinner while the next page loads, or a retry
/// prompt if that request failed.
class _LoadMoreFooter extends ConsumerWidget {
  const _LoadMoreFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (appending, failed) = ref.watch(
      searchControllerProvider.select((s) {
        final (isAppending, status, count) = switch (s.tab) {
          SearchTab.anime => (
              s.anime.isAppending,
              s.anime.status,
              s.anime.items.length,
            ),
          SearchTab.manga => (
              s.manga.isAppending,
              s.manga.status,
              s.manga.items.length,
            ),
          SearchTab.studios => (
              s.studios.isAppending,
              s.studios.status,
              s.studios.items.length,
            ),
          SearchTab.staff => (
              s.staff.isAppending,
              s.staff.status,
              s.staff.items.length,
            ),
          SearchTab.characters => (
              s.characters.isAppending,
              s.characters.status,
              s.characters.items.length,
            ),
        };
        return (isAppending, status == LoadStatus.error && count > 0);
      }),
    );
    if (failed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Tokens.space24),
        child: Center(
          child: TextButton.icon(
            onPressed: ref.read(searchControllerProvider.notifier).retryLoadMore,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text("Couldn't load more · Retry"),
          ),
        ),
      );
    }
    if (!appending) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(bottom: Tokens.space24),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ResultsSlivers extends ConsumerWidget {
  const _ResultsSlivers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    return switch (tab) {
      SearchTab.anime => const _MediaResults(tab: SearchTab.anime),
      SearchTab.manga => const _MediaResults(tab: SearchTab.manga),
      SearchTab.studios => const _StudioResults(),
      SearchTab.staff => const _StaffResults(),
      SearchTab.characters => const _CharacterResults(),
    };
  }
}

/// Poster-grid results shared by the Anime and Manga tabs.
class _MediaResults extends ConsumerWidget {
  const _MediaResults({required this.tab});

  final SearchTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManga = tab == SearchTab.manga;
    final noun = isManga ? 'manga' : 'anime';
    final page = ref.watch(
      searchControllerProvider.select((s) => isManga ? s.manga : s.anime),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final results = page.items;
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => SliverEmpty(
        title: 'Start typing',
        message: isManga
            ? 'Search manga by title — for example "berserk".'
            : 'Search anime by title — for example "frieren".',
        icon: Icons.search,
      ),
      LoadStatus.loading when results.isEmpty => const SliverToBoxAdapter(
        child: LoadingPosterGrid(columnsForWidth: browsePosterColumns),
      ),
      // Keep-previous-data: show the old grid while the next page loads.
      LoadStatus.loading => SliverPosterGrid(items: results, compact: true),
      LoadStatus.error when results.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => SliverPosterGrid(items: results, compact: true),
      LoadStatus.success when results.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'Nothing matched "${query.trim()}". '
                  'Try a different spelling or fewer words.'
            : 'No $noun found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => SliverPosterGrid(items: results, compact: true),
    };
  }
}

class _StudioResults extends ConsumerWidget {
  const _StudioResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      searchControllerProvider.select((s) => s.studios),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when page.items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StudioCard(studio: page.items[i]),
      ),
      LoadStatus.error when page.items.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StudioCard(studio: page.items[i]),
      ),
      LoadStatus.success when page.items.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No studios matched "${query.trim()}".'
            : 'No studios found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StudioCard(studio: page.items[i]),
      ),
    };
  }
}

class _StaffResults extends ConsumerWidget {
  const _StaffResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      searchControllerProvider.select((s) => s.staff),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when page.items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StaffCard(staff: page.items[i]),
      ),
      LoadStatus.error when page.items.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StaffCard(staff: page.items[i]),
      ),
      LoadStatus.success when page.items.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No staff matched "${query.trim()}".'
            : 'No staff found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) => _StaffCard(staff: page.items[i]),
      ),
    };
  }
}

class _CharacterResults extends ConsumerWidget {
  const _CharacterResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(
      searchControllerProvider.select((s) => s.characters),
    );
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);

    return switch (page.status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when page.items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: page.items[i]),
      ),
      LoadStatus.error when page.items.isEmpty => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: controller.runSearch,
      ),
      LoadStatus.error => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: page.items[i]),
      ),
      LoadStatus.success when page.items.isEmpty => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No characters matched "${query.trim()}".'
            : 'No characters found.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => _PeopleGrid(
        itemCount: page.items.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: page.items[i]),
      ),
    };
  }
}

/// Responsive grid of horizontal person/studio cards.
class _PeopleGrid extends StatefulWidget {
  const _PeopleGrid({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<_PeopleGrid> createState() => _PeopleGridState();
}

class _PeopleGridState extends State<_PeopleGrid> {
  // SliverLayoutBuilder calls its builder on every scroll frame; handing back
  // the same grid widget until the width or inputs change stops Flutter from
  // rebuilding every visible card on each frame.
  Widget? _cached;
  double _cachedWidth = -1;

  @override
  void didUpdateWidget(covariant _PeopleGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cached = null;
  }

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final cached = _cached;
        if (cached != null && _cachedWidth == width) return cached;
        final columns = _peopleColumns(width);
        final grid = SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space8,
            Tokens.space16,
            Tokens.space16,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: Tokens.space12,
              crossAxisSpacing: Tokens.space12,
              mainAxisExtent: 84,
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => RepaintBoundary(
              child: widget.itemBuilder(context, index),
            ),
          ),
        );
        _cachedWidth = width;
        _cached = grid;
        return grid;
      },
    );
  }
}

int _peopleColumns(double width) {
  if (width >= 1500) return 5;
  if (width >= 1250) return 4;
  if (width >= 950) return 3;
  if (width >= 620) return 2;
  return 1;
}

String _formatFavourites(int value) => _favouritesFormat.format(value);

/// Favourites pill: "♡ 39,561".
class _FavouritesPill extends StatelessWidget {
  const _FavouritesPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
      child: Text(
        '♡ ${_formatFavourites(count)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PersonImage extends StatelessWidget {
  const _PersonImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
      child: SizedBox(
        width: 46,
        height: 68,
        child: url.isEmpty
            ? Container(
                color: theme.disabledColor.withValues(alpha: 0.15),
                child: const Icon(
                  Icons.person_outline,
                  size: 24,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                // Thumbnails are ~46px wide; decoding the full portrait is
                // wasted memory/CPU when scrolling long lists.
                cacheWidth: 128,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stack) => Container(
                  color: theme.disabledColor.withValues(alpha: 0.15),
                  child: const Icon(Icons.person_outline, size: 24),
                ),
              ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character});

  final SearchCharacter character;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.push(Routes.characterWorks(character.id)),
        child: Padding(
        padding: const EdgeInsets.all(Tokens.space8),
        child: Row(
          spacing: Tokens.space12,
          children: [
            _PersonImage(url: character.imageUrl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    character.nameFull,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (character.nameNative != null &&
                      character.nameNative!.isNotEmpty)
                    Text(
                      character.nameNative!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: Tokens.space4),
                  _FavouritesPill(count: character.favourites),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff});

  final SearchStaff staff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.push(Routes.staffWorks(staff.id)),
        child: Padding(
        padding: const EdgeInsets.all(Tokens.space8),
        child: Row(
          spacing: Tokens.space12,
          children: [
            _PersonImage(url: staff.imageUrl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    staff.nameFull,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (staff.nameNative != null &&
                      staff.nameNative!.isNotEmpty)
                    Text(
                      staff.nameNative!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: Tokens.space4),
                  Wrap(
                    spacing: Tokens.space4,
                    runSpacing: Tokens.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (staff.role.isNotEmpty)
                        Text(
                          staff.role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      _FavouritesPill(count: staff.favourites),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StudioCard extends StatelessWidget {
  const _StudioCard({required this.studio});

  final SearchStudio studio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.push(Routes.studioWorks(studio.id)),
        child: Padding(
        padding: const EdgeInsets.all(Tokens.space8),
        child: Row(
          spacing: Tokens.space12,
          children: [
            Container(
              width: 46,
              height: 68,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
              ),
              child: const Icon(Icons.business_outlined, size: 24),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    studio.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Tokens.space4),
                  Wrap(
                    spacing: Tokens.space4,
                    runSpacing: Tokens.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        studio.isAnimationStudio
                            ? 'Animation studio'
                            : 'Studio',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      _FavouritesPill(count: studio.favourites),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
