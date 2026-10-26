import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/history_entry.dart';
import '../../data/models/media.dart';
import '../../state/history_controller.dart';
import '../components/app_footer.dart';
import '../components/sliver_headers.dart';
import '../router/app_router.dart';

/// Titles the user opened recently, newest first.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This removes every title from your history. Your watchlist is not '
          'affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(historyControllerProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyControllerProvider);

    return CustomScrollView(
      physics: const SmoothScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            count: entries.length,
            onClear: entries.isEmpty ? null : () => _confirmClear(context, ref),
          ),
        ),
        if (entries.isEmpty)
          SliverEmpty(
            icon: Icons.history_rounded,
            title: 'No history yet',
            message: 'Anime and manga you open will show up here.',
            actionLabel: 'Browse anime',
            onAction: () => context.go(Routes.anime),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
            sliver: SliverList.separated(
              itemCount: entries.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: Tokens.space8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _HistoryTile(
                  key: ValueKey('${entry.type.name}-${entry.mediaId}'),
                  entry: entry,
                );
              },
            ),
          ),
        const SliverAppFooter(),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onClear});

  final int count;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        Tokens.space12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('History', style: theme.textTheme.headlineMedium),
                Text(
                  count == 0
                      ? 'Recently opened titles'
                      : '$count recent ${count == 1 ? 'title' : 'titles'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Clear all'),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends ConsumerWidget {
  const _HistoryTile({required this.entry, super.key});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = entry.coverUrl;

    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        entry.type == MediaType.manga
            ? Icons.menu_book_rounded
            : Icons.movie_rounded,
        color: scheme.onSurfaceVariant,
      ),
    );

    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.push(Routes.mediaDetail(entry.type, entry.mediaId)),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: SizedBox(
                  width: 48,
                  height: 68,
                  child: cover == null
                      ? placeholder
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stack) => placeholder,
                        ),
                ),
              ),
              const SizedBox(width: Tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Tokens.space4),
                    Text(
                      '${entry.type.label}, ${Formatters.timeAgo(entry.viewedAt)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove from history',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () =>
                    ref.read(historyControllerProvider.notifier).remove(entry),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
