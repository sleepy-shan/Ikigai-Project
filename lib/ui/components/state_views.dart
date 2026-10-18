import 'package:flutter/material.dart';

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

/// Shimmer placeholder tile shown while content loads.
///
/// Static grey tiles feel frozen; this pulses opacity with a single shared
/// ticker owned by [LoadingPosterGrid] (passed as [pulse]) so a 14-tile
/// grid costs one [AnimationController], not fourteen.
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({this.height = 200, this.pulse, super.key});

  final double height;

  /// 0..1 shimmer phase. When null, renders a static placeholder.
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.disabledColor.withValues(alpha: 0.12);
    final tile = Container(
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
    );
    final animation = pulse;
    if (animation == null) return tile;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return Opacity(
          opacity: 0.55 + 0.45 * t,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base,
                  theme.colorScheme.primary.withValues(
                    alpha: 0.10 + 0.10 * t,
                  ),
                  base,
                ],
              ),
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
            ),
          ),
        );
      },
    );
  }
}

/// Shimmer text line for skeleton cards (title / subtitle placeholders).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    this.width = double.infinity,
    this.height = 12,
    this.pulse,
    super.key,
  });

  final double width;
  final double height;
  final Animation<double>? pulse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.disabledColor.withValues(alpha: 0.12);
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
    );
    final animation = pulse;
    if (animation == null) return box;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Opacity(
        opacity: 0.55 + 0.45 * animation.value,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                base,
                theme.colorScheme.primary.withValues(
                  alpha: 0.10 + 0.10 * animation.value,
                ),
                base,
              ],
            ),
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
          ),
        ),
      ),
    );
  }
}

/// Spotlight hero skeleton: banner block + poster + title lines.
class LoadingHero extends StatelessWidget {
  const LoadingHero({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.disabledColor.withValues(alpha: 0.10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.radiusXl),
        child: Container(
          height: 260,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                base,
                theme.colorScheme.primary.withValues(alpha: 0.08),
                base,
              ],
            ),
          ),
          child: const _PulseHeroContent(),
        ),
      ),
    );
  }
}

class _PulseHeroContent extends StatefulWidget {
  const _PulseHeroContent();

  @override
  State<_PulseHeroContent> createState() => _PulseHeroContentState();
}

class _PulseHeroContentState extends State<_PulseHeroContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        opacity: 0.6 + 0.4 * _controller.value,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 150,
                height: 215,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).disabledColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: 180, height: 14, pulse: _controller),
                    const SizedBox(height: 8),
                    SkeletonLine(width: 260, height: 26, pulse: _controller),
                    const SizedBox(height: 8),
                    SkeletonLine(width: 200, height: 12, pulse: _controller),
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

/// Horizontal rail skeleton driven by a single shared ticker.
class LoadingRail extends StatefulWidget {
  const LoadingRail({this.height = 252, this.itemWidth = 148, super.key});

  final double height;
  final double itemWidth;

  @override
  State<LoadingRail> createState() => _LoadingRailState();
}

class _LoadingRailState extends State<LoadingRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
        itemCount: 5,
        separatorBuilder: (context, index) =>
            const SizedBox(width: Tokens.space12),
        itemBuilder: (context, index) {
          final phase = (index / 5).clamp(0.0, 1.0);
          final curved = CurvedAnimation(
            parent: _controller,
            curve: Interval(phase * 0.5, 0.5 + phase * 0.5),
          );
          return SizedBox(
            width: widget.itemWidth,
            child: SkeletonTile(height: widget.height, pulse: curved),
          );
        },
      ),
    );
  }
}

/// Vertical list-row skeletons (My Lists / calendar) with one ticker.
class LoadingListRows extends StatefulWidget {
  const LoadingListRows({this.count = 5, super.key});

  final int count;

  @override
  State<LoadingListRows> createState() => _LoadingListRowsState();
}

class _LoadingListRowsState extends State<LoadingListRows>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: Tokens.space32),
      itemCount: widget.count,
      separatorBuilder: (context, index) =>
          const SizedBox(height: Tokens.space8),
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: SkeletonTile(height: 76, pulse: _controller),
            ),
            const SizedBox(width: Tokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: 180, pulse: _controller),
                  const SizedBox(height: 6),
                  SkeletonLine(width: 120, pulse: _controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detail page skeleton: title row + tracking card + text lines.
class LoadingDetail extends StatefulWidget {
  const LoadingDetail({super.key});

  @override
  State<LoadingDetail> createState() => _LoadingDetailState();
}

class _LoadingDetailState extends State<LoadingDetail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(Tokens.space16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 132,
              child: SkeletonTile(height: 190, pulse: _controller),
            ),
            const SizedBox(width: Tokens.space16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(width: 200, height: 22, pulse: _controller),
                  const SizedBox(height: 8),
                  SkeletonLine(width: 140, pulse: _controller),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Tokens.space24),
        SkeletonLine(width: double.infinity, height: 44, pulse: _controller),
        const SizedBox(height: Tokens.space12),
        SkeletonLine(width: double.infinity, height: 12, pulse: _controller),
        const SizedBox(height: 6),
        SkeletonLine(width: 260, pulse: _controller),
      ],
    );
  }
}

/// Grid of shimmer tiles used as the loading state for poster grids.
///
/// Owns a single repeating [AnimationController] that drives every tile
/// with a phase offset — efficient and visibly alive.
class LoadingPosterGrid extends StatefulWidget {
  const LoadingPosterGrid({super.key});

  @override
  State<LoadingPosterGrid> createState() => _LoadingPosterGridState();
}

class _LoadingPosterGridState extends State<LoadingPosterGrid>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
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
        return GridView.builder(
          padding: const EdgeInsets.all(Tokens.space16),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          // Static grid: no need for keep-alives; repaint boundaries keep
          // the shimmer cheap.
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: posterRowGap(constraints.maxWidth),
            crossAxisSpacing: columnGap,
            childAspectRatio: tileWidth / tileHeight,
          ),
          itemCount: columns * 2,
          itemBuilder: (context, index) {
            // Phase-shift each tile so the shimmer cascades.
            final phase = ((index % columns) / columns).clamp(0.0, 1.0);
            final curved = CurvedAnimation(
              parent: _controller,
              curve: Interval(phase * 0.5, 0.5 + phase * 0.5),
            );
            return SkeletonTile(height: 240, pulse: curved);
          },
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
