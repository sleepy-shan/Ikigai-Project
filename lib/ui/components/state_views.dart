import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/theme/design_tokens.dart';
import '../../state/load_state.dart';

/// Renders loading / error / empty / success states for a [LoadState].
///
/// Every data-driven screen uses this so behaviour stays consistent.
/// State switches animate via [AnimatedSwitcher] (fade + slight slide)
/// so loading -> content does not pop.
class StateView<T> extends StatelessWidget {
  const StateView({
    required this.state,
    required this.builder,
    this.emptyMessage = 'Nothing to show yet.',
    this.emptyTitle,
    this.emptyIcon = Icons.inbox_outlined,
    this.onRetry,
    this.loading,
    super.key,
  });

  final LoadState<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final String emptyMessage;
  final String? emptyTitle;
  final IconData emptyIcon;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (state.status) {
      LoadStatus.initial || LoadStatus.loading =>
        loading ?? const Center(child: CircularProgressIndicator()),
      LoadStatus.error => ErrorView(
        message: state.errorMessage ?? 'Something went wrong.',
        onRetry: onRetry,
      ),
      LoadStatus.success when state.data == null => EmptyView(
        message: emptyMessage,
        title: emptyTitle,
        icon: emptyIcon,
      ),
      LoadStatus.success => builder(context, state.data as T),
    };
    return AnimatedSwitcher(
      duration: Tokens.durationMedium,
      switchInCurve: Tokens.curveSmooth,
      switchOutCurve: Tokens.curveSmooth,
      transitionBuilder: (inner, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(animation),
          child: inner,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey('${state.status}:${state.errorMessage ?? ''}'),
        child: child,
      ),
    );
  }
}

/// Error panel with a short explanation and a retry action.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 44,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: Tokens.space12),
              Text(
                'Something went wrong',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.space8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: Tokens.space16),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state panel with an optional call to action.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.title,
    super.key,
  });

  final String message;
  final IconData icon;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: Tokens.space12),
              Text(
                title ?? 'Nothing here yet',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Tokens.space8),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Tokens.space16),
                ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One shimmer sweep shared by every bone underneath it, tinted from the
/// active theme (neutral base, primary-tinted highlight) so it reads in light
/// and dark.
///
/// Built on `package:shimmer`: the shimmer paints its gradient through the
/// alpha of its child, so everything inside must be solid [SkeletonBone]s.
/// Wrap a whole grid or rail in a single [SkeletonShimmer] rather than one per
/// card — that keeps a single animation ticker per skeleton.
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Shimmer.fromColors(
      baseColor: theme.disabledColor.withValues(alpha: 0.14),
      highlightColor: theme.colorScheme.primary.withValues(alpha: 0.22),
      period: const Duration(milliseconds: 1400),
      enabled: enabled,
      child: child,
    );
  }
}

/// A solid rounded box. Placed under a [SkeletonShimmer] it becomes a
/// shimmering bone; [width] / [height] of null fill the available space.
class SkeletonBone extends StatelessWidget {
  const SkeletonBone({
    this.width,
    this.height,
    this.radius = Tokens.radiusMd,
    super.key,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A line of text as a bone: [fraction] of the available width, [height] tall.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({this.fraction = 1, this.height = 12, super.key});

  final double fraction;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: fraction,
      child: SkeletonBone(height: height, radius: 4),
    );
  }
}

/// Poster + two text lines, mirroring `PosterCard`'s layout.
class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: SkeletonBone(radius: Tokens.radiusLg)),
        SizedBox(height: Tokens.space12),
        SkeletonLine(height: 14),
        SizedBox(height: Tokens.space8),
        SkeletonLine(fraction: 0.45, height: 10),
      ],
    );
  }
}

/// Spotlight hero skeleton: one banner-sized block.
class LoadingHero extends StatelessWidget {
  const LoadingHero({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SkeletonShimmer(
        child: SkeletonBone(height: 260, radius: Tokens.radiusXl),
      ),
    );
  }
}

/// Horizontal rail skeleton: five poster cards.
class LoadingRail extends StatelessWidget {
  const LoadingRail({this.height = 252, this.itemWidth = 148, super.key});

  final double height;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
          itemCount: 5,
          separatorBuilder: (context, index) =>
              const SizedBox(width: Tokens.space12),
          itemBuilder: (context, index) =>
              SizedBox(width: itemWidth, child: const _PosterSkeleton()),
        ),
      ),
    );
  }
}

/// Skeleton for the home "Releasing today" strip. Mirrors the real episode
/// card exactly: a [coverHeight] cover, an 8px gap, a one-line title and a
/// one-line time row, at [itemWidth] with the rail's own padding and gap, so
/// the real cards replace it without any layout shift.
class LoadingAiringRail extends StatelessWidget {
  const LoadingAiringRail({
    required this.height,
    required this.itemWidth,
    required this.coverHeight,
    super.key,
  });

  final double height;
  final double itemWidth;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
          itemCount: 12,
          separatorBuilder: (context, index) =>
              const SizedBox(width: Tokens.railGap),
          itemBuilder: (context, index) => SizedBox(
            width: itemWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBone(height: coverHeight, radius: Tokens.radiusLg),
                const SizedBox(height: Tokens.space8),
                const SkeletonLine(height: 14),
                const SizedBox(height: 6),
                const SkeletonLine(fraction: 0.7, height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical list-row skeletons (My Lists / profile lists).
class LoadingListRows extends StatelessWidget {
  const LoadingListRows({this.count = 5, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Tokens.space32),
        itemCount: count,
        separatorBuilder: (context, index) =>
            const SizedBox(height: Tokens.space8),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
          child: Row(
            children: [
              const SkeletonBone(width: 52, height: 76),
              const SizedBox(width: Tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(fraction: 0.7, height: 16),
                    SizedBox(height: 8),
                    SkeletonLine(fraction: 0.45, height: 12),
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

/// Detail page skeleton: poster + title block, tracking card, text lines.
class LoadingDetail extends StatelessWidget {
  const LoadingDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(Tokens.space16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SkeletonBone(width: 132, height: 190),
              const SizedBox(width: Tokens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(fraction: 0.8, height: 24),
                    SizedBox(height: 12),
                    SkeletonLine(fraction: 0.5, height: 14),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space24),
          const SkeletonBone(height: 44),
          const SizedBox(height: Tokens.space12),
          const SkeletonLine(height: 14),
          const SizedBox(height: 8),
          const SkeletonLine(height: 14),
          const SizedBox(height: 8),
          const SkeletonLine(fraction: 0.6, height: 14),
        ],
      ),
    );
  }
}

/// Grid of poster skeletons used as the loading state for poster grids.
class LoadingPosterGrid extends StatelessWidget {
  const LoadingPosterGrid({this.columnsForWidth = posterColumns, super.key});

  /// Column count for a given width (browse uses a denser, smaller grid).
  final int Function(double width) columnsForWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsForWidth(constraints.maxWidth);
        final columnGap = posterColumnGap(constraints.maxWidth);
        final tileWidth =
            (constraints.maxWidth -
                (columns - 1) * columnGap -
                Tokens.space32) /
            columns;
        final tileHeight = tileWidth / Tokens.posterAspect + kPosterTextHeight;
        return SkeletonShimmer(
          child: GridView.builder(
            padding: const EdgeInsets.all(Tokens.space16),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: true,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: posterRowGap(constraints.maxWidth),
              crossAxisSpacing: columnGap,
              childAspectRatio: tileWidth / tileHeight,
            ),
            itemCount: columns * 2,
            itemBuilder: (context, index) => const _PosterSkeleton(),
          ),
        );
      },
    );
  }
}

/// Number of poster columns for a given width.
///
/// Breakpoints are intentionally a little wider than the minimum card size so
/// posters keep breathing room instead of being packed edge to edge.
int posterColumns(double width) {
  if (width >= 1800) return 7;
  if (width >= 1500) return 6;
  if (width >= 1200) return 5;
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  return 2;
}

/// Denser variant of [posterColumns] for the Anime/Manga browse pages: one
/// more column at every breakpoint, so each card is smaller.
int browsePosterColumns(double width) {
  if (width >= 1800) return 10;
  if (width >= 1500) return 9;
  if (width >= 1200) return 8;
  if (width >= 900) return 6;
  if (width >= 600) return 5;
  return 3;
}

/// Compact-card metrics for the browse grid.
double browseColumnGap(double width) => width >= 1080 ? 16 : 12;
const double kBrowseRowGap = 20;
const double kBrowseTextHeight = 42;

/// Skeleton for one compact browse card (poster + title + subtitle).
class CompactPosterSkeleton extends StatelessWidget {
  const CompactPosterSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: SkeletonBone(radius: Tokens.radiusMd)),
        SizedBox(height: Tokens.space8),
        SkeletonLine(height: 12),
        SizedBox(height: 4),
        SkeletonLine(fraction: 0.5, height: 9),
      ],
    );
  }
}

/// Shimmering skeleton page for the browse grid (shimmer).
class BrowseSkeletonGrid extends StatelessWidget {
  const BrowseSkeletonGrid({this.count = 24, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = browsePosterColumns(width);
        final gap = browseColumnGap(width);
        final tileWidth =
            (width - (columns - 1) * gap - Tokens.space32) / columns;
        final tileHeight = tileWidth / Tokens.posterAspect + kBrowseTextHeight;
        return SkeletonShimmer(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            addAutomaticKeepAlives: false,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: kBrowseRowGap,
              crossAxisSpacing: gap,
              childAspectRatio: tileWidth / tileHeight,
            ),
            itemCount: count,
            itemBuilder: (context, index) => const CompactPosterSkeleton(),
          ),
        );
      },
    );
  }
}

/// Horizontal gap between poster columns; grows with the viewport.
double posterColumnGap(double width) {
  if (width >= 1080) return Tokens.space24;
  if (width >= 600) return Tokens.space20;
  return Tokens.space16;
}

/// Vertical gap between poster rows. Larger than the column gap because every
/// poster carries a two-line title + subtitle underneath it.
double posterRowGap(double width) {
  if (width >= 1080) return 40;
  if (width >= 840) return 36;
  if (width >= 600) return 32;
  return 28;
}

/// Height reserved under each poster for its title and subtitle text.
const double kPosterTextHeight = 68;
