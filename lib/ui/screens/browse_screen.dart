import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../state/browse_controller.dart';
import '../../state/load_state.dart';
import '../components/app_footer.dart';
import '../components/browse_card.dart';
import '../components/browse_filters.dart' show browseSortLabel;
import '../components/pagination_bar.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart'
    show SkeletonBone, SkeletonLine, SkeletonShimmer;
import '../router/app_router.dart';

/// Browse screen shared by Anime and Manga (different [type]).
///
/// Layout, top to bottom:
///  1. a header card (icon, title, result count and current page);
///  2. one pinned bar: lineup pills (Trending, Airing, Popular, ...) with
///     the Sort menu on the right;
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

/// Size of the round-cornered Sort button and pager arrows.
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
                        height: _barHeight,
                        child: _ControlsBar(
                          type: widget.type,
                          gutter: gutter,
                          wide: width >= 720,
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
// Pinned controls: lineup pills and sort
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
  });

  final MediaType type;
  final double gutter;

  /// Enough room for a text label next to the Sort icon.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: gutter);
    return SizedBox(
      height: _barHeight,
      child: Padding(
        padding: pad,
        child: Row(
          children: [
            Expanded(child: _LineupPills(type: type)),
            const SizedBox(width: Tokens.space8),
            _SortMenu(type: type, showLabel: wide),
          ],
        ),
      ),
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

/// Outlined 44 px button used by Sort: a 22 px icon, plus a
/// text label when there is room. Taps are handled by the Sort popup menu
/// that wraps it.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    this.label,
  });

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Tokens.radiusLg - 2);
    final color = scheme.onSurface;
    final content = Container(
      height: _toolSize,
      constraints: const BoxConstraints(minWidth: _toolSize),
      padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
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
    return content;
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
            'No ${type.label.toLowerCase()} found for this lineup. '
            'Try another one.',
        icon: Icons.search_off_rounded,
        actionLabel: 'Show all',
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
/// ordinary widgets filled with dummy text; one [SkeletonShimmer] sweeps
/// every bone in the grid.
class _SkeletonGrid extends StatelessWidget {
  const _SkeletonGrid({required this.delegate});

  static const int _count = 24;

  final SliverGridDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: SkeletonShimmer(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: SkeletonBone(radius: Tokens.radiusLg)),
        SizedBox(
          height: browseCardTextHeight(context),
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(height: 12),
                SizedBox(height: 6),
                SkeletonLine(fraction: 0.5, height: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
