import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/models/media_entry.dart';
import 'poster_card.dart';
import 'rails.dart';
import 'state_views.dart';

/// Grid of posters for tracked entries, with a progress bar under each.
///
/// Rendering: `GridView.builder` with repaint boundaries and no keep-alives
/// for offscreen tiles; images use gapless playback to avoid flicker.
class MediaEntryGrid extends StatelessWidget {
  const MediaEntryGrid({required this.entries, super.key});

  final List<MediaEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = posterColumns(constraints.maxWidth);
        final columnGap = posterColumnGap(constraints.maxWidth);
        final tileWidth =
            (constraints.maxWidth -
                (columns - 1) * columnGap -
                Tokens.space32) /
            columns;
        final tileHeight = tileWidth / Tokens.posterAspect + 92;

        return GridView.builder(
          physics: const SmoothScrollPhysics(),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          padding: const EdgeInsets.only(
            left: Tokens.space16,
            right: Tokens.space16,
            bottom: Tokens.space32,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: posterRowGap(constraints.maxWidth),
            crossAxisSpacing: columnGap,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) => RevealOnScroll(
            index: index,
            child: RepaintBoundary(
              child: _EntryTile(entry: entries[index]),
            ),
          ),
        );
      },
    );
  }
}

/// One tracked title: poster, progress bar, title and counters.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final MediaEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = entry.fraction;
    return HoverLift(
      lift: 4,
      scale: 1.015,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
                boxShadow: Tokens.cardShadow(theme.brightness),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
                child: entry.coverUrl == null || entry.coverUrl!.isEmpty
                    ? ColoredBox(
                        color: theme.disabledColor.withValues(alpha: 0.12),
                      )
                    : Image.network(
                        entry.coverUrl!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stack) => ColoredBox(
                          color: theme.disabledColor.withValues(alpha: 0.12),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: Tokens.space8),
          Text(
            entry.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Tokens.space2),
          Text(
            '${entry.progress}'
            '${entry.totalUnits != null ? '/${entry.totalUnits}' : ''}'
            ' ${entry.unit}${entry.progress == 1 ? '' : 's'}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (fraction != null) ...[
            const SizedBox(height: Tokens.space4),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
              // Animate progress changes instead of jumping.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction),
                duration: Tokens.durationMedium,
                curve: Tokens.curveSmooth,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 5,
                  backgroundColor: theme.dividerColor,
                  valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Adaptive poster grid with infinite-scroll support + animated back-to-top.
///
/// - End-reached is throttled (500ms) so fast flings fire one `loadMore`.
/// - A [ScrollController] is owned here and disposed properly; it drives
///   the floating back-to-top button (fade + scale entrance).
class MediaGrid extends StatefulWidget {
  const MediaGrid({
    required this.items,
    this.onEndReached,
    this.hasMore = false,
    super.key,
  });

  final List<Media> items;
  final VoidCallback? onEndReached;
  final bool hasMore;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  late final ScrollController _controller;
  DateTime _lastEndReached = DateTime.fromMillisecondsSinceEpoch(0);
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _controller.hasClients && _controller.offset > 900;
    if (show != _showTop && mounted) setState(() => _showTop = show);
    if (widget.hasMore && widget.onEndReached != null) {
      if (!_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      final pixels = _controller.offset;
      if (max > 0 && pixels >= max - 320) {
        final now = DateTime.now();
        // Throttle: at most one load per 500ms.
        if (now.difference(_lastEndReached) >
            const Duration(milliseconds: 500)) {
          _lastEndReached = now;
          widget.onEndReached!();
        }
      }
    }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = posterColumns(constraints.maxWidth);
        final columnGap = posterColumnGap(constraints.maxWidth);
        final tileWidth =
            (constraints.maxWidth -
                (columns - 1) * columnGap -
                Tokens.space32) /
            columns;
        final tileHeight = tileWidth / Tokens.posterAspect + kPosterTextHeight;

        return Stack(
          children: [
            GridView.builder(
              controller: _controller,
              physics: const SmoothScrollPhysics(),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              padding: const EdgeInsets.only(
                left: Tokens.space16,
                right: Tokens.space16,
                bottom: Tokens.space32,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: posterRowGap(constraints.maxWidth),
                crossAxisSpacing: columnGap,
                childAspectRatio: tileWidth / tileHeight,
              ),
              itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= widget.items.length) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final media = widget.items[index];
                return RevealOnScroll(
                  index: index,
                  revealKey: 'poster:${media.type.name}:${media.id}',
                  child: PosterCard(media: media),
                );
              },
            ),
            Positioned(
              right: 16,
              bottom: 24,
              child: BackToTopButton(
                visible: _showTop,
                onPressed: () {
                  if (_controller.hasClients) {
                    _controller.smoothTo(0);
                  }
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Horizontal rail used on the dashboard — glides with smooth physics,
/// arrow buttons, and edge fades on desktop.
///
/// Uses [ArrowRail] with a fixed `itemExtent` (148 + [Tokens.railGap])
/// so the viewport skips child measurement.
class MediaRailList extends StatelessWidget {
  const MediaRailList({required this.items, super.key});

  final List<Media> items;

  @override
  Widget build(BuildContext context) {
    return ArrowRail(
      height: 264,
      itemCount: items.length,
      separatorWidth: Tokens.railGap,
      // 148px card + the rail gap.
      itemExtent: 148 + Tokens.railGap,
      // No RevealOnScroll here: inside a virtualized horizontal viewport
      // recycled items would restart at opacity 0 + slide offset on every
      // fast fling, causing white flash and overlapping cards.
      itemBuilder: (context, index) => SizedBox(
        width: 148,
        child: RepaintBoundary(
          child: MediaRailCard(media: items[index]),
        ),
      ),
    );
  }
}

/// Sliver poster grid for use inside a parent [CustomScrollView].
///
/// Unlike [MediaGrid] (own `GridView` + own controller = nested scrollable),
/// this is a true sliver: one scrollable, no gesture fights, sticky headers
/// work, and overscroll/glow behave as a single surface.
///
/// [columnsForWidth] lets tests override the responsive breakpoints.
class SliverPosterGrid extends StatefulWidget {
  const SliverPosterGrid({
    required this.items,
    this.hasMore = false,
    this.compact = false,
    this.columnsForWidth = posterColumns,
    super.key,
  });

  final List<Media> items;
  final bool hasMore;

  /// Denser grid of smaller cards (same metrics as the browse pages).
  final bool compact;
  final int Function(double width) columnsForWidth;

  @override
  State<SliverPosterGrid> createState() => _SliverPosterGridState();
}

class _SliverPosterGridState extends State<SliverPosterGrid> {
  // A SliverLayoutBuilder runs its builder on every scroll frame (the sliver
  // constraints carry the scroll offset). Returning a freshly built grid each
  // time makes Flutter rebuild every visible tile on every frame, which is
  // what makes long grids lag. The grid only depends on the cross-axis
  // width and this widget's inputs, so it is built once per (width, inputs)
  // and the identical widget is handed back on every other frame.
  Widget? _cached;
  double _cachedWidth = -1;

  @override
  void didUpdateWidget(covariant SliverPosterGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cached = null;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final hasMore = widget.hasMore;
    final compact = widget.compact;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final cached = _cached;
        if (cached != null && _cachedWidth == width) return cached;
        final columns =
            compact ? browsePosterColumns(width) : widget.columnsForWidth(width);
        final columnGap =
            compact ? browseColumnGap(width) : posterColumnGap(width);
        final rowGap = compact ? kBrowseRowGap : posterRowGap(width);
        final textHeight = compact ? kBrowseTextHeight : kPosterTextHeight;
        final tileWidth =
            (width - (columns - 1) * columnGap - Tokens.space32) / columns;
        final tileHeight = tileWidth / Tokens.posterAspect + textHeight;
        final indexById = <String, int>{
          for (var i = 0; i < items.length; i++)
            '${items[i].type.name}:${items[i].id}': i,
        };
        final grid = SliverPadding(
          padding: const EdgeInsets.only(
            left: Tokens.space16,
            right: Tokens.space16,
            bottom: Tokens.space32,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: rowGap,
              crossAxisSpacing: columnGap,
              childAspectRatio: tileWidth / tileHeight,
            ),
            // No keep-alives for offscreen posters; repaint boundaries
            // isolate image repaints during hover/reveal.
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            itemCount: items.length + (hasMore ? 1 : 0),
            // Stable identity: appended pages (infinite scroll) and replaced
            // result sets reuse existing tiles instead of rebuilding them.
            findChildIndexCallback: (key) {
              if (key is! ValueKey<String>) return null;
              final i = indexById[key.value];
              return i;
            },
            itemBuilder: (context, index) {
              if (index >= items.length) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final media = items[index];
              return RevealOnScroll(
                key: ValueKey('${media.type.name}:${media.id}'),
                index: index,
                revealKey: 'poster:${media.type.name}:${media.id}',
                child: PosterCard(media: media, compact: compact),
              );
            },
          ),
        );
        _cachedWidth = width;
        _cached = grid;
        return grid;
      },
    );
  }
}

/// Sliver list of tracked entries for My Lists (single scrollable).
///
/// Takes an [itemBuilder] so `media_grid.dart` stays decoupled from the
/// `EntryRow` defined in `my_lists_screen.dart` (no import cycle).
class SliverEntryList extends StatelessWidget {
  const SliverEntryList({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: Tokens.space32),
      sliver: SliverList.builder(
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        itemCount: itemCount,
        itemBuilder: (context, index) => RevealOnScroll(
          index: index,
          child: itemBuilder(context, index),
        ),
      ),
    );
  }
}
