import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/repositories/media_repository.dart';
import '../../state/browse_controller.dart';
import '../../state/load_state.dart';
import '../components/app_footer.dart';
import '../components/browse_card.dart';
import '../components/browse_filters.dart';
import '../components/pagination_bar.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart' show skeletonEffect;
import '../router/app_router.dart';

/// Browse screen shared by Anime and Manga (different [type]).
///
/// Layout, top to bottom:
///  1. a header card (icon, title, result count and current page);
///  2. one pinned bar: lineup pills (Trending, Airing, Popular, ...) with
///     the Sort menu and the Filters button on the right;
///  3. the poster grid for the current page;
///  4. a page-by-page pager (previous, numbered pages, next).
///
/// Results are paged, not infinite: each page replaces the last and the view
/// returns to the top. There is no search box here; global search lives in
/// the app bar.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({required this.type, this.preset, super.key});

  final MediaType type;

  /// Home "View all" lineup (`?rail=`); null for the plain browse page.
  final BrowsePreset? preset;

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

const double _maxWidth = 1280;

/// Height of the pinned bar's main row (44 px controls + breathing room).
const double _barHeight = 64;
const double _activeRowHeight = 44;

/// Size of the round-cornered Sort / Filters buttons and pager arrows.
const double _toolSize = 44;

/// Posters never get wider than this; the column count follows.
const double _maxTileWidth = 200;

/// Lineup pills, in display order (after "All").
const List<BrowsePreset> _lineups = [
  BrowsePreset.trending,
  BrowsePreset.airing,
  BrowsePreset.popular,
  BrowsePreset.topRated,
  BrowsePreset.upcoming,
  BrowsePreset.topCompleted,
];

String _lineupLabel(BrowsePreset preset, MediaType type) => switch (preset) {
      BrowsePreset.airing =>
        type == MediaType.manga ? 'Publishing' : 'Airing',
      BrowsePreset.trending => 'Trending',
      BrowsePreset.popular => 'Popular',
      BrowsePreset.topRated => 'Top rated',
      BrowsePreset.upcoming => 'Upcoming',
      BrowsePreset.topCompleted => 'Completed',
    };

IconData _lineupIcon(BrowsePreset preset) => switch (preset) {
      BrowsePreset.airing => Icons.sensors_rounded,
      BrowsePreset.trending => Icons.local_fire_department_rounded,
      BrowsePreset.popular => Icons.favorite_rounded,
      BrowsePreset.topRated => Icons.star_rounded,
      BrowsePreset.upcoming => Icons.event_rounded,
      BrowsePreset.topCompleted => Icons.check_circle_rounded,
    };

String _formatCount(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Filters the reader added themselves. A lineup's own status (e.g. "Airing"
/// = Releasing) is part of the lineup pill, so it is not counted again.
int _visibleFilterCount(BrowseState s) {
  final lineupStatus = s.activePreset?.status;
  final implied = lineupStatus != null && lineupStatus == s.query.status;
  return s.query.activeFilterCount - (implied ? 1 : 0);
}

/// Poster grid metrics for a content [width]: as many columns as fit without
/// posters growing past [_maxTileWidth] (always at least two), and an exact
/// row height (poster + text block) so cards never overflow or stretch.
SliverGridDelegate _gridDelegate(
  BuildContext context, {
  required double width,
  required double gutter,
}) {
  final usable = width - gutter * 2;
  final spacing = width >= 600 ? Tokens.space16 : Tokens.space12;
  final columns = math.max(2, (usable / (_maxTileWidth + spacing)).ceil());
  final tileWidth = (usable - (columns - 1) * spacing) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    mainAxisSpacing: width >= 600 ? Tokens.space24 : Tokens.space20,
    crossAxisSpacing: spacing,
    mainAxisExtent:
        tileWidth / Tokens.posterAspect + browseCardTextHeight(context),
  );
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  late final BouncyScrollController _controller;
  // A notifier (not setState) so crossing the threshold only rebuilds the
  // floating button, not the whole screen.
  final ValueNotifier<bool> _showTop = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _controller = BouncyScrollController();
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

  /// Applies (or clears) the route's lineup once the provider is readable.
  ///
  /// A lineup that is already applied and untouched is left alone, so coming
  /// back from a title page keeps the page the reader was on.
  void _syncPreset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = browseControllerProvider(widget.type);
      final controller = ref.read(provider.notifier);
      final preset = widget.preset;
      if (preset != null) {
        if (ref.read(provider).activePreset != preset) {
          controller.applyPreset(preset);
        }
      } else {
        controller.clearPreset();
      }
    });
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final show = _controller.offset > 900;
    if (show != _showTop.value) _showTop.value = show;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    _showTop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showActive = ref.watch(
      browseControllerProvider(widget.type)
          .select((s) => _visibleFilterCount(s) > 0),
    );

    ref.listen<LoadStatus>(
      browseControllerProvider(widget.type).select((s) => s.status),
      (previous, next) {
        // A new page or a new filter set replaces the grid: start at the top.
        if (next == LoadStatus.loading &&
            previous != LoadStatus.loading &&
            _controller.hasClients &&
            _controller.offset > 0) {
          _controller.jumpTo(0);
        }
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, _maxWidth);
        final gutter = width >= 600 ? Tokens.space24 : Tokens.space16;
        final barHeight = _barHeight + (showActive ? _activeRowHeight : 0);
        final delegate = _gridDelegate(context, width: width, gutter: gutter);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Stack(
              children: [
                SmoothCustomScrollView(
                  controller: _controller,
                  slivers: [
                    SliverToBoxAdapter(
                      child: _Header(type: widget.type, gutter: gutter),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _BarDelegate(
                        height: barHeight,
                        child: _ControlsBar(
                          type: widget.type,
                          gutter: gutter,
                          wide: width >= 720,
                          showActive: showActive,
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: Tokens.space16),
                    ),
                    _Results(
                      type: widget.type,
                      gutter: gutter,
                      delegate: delegate,
                    ),
                    SliverToBoxAdapter(
                      child: _PagerSection(type: widget.type, gutter: gutter),
                    ),
                    const SliverAppFooter(),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 24,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _showTop,
                    builder: (context, show, _) => BackToTopButton(
                      visible: show,
                      onPressed: () {
                        if (_controller.hasClients) _controller.smoothTo(0);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// Accent-tinted card: type icon, title (or lineup name), result count and
/// the page the reader is on.
class _Header extends ConsumerWidget {
  const _Header({required this.type, required this.gutter});

  final MediaType type;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isManga = type == MediaType.manga;
    final compact = MediaQuery.sizeOf(context).width < 600;

    final info = ref.watch(
      browseControllerProvider(type).select(
        (s) => (total: s.totalItems, page: s.currentPage, pages: s.pageCount),
      ),
    );
    // The lineup name shows only while the query still matches the lineup
    // (manual filter or sort edits fall back to the plain title).
    final title = ref.watch(
      browseControllerProvider(type).select(
        (s) => s.activePreset?.titleFor(type) ?? (isManga ? 'Manga' : 'Anime'),
      ),
    );

    final total = info.total;
    final String subtitle;
    if (total == null || total <= 0) {
      subtitle = isManga ? 'Discover series and chapters' : 'Discover shows and movies';
    } else if (info.pages > 1) {
      subtitle =
          '${_formatCount(total)} titles · Page ${info.page}';
    } else {
      subtitle = '${_formatCount(total)} titles';
    }

    final icon = isManga ? Icons.menu_book_rounded : Icons.movie_rounded;
    final radius = BorderRadius.circular(Tokens.radiusXl);
    final badge = compact ? 48.0 : 56.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        Tokens.space16,
        gutter,
        Tokens.space16,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              scheme.primary.withValues(alpha: isDark ? 0.24 : 0.14),
              scheme.primary.withValues(alpha: 0.03),
            ],
          ),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned(
                right: -10,
                bottom: -22,
                child: Icon(
                  icon,
                  size: 128,
                  color: scheme.primary.withValues(alpha: 0.08),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(
                  compact ? Tokens.space16 : Tokens.space20,
                ),
                child: Row(
                  children: [
                    Container(
                      width: badge,
                      height: badge,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(Tokens.radiusLg),
                      ),
                      child: Icon(
                        icon,
                        size: compact ? 26 : 30,
                        color: scheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: Tokens.space16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
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

// ---------------------------------------------------------------------------
// Pinned controls: lineup pills, sort, filters, active filters
// ---------------------------------------------------------------------------

/// Pinned header that draws a hairline under itself once content scrolls
/// beneath it.
class _BarDelegate extends SliverPersistentHeaderDelegate {
  _BarDelegate({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Tokens.durationFast,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      // Painted over the child instead of as a border: a border would take
      // 1px of layout height and overflow the fixed-height controls bar.
      foregroundDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: overlapsContent ? scheme.outlineVariant : Colors.transparent,
          ),
        ),
      ),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _BarDelegate oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

class _ControlsBar extends StatelessWidget {
  const _ControlsBar({
    required this.type,
    required this.gutter,
    required this.wide,
    required this.showActive,
  });

  final MediaType type;
  final double gutter;

  /// Enough room for text labels next to the Sort / Filters icons.
  final bool wide;
  final bool showActive;

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: gutter);
    return Column(
      children: [
        SizedBox(
          height: _barHeight,
          child: Padding(
            padding: pad,
            child: Row(
              children: [
                Expanded(child: _LineupPills(type: type)),
                const SizedBox(width: Tokens.space8),
                _SortMenu(type: type, showLabel: wide),
                const SizedBox(width: Tokens.space8),
                _FilterButton(type: type, showLabel: wide),
              ],
            ),
          ),
        ),
        if (showActive)
          SizedBox(
            height: _activeRowHeight,
            child: Padding(padding: pad, child: _ActiveFilters(type: type)),
          ),
      ],
    );
  }
}

/// Horizontally scrolling lineup pills: All, Trending, Airing, ...
class _LineupPills extends ConsumerWidget {
  const _LineupPills({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      browseControllerProvider(type).select((s) => s.activePreset),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);

    // Keep the URL in step with the pill so the page can be shared/reloaded.
    void select(BrowsePreset? preset) {
      if (preset == null) {
        controller.showAll();
        context.go(type == MediaType.manga ? Routes.manga : Routes.anime);
      } else {
        controller.applyPreset(preset);
        context.go(Routes.browseRail(type, preset));
      }
    }

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      // Soft fade on the right edge hints that the row scrolls.
      shaderCallback: (bounds) => const LinearGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.94, 1.0],
      ).createShader(bounds),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: Tokens.space24),
        itemCount: _lineups.length + 1,
        separatorBuilder: (context, index) =>
            const SizedBox(width: Tokens.space8),
        itemBuilder: (context, index) {
          final preset = index == 0 ? null : _lineups[index - 1];
          return Center(
            child: _LineupPill(
              label: preset == null ? 'All' : _lineupLabel(preset, type),
              icon: preset == null ? Icons.apps_rounded : _lineupIcon(preset),
              selected: preset == active,
              onTap: () => select(preset),
            ),
          );
        },
      ),
    );
  }
}

class _LineupPill extends StatelessWidget {
  const _LineupPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primary
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Outlined 44 px button shared by Sort and Filters: a 22 px icon, plus a
/// text label when there is room. [active] tints it with the accent.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String? label;

  /// Null when the button is the child of something that handles taps
  /// itself (the Sort popup menu).
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Tokens.radiusLg - 2);
    final color = active ? scheme.primary : scheme.onSurface;
    final content = Container(
      height: _toolSize,
      constraints: const BoxConstraints(minWidth: _toolSize),
      padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: active ? scheme.primary.withValues(alpha: 0.10) : null,
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          if (label != null) ...[
            const SizedBox(width: Tokens.space8),
            Text(
              label!,
              style: theme.textTheme.labelLarge?.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(borderRadius: radius, onTap: onTap, child: content);
  }
}

/// Sort is a single menu button; the label shows the current order.
class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.type, required this.showLabel});

  final MediaType type;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(
      browseControllerProvider(type).select((s) => s.query.sort),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);
    return PopupMenuButton<MediaSort>(
      tooltip: 'Sort: ${browseSortLabel(sort)}',
      initialValue: sort,
      onSelected: controller.setSort,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg - 2),
      ),
      itemBuilder: (context) => [
        for (final value in MediaSort.browseOptions)
          CheckedPopupMenuItem<MediaSort>(
            value: value,
            checked: value == sort,
            child: Text(browseSortLabel(value)),
          ),
      ],
      child: _ToolButton(
        icon: Icons.swap_vert_rounded,
        label: showLabel ? browseSortLabel(sort) : null,
      ),
    );
  }
}

class _FilterButton extends ConsumerWidget {
  const _FilterButton({required this.type, required this.showLabel});

  final MediaType type;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      browseControllerProvider(type).select(_visibleFilterCount),
    );
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Tooltip(
        message: 'Filters',
        child: _ToolButton(
          icon: Icons.tune_rounded,
          label: showLabel ? 'Filters' : null,
          active: count > 0,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            constraints: const BoxConstraints(maxWidth: 560),
            builder: (_) => _FilterSheet(type: type),
          ),
        ),
      ),
    );
  }
}

/// Removable chips summarising the filters the reader added.
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(
      browseControllerProvider(type).select(
        (s) => (query: s.query, lineupStatus: s.activePreset?.status),
      ),
    );
    final query = data.query;
    final controller = ref.read(browseControllerProvider(type).notifier);

    Widget chip(String label, VoidCallback onDeleted) => InputChip(
          label: Text(label),
          onDeleted: onDeleted,
          visualDensity: VisualDensity.compact,
        );
    void apply(BrowseQuery q) => controller.applyQuery(q);

    final chips = <Widget>[
      if (query.genre != null && query.genre!.isNotEmpty)
        chip(query.genre!, () => apply(editBrowseQuery(query, genre: null))),
      if (query.format != null)
        chip(
          query.format!.label,
          () => apply(editBrowseQuery(query, format: null)),
        ),
      // The lineup's own status is already shown by the selected pill.
      if (query.status != null && query.status != data.lineupStatus)
        chip(
          query.status!.label,
          () => apply(editBrowseQuery(query, status: null)),
        ),
      if (query.season != null)
        chip(
          query.season!.label,
          () => apply(editBrowseQuery(query, season: null)),
        ),
      if (query.seasonYear != null)
        chip(
          '${query.seasonYear}',
          () => apply(editBrowseQuery(query, seasonYear: null)),
        ),
      if (query.minScore != null)
        chip(
          '≥ ${(query.minScore! / 10).toStringAsFixed(1)}',
          () => apply(editBrowseQuery(query, minScore: null)),
        ),
      if (query.countryOfOrigin != null)
        chip(
          kCountries[query.countryOfOrigin] ?? query.countryOfOrigin!,
          () => apply(editBrowseQuery(query, country: null)),
        ),
      if (query.source != null)
        chip(
          query.source!.label,
          () => apply(editBrowseQuery(query, source: null)),
        ),
      if (query.isAdult)
        chip('Adult', () => apply(editBrowseQuery(query, isAdult: false))),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final c in chips)
          Padding(
            padding: const EdgeInsets.only(right: Tokens.space8),
            child: Center(child: c),
          ),
        Center(
          child: TextButton(
            onPressed: controller.clearFilters,
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            child: const Text('Clear all'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Filters sheet
// ---------------------------------------------------------------------------

/// Filter sheet. Edits a draft; "Show results" applies it with a
/// single reload instead of one request per tapped chip.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.type});

  final MediaType type;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late BrowseQuery _draft;

  @override
  void initState() {
    super.initState();
    _draft = ref.read(browseControllerProvider(widget.type)).query;
  }

  void _apply() {
    ref.read(browseControllerProvider(widget.type).notifier).applyQuery(_draft);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = _draft.activeFilterCount;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space20,
              0,
              Tokens.space12,
              Tokens.space8,
            ),
            child: Row(
              children: [
                Text(
                  count > 0 ? 'Filters ($count)' : 'Filters',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: count > 0
                      ? () => setState(
                            () => _draft = resetBrowseFilters(_draft),
                          )
                      : null,
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(Tokens.space20),
              children: [
                BrowseFilterForm(
                  query: _draft,
                  onChanged: (q) => setState(() => _draft = q),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Tokens.space16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _apply,
                  child: const Text('Show results'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// Skeleton while a page loads, error, empty, or the card grid.
class _Results extends ConsumerWidget {
  const _Results({
    required this.type,
    required this.gutter,
    required this.delegate,
  });

  final MediaType type;
  final double gutter;
  final SliverGridDelegate delegate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      browseControllerProvider(type).select((s) => s.status),
    );
    final items = ref.watch(
      browseControllerProvider(type).select((s) => s.items),
    );
    final errorMessage = ref.watch(
      browseControllerProvider(type).select((s) => s.errorMessage),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);

    if (status == LoadStatus.error) {
      return SliverError(
        message: errorMessage ?? 'Could not load titles.',
        onRetry: controller.retry,
      );
    }
    final loading =
        status == LoadStatus.initial || status == LoadStatus.loading;
    if (!loading && items.isEmpty) {
      return SliverEmpty(
        title: 'No results',
        message:
            'No ${type.label.toLowerCase()} match these filters. '
            'Try widening them.',
        icon: Icons.search_off_rounded,
        actionLabel: 'Clear filters',
        onAction: controller.clearFilters,
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      sliver: loading
          ? _SkeletonGrid(delegate: delegate)
          : SliverGrid(
              gridDelegate: delegate,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final media = items[index];
                  return KeyedSubtree(
                    key: ValueKey(media.id),
                    child: RevealOnScroll(
                      revealKey: media.id,
                      index: index,
                      slide: 8,
                      child: RepaintBoundary(child: BrowseCard(media: media)),
                    ),
                  );
                },
                childCount: items.length,
                addAutomaticKeepAlives: false,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<int>) return null;
                  final i = items.indexWhere((m) => m.id == key.value);
                  return i < 0 ? null : i;
                },
              ),
            ),
    );
  }
}

/// Below the grid: the pager and a one-line "Showing 25–48 of 2,880".
class _PagerSection extends ConsumerWidget {
  const _PagerSection({required this.type, required this.gutter});

  final MediaType type;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final data = ref.watch(
      browseControllerProvider(type).select(
        (s) => (
          status: s.status,
          page: s.currentPage,
          pages: s.pageCount,
          hasNext: s.hasNextPage,
          shown: s.items.length,
          perPage: s.query.perPage,
          total: s.totalItems,
        ),
      ),
    );
    final controller = ref.read(browseControllerProvider(type).notifier);

    final paged = data.status == LoadStatus.success ||
        data.status == LoadStatus.loading;
    if (!paged || data.shown == 0) {
      return const SizedBox(height: Tokens.space32);
    }

    final busy = data.status == LoadStatus.loading;
    final total = data.total;
    final from = (data.page - 1) * data.perPage + 1;
    final to = from + data.shown - 1;
    final String summary;
    if (busy) {
      summary = 'Loading page ${data.page}…';
    } else if (total != null && total > 0) {
      summary =
          'Showing ${_formatCount(from)}–${_formatCount(to)} of ${_formatCount(total)}';
    } else {
      summary = 'Page ${data.page}';
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        Tokens.space32,
        gutter,
        Tokens.space32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (data.pages > 1)
            PaginationBar(
              page: data.page,
              pageCount: data.pages,
              hasNext: data.hasNext,
              busy: busy,
              onPageSelected: controller.goToPage,
            ),
          if (data.pages > 1) const SizedBox(height: Tokens.space12),
          Text(
            summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton
// ---------------------------------------------------------------------------

/// One page of placeholder cards, shown while a page loads. The cards are
/// ordinary widgets filled with dummy text; one [Skeletonizer] turns every
/// text run and decorated box into a shimmering bone.
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid({required this.delegate});

  static const int _count = 24;

  final SliverGridDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Skeletonizer(
        enabled: true,
        effect: skeletonEffect(context),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          addAutomaticKeepAlives: false,
          gridDelegate: delegate,
          itemCount: _count,
          itemBuilder: (context, index) => const _CardSkeleton(),
        ),
      ),
    );
  }
}

/// Same silhouette as [BrowseCard]: poster, then a two-line title and a meta
/// line, using the card's own text block height so the grid never jumps.
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(Tokens.radiusLg),
            ),
          ),
        ),
        SizedBox(
          height: browseCardTextHeight(context),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Placeholder series title that wraps',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'TV · 2024',
                  maxLines: 1,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
