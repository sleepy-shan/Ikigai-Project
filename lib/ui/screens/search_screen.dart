import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../data/models/media.dart';
import '../../data/models/people.dart';
import '../../state/load_state.dart';
import '../../state/search_controller.dart';
import '../../state/search_filters.dart';
import '../components/media_grid.dart';
import '../components/search_field.dart';
import '../components/search_filter_fields.dart';
import '../components/search_filters_editor.dart';
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
        // Don't pop the on-screen keyboard open on phones: on a small screen
        // it covers most of the page before the reader has seen anything.
        if (MediaQuery.sizeOf(context).width >= Tokens.breakpointCompact) {
          focusNodeFor(ref.read(searchControllerProvider).tab).requestFocus();
        }
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
            SliverToBoxAdapter(child: _SearchControls()),
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
(SearchTab, String, MediaSort?, SearchFilters) _viewKey(SearchState s) => (
      s.tab,
      normalizeSearchText(s.query),
      switch (s.tab) {
        SearchTab.anime || SearchTab.manga => s.sortOf(s.tab),
        _ => null,
      },
      s.filtersOf(s.tab),
    );

const List<(SearchTab, IconData, String)> _searchTabs = [
  (SearchTab.anime, Icons.web_asset_outlined, 'Anime'),
  (SearchTab.manga, Icons.view_column_outlined, 'Manga'),
  (SearchTab.studios, Icons.home_outlined, 'Studio'),
  (SearchTab.staff, Icons.person_outline, 'Staff'),
  (SearchTab.characters, Icons.group_outlined, 'Characters'),
];

/// Title + subtitle + tab bar (Anime / Manga / Studio / Staff / Characters).
///
/// Wide: a segmented pill on the right of the title. Narrow: a row of
/// icon-over-label tiles under it.
class _SearchHeader extends ConsumerWidget {
  const _SearchHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    final controller = ref.read(searchControllerProvider.notifier);

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
              const SizedBox(height: Tokens.space4),
              Text(
                'Simple when you want it, extremely specific when you need it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final width = constraints.maxWidth;
          // Wide: title and tab pill side by side. Tablet: the pill gets the
          // full width under the title (beside it the title would be squeezed
          // into a few words per line). Phone: icon-over-label tiles.
          if (width >= 960) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleBlock),
                const SizedBox(width: Tokens.space16),
                _TabSegmented(selected: tab, onSelected: controller.setTab),
              ],
            );
          }
          if (width >= 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleBlock,
                const SizedBox(height: Tokens.space16),
                _TabSegmented(
                  selected: tab,
                  onSelected: controller.setTab,
                  expand: true,
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: Tokens.space16),
              _TabTiles(selected: tab, onSelected: controller.setTab),
            ],
          );
        },
      ),
    );
  }
}

/// Desktop / tablet tab switcher: one rounded container, the active tab
/// filled. With [expand] the five tabs share the full width equally.
class _TabSegmented extends StatelessWidget {
  const _TabSegmented({
    required this.selected,
    required this.onSelected,
    this.expand = false,
  });

  final SearchTab selected;
  final ValueChanged<SearchTab> onSelected;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(Tokens.space4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final (tab, _, label) in _searchTabs)
            () {
              final item = Semantics(
                button: true,
                selected: tab == selected,
                label: label,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Tokens.radiusPill),
                  onTap: () => onSelected(tab),
                  child: AnimatedContainer(
                    duration: Tokens.durationFast,
                    curve: Tokens.curveSmooth,
                    alignment: expand ? Alignment.center : null,
                    padding: EdgeInsets.symmetric(
                      horizontal: expand ? Tokens.space8 : 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tab == selected
                          ? scheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tab == selected
                              ? scheme.onPrimary
                              : scheme.onSurfaceVariant,
                          fontWeight: tab == selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
              return expand ? Expanded(child: item) : item;
            }(),
        ],
      ),
    );
  }
}

/// Phone tab switcher: five equal tiles, icon over label.
class _TabTiles extends StatelessWidget {
  const _TabTiles({required this.selected, required this.onSelected});

  final SearchTab selected;
  final ValueChanged<SearchTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      spacing: Tokens.space8,
      children: [
        for (final (tab, icon, label) in _searchTabs)
          Expanded(
            child: Semantics(
              button: true,
              selected: tab == selected,
              label: label,
              excludeSemantics: true,
              child: Material(
                color: tab == selected
                    ? scheme.primary.withValues(alpha: 0.14)
                    : theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg - 2),
                  side: BorderSide(
                    color: tab == selected ? scheme.primary : theme.dividerColor,
                    width: tab == selected ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelected(tab),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space4,
                      vertical: Tokens.space12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: tab == selected
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                        const SizedBox(height: Tokens.space8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: tab == selected
                                  ? scheme.primary
                                  : scheme.onSurface,
                              fontWeight: tab == selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything between the tab bar and the results.
///
/// Anime and Manga get the full search card, Filters & Criteria and a result
/// heading; the other tabs keep their plain name search.
class _SearchControls extends ConsumerWidget {
  const _SearchControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(searchControllerProvider.select((s) => s.tab));
    if (tab == SearchTab.anime || tab == SearchTab.manga) {
      // Keyed so each tab starts with its own panel state and draft.
      return _MediaSearchControls(key: ValueKey(tab), tab: tab);
    }
    return const _TabSearchField();
  }
}

/// Anime / Manga search: search field + Filters & Criteria, active-filter chips,
/// "N matched titles" heading and the sort menu.
///
/// Wide (>= 760): one card holding the field, the filters button and the
/// match count, with the "Refine Filters" panel opening beneath it.
/// Narrow: field and a Filters button in one row; the criteria open in a
/// bottom sheet.
class _MediaSearchControls extends ConsumerStatefulWidget {
  const _MediaSearchControls({required this.tab, super.key});

  /// [SearchTab.anime] or [SearchTab.manga].
  final SearchTab tab;

  @override
  ConsumerState<_MediaSearchControls> createState() =>
      _MediaSearchControlsState();
}

class _MediaSearchControlsState extends ConsumerState<_MediaSearchControls> {
  /// Desktop only: whether the "Refine Filters" panel is showing.
  bool _panelOpen = false;

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_SearchScreenState>();
    if (parent == null) return const SizedBox.shrink();
    final tab = widget.tab;
    final noun = tab == SearchTab.manga ? 'manga' : 'anime';
    final theme = Theme.of(context);
    final controller = ref.read(searchControllerProvider.notifier);
    final filterCount = ref.watch(
      searchControllerProvider.select((s) => s.filtersOf(tab).activeCount),
    );
    final hasQuery = ref.watch(
      searchControllerProvider.select((s) => s.query.isNotEmpty),
    );
    final textController = parent.controllerFor(tab);

    final field = LensSearchField(
      key: ValueKey(tab),
      controller: textController,
      focusNode: parent.focusNodeFor(tab),
      hintLong: 'Search $noun by name...',
      hintShort: 'Search $noun by name...',
      showKbdChip: false,
      showClear: hasQuery,
      onChanged: (value) => controller.onQueryChanged(tab, value),
      onSubmitted: (value) => controller.submit(tab, value),
      onClear: () {
        textController.clear();
        controller.clear(tab);
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        if (!wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space16,
              Tokens.space12,
              Tokens.space16,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  spacing: Tokens.space12,
                  children: [
                    Expanded(child: field),
                    _FiltersButton(
                      wide: false,
                      // Under ~380px the label would leave the search field
                      // only a sliver: keep the icon and the count.
                      iconOnly: constraints.maxWidth < 380,
                      count: filterCount,
                      onPressed: () => showSearchFiltersSheet(context, tab),
                    ),
                  ],
                ),
                _ActiveFilterChips(tab: tab, scroll: true),
                const SizedBox(height: Tokens.space20),
                _ResultsHeading(tab: tab, wide: false),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space12,
            Tokens.space16,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(Tokens.space20),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      spacing: Tokens.space12,
                      children: [
                        Expanded(child: field),
                        _FiltersButton(
                          wide: true,
                          count: filterCount,
                          onPressed: () =>
                              setState(() => _panelOpen = !_panelOpen),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space16),
                    Divider(height: 1, color: theme.dividerColor),
                    const SizedBox(height: Tokens.space12),
                    _ShowingCount(tab: tab),
                  ],
                ),
              ),
              AnimatedSize(
                duration: Tokens.durationMedium,
                curve: Tokens.curveSmooth,
                alignment: Alignment.topCenter,
                child: _panelOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: Tokens.space16),
                        child: SearchFiltersEditor(
                          tab: tab,
                          layout: FiltersLayout.panel,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: Tokens.space32),
              _ResultsHeading(tab: tab, wide: true),
              _ActiveFilterChips(tab: tab, scroll: false),
            ],
          ),
        );
      },
    );
  }
}

/// "Filters & Criteria · 3" (wide, outlined) or "Filters (3)" (phone, light).
class _FiltersButton extends StatelessWidget {
  const _FiltersButton({
    required this.wide,
    required this.count,
    required this.onPressed,
    this.iconOnly = false,
  });

  final bool wide;

  /// Phone layout only: drop the "Filters" label.
  final bool iconOnly;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Tokens.radiusMd);
    if (wide) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          foregroundColor: scheme.primary,
          backgroundColor: scheme.primary.withValues(alpha: 0.08),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.7)),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
        child: Text(
          count > 0 ? 'Filters & Criteria · $count' : 'Filters & Criteria',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: EdgeInsets.symmetric(horizontal: iconOnly ? 12 : 16),
        backgroundColor: scheme.inverseSurface,
        foregroundColor: scheme.onInverseSurface,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Tokens.space8,
        children: [
          Icon(
            Icons.tune_rounded,
            size: 18,
            semanticLabel: iconOnly ? 'Filters' : null,
          ),
          if (!iconOnly)
            const Text(
              'Filters',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          if (count > 0)
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onInverseSurface,
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How many titles the current Anime/Manga search matches, or null while the
/// first page is still loading.
int? _animeMatchCount(TabPage<Media> page) {
  if (page.status == LoadStatus.initial ||
      (page.status == LoadStatus.loading && page.items.isEmpty)) {
    return null;
  }
  return page.total ?? page.items.length;
}

/// "Showing 148 matched titles" line inside the desktop search card.
class _ShowingCount extends ConsumerWidget {
  const _ShowingCount({required this.tab});

  final SearchTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final count = ref.watch(
      searchControllerProvider.select((s) => _animeMatchCount(s.mediaPageOf(tab))),
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (count == null) return Text('Searching…', style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Showing '),
          TextSpan(
            text: _favouritesFormat.format(count),
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: count == 1 ? ' matched title' : ' matched titles'),
        ],
      ),
    );
  }
}

/// "FILTERED DISCOVERIES / 148 matched titles" with the sort menu.
class _ResultsHeading extends ConsumerWidget {
  const _ResultsHeading({required this.tab, required this.wide});

  final SearchTab tab;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final page = ref.watch(
      searchControllerProvider.select((s) => s.mediaPageOf(tab)),
    );
    final filtered = ref.watch(
      searchControllerProvider.select((s) => !s.filtersOf(tab).isEmpty),
    );
    final hasQuery = ref.watch(
      searchControllerProvider.select(
        (s) => normalizeSearchText(s.queryOf(tab)).isNotEmpty,
      ),
    );
    final count = _animeMatchCount(page);
    final title = page.status == LoadStatus.error && page.items.isEmpty
        ? 'Something went wrong'
        : count == null
            ? 'Searching…'
            : '${_favouritesFormat.format(count)} matched '
                  '${count == 1 ? 'title' : 'titles'}';
    final eyebrow = filtered
        ? 'FILTERED DISCOVERIES'
        : (hasQuery ? 'SEARCH RESULTS' : 'DISCOVER');

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Tokens.space4),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (wide
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Beside the title the menu needs ~160px; on a narrow phone that
        // leaves the title a few letters, so the menu drops underneath.
        if (constraints.maxWidth < 440) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleBlock,
              const SizedBox(height: Tokens.space12),
              _MediaSortSelect(tab: tab),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: Tokens.space12),
            SizedBox(width: wide ? 200 : 156, child: _MediaSortSelect(tab: tab)),
          ],
        );
      },
    );
  }
}

/// Sort menu for the Anime and Manga tabs ("Highest Score").
class _MediaSortSelect extends ConsumerWidget {
  const _MediaSortSelect({required this.tab});

  final SearchTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sort = ref.watch(
      searchControllerProvider.select((s) => s.sortOf(tab)),
    );
    final hasQuery = ref.watch(
      searchControllerProvider.select(
        (s) => normalizeSearchText(s.queryOf(tab)).isNotEmpty,
      ),
    );
    final options = [
      if (hasQuery) MediaSort.searchMatch,
      MediaSort.popularity,
      MediaSort.trending,
      MediaSort.score,
      MediaSort.titleRomaji,
    ];
    String label(MediaSort s) => switch (s) {
          MediaSort.popularity => 'Most Popular',
          MediaSort.score => 'Highest Score',
          _ => s.label,
        };
    return FilterFieldBox(
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MediaSort>(
          value: options.contains(sort) ? sort : MediaSort.popularity,
          isExpanded: true,
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          items: [
            for (final s in options)
              DropdownMenuItem(
                value: s,
                child: Text(
                  label(s),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (s) {
            if (s == null) return;
            final notifier = ref.read(searchControllerProvider.notifier);
            if (tab == SearchTab.manga) {
              notifier.setMangaSort(s);
            } else {
              notifier.setAnimeSort(s);
            }
          },
        ),
      ),
    );
  }
}

/// Removable pills for every active criterion ("Genre: Action, Sci-Fi ✕").
class _ActiveFilterChips extends ConsumerWidget {
  const _ActiveFilterChips({required this.tab, required this.scroll});

  final SearchTab tab;

  /// One horizontally scrolling row (phone) instead of a wrapping block.
  final bool scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(
      searchControllerProvider.select((s) => s.filtersOf(tab)),
    );
    final chips = activeFilterChips(filters, manga: tab == SearchTab.manga);
    if (chips.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(searchControllerProvider.notifier);
    final pills = [
      for (final chip in chips)
        ActiveFilterPill(
          key: ValueKey(chip.key),
          label: chip.label,
          onRemove: () => controller.removeFilter(tab, chip.key),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: Tokens.space12),
      child: scroll
          ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(spacing: Tokens.space8, children: pills),
            )
          : Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: Tokens.space8,
                runSpacing: Tokens.space8,
                children: pills,
              ),
            ),
    );
  }
}

/// Studio / Staff / Characters search: a full-width name field, a hairline
/// (wide only) and the "STAFF / 128 results" heading.
class _TabSearchField extends ConsumerWidget {
  const _TabSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
      SearchTab.studios => 'Studio name',
      SearchTab.staff => 'Staff name',
      SearchTab.characters => 'Character name',
    };

    final field = LensSearchField(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space12,
            Tokens.space16,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              if (wide) ...[
                const SizedBox(height: Tokens.space24),
                Divider(height: 1, color: theme.dividerColor),
              ],
              SizedBox(height: wide ? Tokens.space24 : Tokens.space20),
              _PeopleHeading(tab: tab, wide: wide),
            ],
          ),
        );
      },
    );
  }
}

(LoadStatus, int?, int) _pageStats<T>(TabPage<T> page) =>
    (page.status, page.total, page.items.length);

/// "STAFF / 128 results" heading above the people result lists.
class _PeopleHeading extends ConsumerWidget {
  const _PeopleHeading({required this.tab, required this.wide});

  final SearchTab tab;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (status, total, loaded) = ref.watch(
      searchControllerProvider.select(
        (s) => switch (tab) {
          SearchTab.studios => _pageStats(s.studios),
          SearchTab.staff => _pageStats(s.staff),
          _ => _pageStats(s.characters),
        },
      ),
    );
    final eyebrow = switch (tab) {
      SearchTab.studios => 'STUDIOS',
      SearchTab.staff => 'STAFF',
      _ => 'CHARACTERS',
    };
    final count = total ?? loaded;
    final searching = loaded == 0 &&
        (status == LoadStatus.initial || status == LoadStatus.loading);
    final title = searching
        ? 'Searching…'
        : '${_favouritesFormat.format(count)} '
              '${count == 1 ? 'result' : 'results'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Tokens.space4),
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (wide
                  ? theme.textTheme.headlineMedium
                  : theme.textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
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
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text("Couldn't load more."),
              TextButton.icon(
                onPressed:
                    ref.read(searchControllerProvider.notifier).retryLoadMore,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
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
    final filtered = ref.watch(
      searchControllerProvider.select((s) => !s.filtersOf(tab).isEmpty),
    );
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
                  'Try a different spelling, fewer words or fewer filters.'
            : (filtered
                  ? 'No $noun matched these filters. '
                        'Try removing a few criteria.'
                  : 'No $noun found.'),
        icon: Icons.search_off,
      ),
      LoadStatus.success => SliverPosterGrid(items: results, compact: true),
    };
  }
}

/// Loading / error / empty handling shared by the people result lists.
class _PeopleResults<T> extends StatelessWidget {
  const _PeopleResults({
    required this.page,
    required this.query,
    required this.noun,
    required this.onRetry,
    required this.builder,
  });

  final TabPage<T> page;
  final String query;
  final String noun;
  final VoidCallback onRetry;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    final items = page.items;
    if (items.isNotEmpty) return builder(items);
    return switch (page.status) {
      LoadStatus.error => SliverError(
        message: page.errorMessage ?? 'Search failed.',
        onRetry: onRetry,
      ),
      LoadStatus.success => SliverEmpty(
        title: 'No results',
        message: query.trim().isNotEmpty
            ? 'No $noun matched "${query.trim()}".'
            : 'No $noun found.',
        icon: Icons.search_off,
      ),
      _ => const SliverToBoxAdapter(child: LoadingPosterGrid()),
    };
  }
}

class _StudioResults extends ConsumerWidget {
  const _StudioResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(searchControllerProvider.select((s) => s.studios));
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);
    return _PeopleResults<SearchStudio>(
      page: page,
      query: query,
      noun: 'studios',
      onRetry: controller.runSearch,
      builder: (items) => _PeopleList(
        itemCount: items.length,
        itemBuilder: (context, i, card) =>
            _StudioItem(studio: items[i], index: i, card: card),
      ),
    );
  }
}

class _StaffResults extends ConsumerWidget {
  const _StaffResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(searchControllerProvider.select((s) => s.staff));
    final query = ref.watch(searchControllerProvider.select((s) => s.query));
    final controller = ref.read(searchControllerProvider.notifier);
    return _PeopleResults<SearchStaff>(
      page: page,
      query: query,
      noun: 'staff',
      onRetry: controller.runSearch,
      builder: (items) => _PeopleList(
        itemCount: items.length,
        itemBuilder: (context, i, card) =>
            _StaffItem(staff: items[i], index: i, card: card),
      ),
    );
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
    return _PeopleResults<SearchCharacter>(
      page: page,
      query: query,
      noun: 'characters',
      onRetry: controller.runSearch,
      builder: (items) => _CharacterGrid(items: items),
    );
  }
}

const List<Color> _placeholderTints = [
  Color(0xFF1B3D45),
  Color(0xFF254640),
  Color(0xFF203556),
  Color(0xFF3C2F4A),
  Color(0xFF43352E),
];

Color _tintFor(int index) => _placeholderTints[index % _placeholderTints.length];

/// "12.4k" style count for the favourites badge.
String _compactCount(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  return '$value';
}

/// Studio / Staff list: one row per item with a divider on phones, two
/// columns of bordered cards on wide screens.
class _PeopleList extends StatefulWidget {
  const _PeopleList({required this.itemCount, required this.itemBuilder});

  final int itemCount;

  /// `card` is true in the two-column layout, false for plain rows.
  final Widget Function(BuildContext context, int index, bool card)
      itemBuilder;

  @override
  State<_PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends State<_PeopleList> {
  // Same trick as the poster grid: hand back the identical widget until the
  // width or inputs change so scrolling doesn't rebuild every tile.
  Widget? _cached;
  double _cachedWidth = -1;
  double _cachedScale = -1;

  @override
  void didUpdateWidget(covariant _PeopleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cached = null;
  }

  @override
  Widget build(BuildContext context) {
    final textScale = textScaleOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final cached = _cached;
        if (cached != null &&
            _cachedWidth == width &&
            _cachedScale == textScale) {
          return cached;
        }
        // Two bordered cards per row need ~350px each (avatar, two text
        // lines, count pill, chevron); below that a single plain column.
        final card = width >= 760;
        final grid = SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space8,
            Tokens.space16,
            Tokens.space16,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: card ? 2 : 1,
              mainAxisSpacing: card ? Tokens.space16 : 0,
              crossAxisSpacing: Tokens.space16,
              // Fixed row height + the extra the reader's font size needs.
              mainAxisExtent:
                  (card ? 100 : 77) + (textScale - 1) * (card ? 56 : 44),
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: widget.itemCount,
            itemBuilder: (context, index) => RepaintBoundary(
              child: widget.itemBuilder(context, index, card),
            ),
          ),
        );
        _cachedWidth = width;
        _cachedScale = textScale;
        _cached = grid;
        return grid;
      },
    );
  }
}

/// Tinted circle / rounded square with the person's photo, or an icon.
class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.url,
    required this.index,
    required this.size,
    required this.circle,
    this.icon = Icons.person_outline,
  });

  final String url;
  final int index;
  final double size;
  final bool circle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder() => ColoredBox(
          color: _tintFor(index),
          child: Center(
            child: Icon(
              icon,
              size: size * 0.4,
              color: scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(circle ? size / 2 : 16),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? placeholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                cacheWidth: 192,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
                errorBuilder: (context, error, stack) => placeholder(),
              ),
      ),
    );
  }
}

/// Teal "24 credits" pill on the wide cards.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: scheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Shared layout of a Studio / Staff item: avatar, two text lines, optional
/// count pill (cards only) and a chevron. A plain row with a bottom divider
/// on phones, a bordered card on wide screens.
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.card,
    this.pill,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool card;
  final String? pill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Row(
      children: [
        leading,
        const SizedBox(width: Tokens.space16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: Tokens.space4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (card && pill != null) ...[
          const SizedBox(width: Tokens.space12),
          _CountPill(label: pill!),
        ],
        const SizedBox(width: Tokens.space8),
        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      ],
    );
    if (card) {
      return Material(
        color: theme.cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          side: BorderSide(color: theme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: content,
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Tokens.space12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: content,
      ),
    );
  }
}

class _StaffItem extends StatelessWidget {
  const _StaffItem({
    required this.staff,
    required this.index,
    required this.card,
  });

  final SearchStaff staff;
  final int index;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final credits = staff.credits > 0
        ? '${_favouritesFormat.format(staff.credits)} credits'
        : null;
    final subtitle = card
        ? staff.role
        : [
            if (staff.role.isNotEmpty) staff.role,
            ?credits,
          ].join(' · ');
    return _PersonTile(
      leading: _PersonAvatar(
        url: staff.imageUrl,
        index: index,
        size: card ? 60 : 52,
        circle: true,
      ),
      title: staff.nameFull,
      subtitle: subtitle,
      pill: credits,
      card: card,
      onTap: () => context.push(Routes.staffWorks(staff.id)),
    );
  }
}

class _StudioItem extends StatelessWidget {
  const _StudioItem({
    required this.studio,
    required this.index,
    required this.card,
  });

  final SearchStudio studio;
  final int index;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final kind = studio.isAnimationStudio ? 'Animation studio' : 'Studio';
    final titles = studio.titleCount > 0
        ? '${_favouritesFormat.format(studio.titleCount)} '
              '${studio.titleCount == 1 ? 'title' : 'titles'}'
        : null;
    return _PersonTile(
      leading: _PersonAvatar(
        url: '',
        index: index,
        size: card ? 60 : 52,
        circle: false,
        icon: Icons.home_outlined,
      ),
      title: studio.name,
      subtitle: card ? kind : [?titles, kind].join(' · '),
      pill: titles,
      card: card,
      onTap: () => context.push(Routes.studioWorks(studio.id)),
    );
  }
}

/// Poster grid of characters: photo, heart badge, name and first title.
class _CharacterGrid extends StatefulWidget {
  const _CharacterGrid({required this.items});

  final List<SearchCharacter> items;

  @override
  State<_CharacterGrid> createState() => _CharacterGridState();
}

class _CharacterGridState extends State<_CharacterGrid> {
  Widget? _cached;
  double _cachedWidth = -1;
  double _cachedScale = -1;

  @override
  void didUpdateWidget(covariant _CharacterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cached = null;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final textScale = textScaleOf(context);
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final cached = _cached;
        if (cached != null &&
            _cachedWidth == width &&
            _cachedScale == textScale) {
          return cached;
        }
        final columns = browsePosterColumns(width);
        final gap = browseColumnGap(width);
        final tileWidth =
            (width - (columns - 1) * gap - Tokens.space32) / columns;
        final grid = SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space8,
            Tokens.space16,
            Tokens.space32,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: kBrowseRowGap,
              crossAxisSpacing: gap,
              // Poster + gap + two text lines (name, first title).
              mainAxisExtent:
                  tileWidth / Tokens.posterAspect + 20 + 40 * textScale,
            ),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: items.length,
            itemBuilder: (context, index) => RepaintBoundary(
              child: _CharacterTile(character: items[index], index: index),
            ),
          ),
        );
        _cachedWidth = width;
        _cachedScale = textScale;
        _cached = grid;
        return grid;
      },
    );
  }
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({required this.character, required this.index});

  final SearchCharacter character;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const pink = Color(0xFFFF6B9A);
    Widget placeholder() => ColoredBox(
          color: _tintFor(index),
          child: Center(
            child: Icon(
              Icons.person_outline,
              size: 32,
              color: scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        );
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      onTap: () => context.push(Routes.characterWorks(character.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  child: character.imageUrl.isEmpty
                      ? placeholder()
                      : Image.network(
                          character.imageUrl,
                          fit: BoxFit.cover,
                          cacheWidth: 320,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stack) =>
                              placeholder(),
                        ),
                ),
                Positioned(
                  top: Tokens.space8,
                  left: Tokens.space8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(Tokens.radiusMd),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite, size: 13, color: pink),
                        const SizedBox(width: 4),
                        Text(
                          _compactCount(character.favourites),
                          style: const TextStyle(
                            color: pink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.space8),
          Text(
            character.nameFull,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (character.mediaTitle.isNotEmpty)
            Text(
              character.mediaTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
