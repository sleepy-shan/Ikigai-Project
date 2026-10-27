import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

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

/// Shimmer used by every skeleton in the app, tinted from the active theme
/// (neutral base, primary-tinted highlight) so it reads in light and dark.
PaintingEffect skeletonEffect(BuildContext context) {
  final theme = Theme.of(context);
  return ShimmerEffect(
    baseColor: theme.disabledColor.withValues(alpha: 0.14),
    highlightColor: theme.colorScheme.primary.withValues(alpha: 0.22),
    duration: const Duration(milliseconds: 1400),
  );
}

/// Wraps a placeholder layout in an always-on [Skeletonizer].
///
/// The layouts below are ordinary widgets filled with dummy text; Skeletonizer
/// turns every text run and decorated box into a shimmering bone, so the
/// skeleton always matches the real card's proportions.
class _SkeletonScope extends StatelessWidget {
  const _SkeletonScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      effect: skeletonEffect(context),
      child: child,
    );
  }
}

/// A rounded box that Skeletonizer paints as a bone.
class _BoneBox extends StatelessWidget {
  const _BoneBox({this.width, this.height, this.radius = Tokens.radiusMd});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Poster + two text lines, mirroring `PosterCard`'s layout.
class _PosterSkeleton extends StatelessWidget {
  const _PosterSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: _BoneBox(radius: Tokens.radiusLg)),
        const SizedBox(height: Tokens.space12),
        Text(
          'Placeholder series title',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: Tokens.space4),
        Text('TV • 2024', maxLines: 1, style: theme.textTheme.labelSmall),
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
      child: _SkeletonScope(
        child: _BoneBox(height: 260, radius: Tokens.radiusXl),
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
    return _SkeletonScope(
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

/// Vertical list-row skeletons (My Lists / profile lists).
class LoadingListRows extends StatelessWidget {
  const LoadingListRows({this.count = 5, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SkeletonScope(
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
              const _BoneBox(width: 52, height: 76),
              const SizedBox(width: Tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Placeholder series title here',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Watching • 4 / 12 episodes',
                      style: theme.textTheme.bodySmall,
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

/// Detail page skeleton: poster + title block, tracking card, text lines.
class LoadingDetail extends StatelessWidget {
  const LoadingDetail({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SkeletonScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: const EdgeInsets.all(Tokens.space16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const _BoneBox(width: 132, height: 190),
              const SizedBox(width: Tokens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Placeholder series title',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text('TV • 2024 • Finished', style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space24),
          const _BoneBox(height: 44),
          const SizedBox(height: Tokens.space12),
          Text(
            'Placeholder synopsis line one that runs the full width of the '
            'page and wraps onto a second line, then a third line follows '
            'it so the block reads like a real paragraph of text.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// Grid of poster skeletons used as the loading state for poster grids.
class LoadingPosterGrid extends StatelessWidget {
  const LoadingPosterGrid({super.key});

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
        return _SkeletonScope(
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
