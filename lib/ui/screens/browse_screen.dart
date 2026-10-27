import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../state/browse_controller.dart';
import '../../state/load_state.dart';
import '../components/media_grid.dart';
import '../components/app_footer.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart';
import 'filters_sheet.dart';

/// Browse screen shared by Anime and Manga (different [type]).
///
/// Single-scrollable sliver version: one [CustomScrollView] owns the scroll,
/// the title + filter bar scroll away, active filters stick, then a
/// `Page N` pager sits above a true `SliverGrid` — no nested `GridView`,
/// no gesture fights, and infinite scroll fires from the outer controller
/// (throttled).
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({required this.type, this.preset, super.key});

  final MediaType type;

  /// Home "View all" lineup (`?rail=`); null for the plain browse page.
  final BrowsePreset? preset;

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  late final ScrollController _controller;
  DateTime _lastEndReached = DateTime.fromMillisecondsSinceEpoch(0);
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
    _syncPreset();
  }

  @override
  void didUpdateWidget(covariant BrowseScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset || oldWidget.type != widget.type) {
      _syncPreset();
    }
  }

  /// Applies (or clears) the route's preset once the provider is readable.
  void _syncPreset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller =
          ref.read(browseControllerProvider(widget.type).notifier);
      final preset = widget.preset;
      if (preset != null) {
        controller.applyPreset(preset);
      } else {
        controller.clearPreset();
      }
    });
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final show = _controller.offset > 900;
    if (show != _showTop && mounted) setState(() => _showTop = show);
    final hasMore = ref.read(
      browseControllerProvider(widget.type).select((s) => s.hasNextPage),
    );
    if (!hasMore) return;
    final max = _controller.position.maxScrollExtent;
    if (max > 0 && _controller.offset >= max - 480) {
      final now = DateTime.now();
      if (now.difference(_lastEndReached) >
          const Duration(milliseconds: 500)) {
        _lastEndReached = now;
        ref.read(browseControllerProvider(widget.type).notifier).loadMore();
      }
    }
  }

  void scrollToTop() {
    if (_controller.hasClients) _controller.smoothTo(0);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters = ref.watch(
      browseControllerProvider(widget.type).select((s) => s.query.hasFilters),
    );

    return Stack(
      children: [
        SmoothCustomScrollView(
          controller: _controller,
          slivers: [
            SliverToBoxAdapter(child: _Toolbar(type: widget.type)),
            SliverToBoxAdapter(
              child: _FilterBar(
                type: widget.type,
                onMoreTap: () => _openFilters(context, ref),
              ),
            ),
            if (hasFilters)
              SliverPersistentHeader(
                pinned: true,
                delegate: StickyHeaderDelegate(
                  height: 48,
                  child: _ActiveFilters(type: widget.type),
                ),
              ),
            SliverToBoxAdapter(child: _PageNav(type: widget.type)),
            _GridSlivers(type: widget.type),
            const SliverAppFooter(),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 24,
          child: BackToTopButton(
            visible: _showTop,
            onPressed: () {
              if (_controller.hasClients) _controller.smoothTo(0);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openFilters(BuildContext context, WidgetRef ref) async {
    final query = ref.read(browseControllerProvider(widget.type)).query;
    final result = await showModalBottomSheet<FilterSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FilterSheet(initial: query),
    );
    if (result != null && context.mounted) {
      await ref
          .read(browseControllerProvider(widget.type).notifier)
          .applyFilters(
            genre: result.genre,
            status: result.status,
            format: result.format,
            season: result.season,
            seasonYear: result.seasonYear,
            sort: result.sort,
          );
    }
  }
}

/// Grid states as slivers: loading skeleton, error, empty, or the grid.
class _GridSlivers extends ConsumerWidget {
  const _GridSlivers({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      browseControllerProvider(type).select((s) => s.status),
    );
    final items = ref.watch(
      browseControllerProvider(type).select((s) => s.items),
    );
    final hasNextPage = ref.watch(
      browseControllerProvider(type).select((s) => s.hasNextPage),
    );
    final errorMessage = ref.watch(
      browseControllerProvider(type).select((s) => s.errorMessage),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);

    return switch (status) {
      LoadStatus.initial => const SliverToBoxAdapter(
        child: LoadingPosterGrid(),
      ),
      LoadStatus.loading when items.isEmpty =>
        const SliverToBoxAdapter(child: LoadingPosterGrid()),
      LoadStatus.loading => SliverPosterGrid(
        items: items,
        hasMore: true,
      ),
      LoadStatus.error when items.isEmpty => SliverError(
        message: errorMessage ?? 'Could not load titles.',
        onRetry: controller.retry,
      ),
      // Keep-previous-data: error with cached items still shows the grid.
      LoadStatus.error => SliverPosterGrid(
        items: items,
        hasMore: hasNextPage,
      ),
      LoadStatus.success when items.isEmpty => SliverEmpty(
        title: 'No results',
        message:
            'No ${type.label.toLowerCase()} match these filters. '
            'Try widening your search.',
        icon: Icons.search_off,
      ),
      LoadStatus.success => SliverPosterGrid(
        items: items,
        hasMore: hasNextPage,
      ),
    };
  }
}

/// Title + result count.
class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isManga = type == MediaType.manga;
    final count = ref.watch(
      browseControllerProvider(type).select((s) => s.items.length),
    );
    final hasMore = ref.watch(
      browseControllerProvider(type).select((s) => s.hasNextPage),
    );
    // Show the lineup name only while the query still matches the preset
    // (manual filter/sort edits fall back to the plain title).
    final title = ref.watch(
      browseControllerProvider(type).select((s) {
        final p = s.preset;
        final q = s.query;
        final untouched =
            p != null &&
            q.sort == p.sort &&
            q.status == p.status &&
            (q.genre == null || q.genre!.isEmpty) &&
            q.format == null &&
            q.season == null &&
            q.seasonYear == null &&
            q.search.trim().isEmpty;
        return untouched ? p.titleFor(type) : (isManga ? 'Manga' : 'Anime');
      }),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        Tokens.space4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  gradient: Tokens.brandGradient,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: Tokens.space8),
              Flexible(
                child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                ),
              ),
              const SizedBox(width: Tokens.space8),
              AnimatedSwitcher(
                duration: Tokens.durationFast,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Container(
                  key: ValueKey('$count:$hasMore'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: Tokens.brandGradient,
                    borderRadius: BorderRadius.circular(Tokens.radiusPill),
                  ),
                  child: Text(
                    '$count${hasMore ? '+' : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2),
            child: Text(
              'Discover ${isManga ? 'series and chapters' : 'shows and movies'}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline filter bar: Genres / Formats / Status / Year / Sort dropdowns plus
/// a reset button and an overflow button for the full filter sheet
/// (anime season lives there).
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.type, required this.onMoreTap});

  final MediaType type;
  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(
      browseControllerProvider(type).select((s) => s.query),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);
    final isManga = type == MediaType.manga;

    final formats = isManga
        ? const [MediaFormat.manga, MediaFormat.novel, MediaFormat.oneShot]
        : const [
            MediaFormat.tv,
            MediaFormat.tvShort,
            MediaFormat.movie,
            MediaFormat.special,
            MediaFormat.ova,
            MediaFormat.ona,
            MediaFormat.music,
          ];
    final statuses =
        MediaStatus.values.where((s) => s != MediaStatus.unknown).toList();
    final thisYear = DateTime.now().year;
    final years = List.generate(thisYear + 2 - 1970, (i) => thisYear + 1 - i);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        Tokens.space4,
      ),
      child: Row(
        spacing: Tokens.space8,
        children: [
          _FilterDropdown<String>(
            width: 150,
            hint: 'Genres',
            value: query.genre,
            items: [
              for (final genre in kGenres)
                DropdownMenuItem(value: genre, child: Text(genre)),
            ],
            onChanged: controller.setGenre,
          ),
          _FilterDropdown<MediaFormat>(
            width: 150,
            hint: 'Formats',
            value: query.format == MediaFormat.unknown ? null : query.format,
            items: [
              for (final format in formats)
                DropdownMenuItem(
                  value: format,
                  child: Text(format.label),
                ),
            ],
            onChanged: controller.setFormat,
          ),
          _FilterDropdown<MediaStatus>(
            width: 150,
            hint: 'Status',
            value: query.status,
            items: [
              for (final status in statuses)
                DropdownMenuItem(
                  value: status,
                  child: Text(status.label),
                ),
            ],
            onChanged: controller.setStatus,
          ),
          _FilterDropdown<int>(
            width: 130,
            hint: 'Year',
            icon: Icons.calendar_month_outlined,
            value: query.seasonYear,
            items: [
              for (final year in years)
                DropdownMenuItem(value: year, child: Text('$year')),
            ],
            onChanged: controller.setYear,
          ),
          _FilterDropdown<MediaSort>(
            width: 170,
            hint: 'Most Popular',
            value: query.sort,
            items: [
              for (final sort in MediaSort.values)
                DropdownMenuItem(
                  value: sort,
                  child: Text(_sortLabel(sort)),
                ),
            ],
            onChanged: (sort) {
              if (sort != null) controller.setSort(sort);
            },
          ),
          _BarButton(
            tooltip: query.hasFilters ? 'Reset filters' : 'No filters to reset',
            icon: Icons.restart_alt_outlined,
            onPressed: query.hasFilters ? controller.clearFilters : null,
          ),
          _BarButton(
            tooltip: 'More filters',
            icon: Icons.tune_outlined,
            onPressed: onMoreTap,
          ),
        ],
      ),
    );
  }
}

String _sortLabel(MediaSort sort) => switch (sort) {
      MediaSort.popularity => 'Most Popular',
      MediaSort.trending => 'Trending',
      MediaSort.score => 'Top Rated',
      MediaSort.favourites => 'Most Favorited',
      MediaSort.startDate => 'Newest',
      MediaSort.updated => 'Recently Updated',
      MediaSort.titleRomaji => 'A – Z',
    };

/// Outlined dropdown box used by the filter bar.
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.width,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  final double width;
  final String hint;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasValue =
        value != null && (value is! String || (value as String).isNotEmpty);
    return Container(
      width: width,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: Tokens.space12),
      decoration: BoxDecoration(
        border: Border.all(
          color: hasValue ? scheme.primary : scheme.outlineVariant,
          width: hasValue ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          hint: Row(
            spacing: Tokens.space4,
            children: [
              if (icon != null)
                Icon(icon, size: 16, color: scheme.onSurfaceVariant),
              Flexible(
                child: Text(
                  hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          items: [
            DropdownMenuItem<T?>(
              child: Text(
                hasValue ? 'All' : hint,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            ...items,
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Small outlined square button used at the end of the filter bar.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
            ),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }
}

/// "Page N" label with prev/next arrows.
class _PageNav extends ConsumerWidget {
  const _PageNav({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final page = ref.watch(
      browseControllerProvider(type).select((s) => s.query.page),
    );
    final hasNextPage = ref.watch(
      browseControllerProvider(type).select((s) => s.hasNextPage),
    );
    final isLoading = ref.watch(
      browseControllerProvider(type).select(
        (s) => s.status == LoadStatus.loading || s.isLoadingMore,
      ),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);

    Future<void> goTo(int target) async {
      await controller.goToPage(target);
      if (context.mounted) {
        context
            .findAncestorStateOfType<_BrowseScreenState>()
            ?.scrollToTop();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space8,
        Tokens.space16,
        0,
      ),
      child: Row(
        children: [
          Text(
            'Page $page',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          IconButton.outlined(
            tooltip: 'Previous page',
            visualDensity: VisualDensity.compact,
            onPressed: page <= 1 || isLoading ? null : () => goTo(page - 1),
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          const SizedBox(width: Tokens.space8),
          IconButton.outlined(
            tooltip: 'Next page',
            visualDensity: VisualDensity.compact,
            onPressed: !hasNextPage || isLoading ? null : () => goTo(page + 1),
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }
}

/// Removable chips summarising the active filters (sticky).
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(
      browseControllerProvider(type).select((s) => s.query),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);

    // Re-applies every filter except the one being removed.
    Future<void> clear({
      bool withGenre = true,
      bool withStatus = true,
      bool withFormat = true,
      bool withSeason = true,
    }) {
      return controller.applyFilters(
        genre: withGenre ? query.genre : null,
        status: withStatus ? query.status : null,
        format: withFormat ? query.format : null,
        season: withSeason ? query.season : null,
        seasonYear: withSeason ? query.seasonYear : null,
        sort: query.sort,
      );
    }

    final chips = <Widget>[
      if (query.search.trim().isNotEmpty)
        InputChip(
          label: Text('"${query.search.trim()}"'),
          onDeleted: () => controller.setSearch(''),
        ),
      if (query.genre != null && query.genre!.isNotEmpty)
        InputChip(
          label: Text(query.genre!),
          onDeleted: () => clear(withGenre: false),
        ),
      if (query.status != null)
        InputChip(
          label: Text(query.status!.label),
          onDeleted: () => clear(withStatus: false),
        ),
      if (query.format != null)
        InputChip(
          label: Text(query.format!.label),
          onDeleted: () => clear(withFormat: false),
        ),
      if (query.season != null)
        InputChip(
          label: Text(
            query.seasonYear != null
                ? '${query.season!.label} ${query.seasonYear}'
                : query.season!.label,
          ),
          onDeleted: () => clear(withSeason: false),
        ),
      if (query.season == null && query.seasonYear != null)
        InputChip(
          label: Text('${query.seasonYear}'),
          onDeleted: () => clear(withSeason: false),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space16,
        vertical: Tokens.space8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(spacing: Tokens.space8, children: chips),
      ),
    );
  }
}
