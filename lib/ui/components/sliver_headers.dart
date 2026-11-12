import 'package:material_ui/material_ui.dart';

import '../../core/theme/design_tokens.dart';

/// Pinned/sticky header delegate for filter chips, week controls, etc.
///
/// Used with `SliverPersistentHeader(pinned: true)` so the toolbar sticks
/// while the grid scrolls underneath — one scrollable, no nested columns.
class StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  StickyHeaderDelegate({
    required this.child,
    required this.height,
  });

  final Widget child;
  final double height;

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
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant StickyHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

/// Sliver loading / error / empty states that fill remaining viewport.
///
/// Use inside `CustomScrollView` where `StateView` (box-based) does not fit.
class SliverLoading extends StatelessWidget {
  const SliverLoading({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class SliverError extends StatelessWidget {
  const SliverError({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
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
                const SizedBox(height: Tokens.space16),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SliverEmpty extends StatelessWidget {
  const SliverEmpty({
    required this.message,
    this.title,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? title;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 44,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                  ElevatedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
