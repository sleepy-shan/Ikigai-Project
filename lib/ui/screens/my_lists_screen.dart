import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_motion.dart';
import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../data/models/media_entry.dart';
import '../../state/load_state.dart';
import '../../state/my_lists_controller.dart';
import '../components/media_grid.dart';
import '../components/app_footer.dart';
import '../components/sliver_headers.dart';
import '../components/status_badge.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

/// The user's personal list: filter by status, sort, and edit progress.
///
/// Single-scrollable sliver version: header scrolls away, filter chips
/// stick (`SliverPersistentHeader`), entries are a `SliverList` — one
/// scrollable, no `Column + Expanded + ListView` nesting.
class MyListsScreen extends ConsumerStatefulWidget {
  const MyListsScreen({super.key});

  @override
  ConsumerState<MyListsScreen> createState() => _MyListsScreenState();
}

class _MyListsScreenState extends ConsumerState<MyListsScreen> {
  late final ScrollController _controller;
  bool _showTop = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final show = _controller.offset > 700;
    if (show != _showTop && mounted) setState(() => _showTop = show);
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
    final status = ref.watch(myListsControllerProvider.select((s) => s.status));

    return Stack(
      children: [
        CustomScrollView(
          controller: _controller,
          physics: const SmoothScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            SliverPersistentHeader(
              pinned: true,
              delegate: StickyHeaderDelegate(
                height: 56,
                child: const _FilterChips(),
              ),
            ),
            switch (status) {
              LoadStatus.loading || LoadStatus.initial =>
                const SliverToBoxAdapter(child: LoadingListRows(count: 5)),
              LoadStatus.error => const _ErrorSlivers(),
              LoadStatus.success => const _BodySlivers(),
            },
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
}

class _ErrorSlivers extends ConsumerWidget {
  const _ErrorSlivers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      myListsControllerProvider.select(
        (s) => s.errorMessage ?? 'Could not load your list.',
      ),
    );
    final controller = ref.read(myListsControllerProvider.notifier);
    return SliverError(message: message, onRetry: controller.refresh);
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final total = ref.watch(
      myListsControllerProvider.select((s) => s.entries.length),
    );
    final sort = ref.watch(myListsControllerProvider.select((s) => s.sort));
    final controller = ref.read(myListsControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        Tokens.space8,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My List', style: theme.textTheme.headlineMedium),
                AnimatedSwitcher(
                  duration: Tokens.durationMedium,
                  child: Text(
                    '$total tracked ${total == 1 ? 'title' : 'titles'}',
                    key: ValueKey(total),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: DropdownButton<ListsSort>(
              value: sort,
              isExpanded: true,
              borderRadius: BorderRadius.circular(Tokens.radiusSm),
              underline: const SizedBox.shrink(),
              items: [
                for (final s in ListsSort.values)
                  DropdownMenuItem(
                    value: s,
                    child: Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (s) {
                if (s != null) controller.setSort(s);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(
      myListsControllerProvider.select((s) => s.filter),
    );
    final counts = ref.watch(myListsCountsProvider);
    final controller = ref.read(myListsControllerProvider.notifier);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space16,
        vertical: Tokens.space8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: Tokens.space8,
          children: [
            for (final f in ListsFilter.values)
              ChoiceChip(
                label: AnimatedSwitcher(
                  duration: Tokens.durationFast,
                  child: Text(
                    '${f.label} (${counts[f] ?? 0})',
                    key: ValueKey('${f.name}:${counts[f] ?? 0}'),
                  ),
                ),
                selected: filter == f,
                onSelected: (_) => controller.setFilter(f),
              ),
          ],
        ),
      ),
    );
  }
}

class _BodySlivers extends ConsumerWidget {
  const _BodySlivers();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(visibleEntriesProvider);
    final filter = ref.watch(
      myListsControllerProvider.select((s) => s.filter),
    );
    final controller = ref.read(myListsControllerProvider.notifier);
    if (entries.isEmpty) {
      return filter == ListsFilter.all
          ? SliverEmpty(
              icon: Icons.format_list_bulleted_outlined,
              title: 'Your list is empty',
              message:
                  'Browse anime or manga and tap "Add to my list" '
                  'to start tracking progress.',
              actionLabel: 'Browse anime',
              onAction: () => context.go(Routes.anime),
            )
          : SliverEmpty(
              icon: Icons.filter_alt_off_outlined,
              title: 'Nothing in this status',
              message: 'No titles have this status right now.',
              actionLabel: 'Show all titles',
              onAction: () => controller.setFilter(ListsFilter.all),
            );
    }
    return SliverEntryList(
      itemCount: entries.length,
      itemBuilder: (context, index) => EntryRow(entry: entries[index]),
    );
  }
}

/// Entry rows with progress steppers and a status menu.
class EntryRow extends ConsumerWidget {
  const EntryRow({required this.entry, super.key});

  final MediaEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = ref.read(myListsControllerProvider.notifier);
    final fraction = entry.fraction;

    return RepaintBoundary(
      child: Card(
        margin: const EdgeInsets.symmetric(
          horizontal: Tokens.space16,
          vertical: Tokens.space8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: entry.coverUrl == null || entry.coverUrl!.isEmpty
                    ? Container(
                        width: 52,
                        height: 76,
                        color: theme.disabledColor.withValues(alpha: 0.15),
                      )
                    : Image.network(
                        entry.coverUrl!,
                        width: 52,
                        height: 76,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stack) => Container(
                          width: 52,
                          height: 76,
                          color: theme.disabledColor.withValues(alpha: 0.15),
                        ),
                      ),
              ),
              const SizedBox(width: Tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () => context.go(
                        Routes.mediaDetail(entry.type, entry.mediaId),
                      ),
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: Tokens.space4),
                    // Wrap so badge + counters never clip on 320px rows.
                    Wrap(
                      spacing: Tokens.space8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(status: entry.status, type: entry.type),
                        Text(
                          '${entry.progress}'
                          '${entry.totalUnits != null ? '/${entry.totalUnits}' : ''}'
                          ' ${entry.unit}s',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (entry.score != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Tokens.warning,
                              ),
                              Text(
                                '${entry.score}/10',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (fraction != null) ...[
                      const SizedBox(height: Tokens.space8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(
                          Tokens.radiusPill,
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: fraction),
                          duration: Tokens.durationMedium,
                          curve: Tokens.curveSmooth,
                          builder: (context, value, _) =>
                              LinearProgressIndicator(
                            value: value,
                            minHeight: 4,
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
              ),
              IconButton.filledTonal(
                tooltip: 'Mark one more ${entry.unit}',
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => controller.incrementProgress(entry.mediaId),
              ),
              PopupMenuButton<String>(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) async {
                  switch (value) {
                    case 'remove':
                      await _confirmRemove(context, controller, entry);
                    case 'restart':
                      await controller.setProgress(entry.mediaId, 0);
                    case 'complete':
                      await controller.setStatus(
                        entry.mediaId,
                        ListStatus.completed,
                      );
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'restart',
                    child: Text('Reset progress'),
                  ),
                  PopupMenuItem(
                    value: 'complete',
                    child: Text('Mark completed'),
                  ),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    MyListsController controller,
    MediaEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from list?'),
        content: Text('"${entry.title}" will no longer be tracked.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.remove(entry.mediaId);
    }
  }
}

/// List body rendered as scrollable rows (kept for tests/embedders).
///
/// The screen itself uses [SliverEntryList] inside its `CustomScrollView`.
class MyListBody extends StatelessWidget {
  const MyListBody({required this.entries, super.key});

  final List<MediaEntry> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Tokens.space32),
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: entries.length,
      itemBuilder: (context, index) => RevealOnScroll(
        index: index,
        child: EntryRow(entry: entries[index]),
      ),
    );
  }
}

class EmptyFilter extends StatelessWidget {
  const EmptyFilter({required this.onClear, super.key});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.filter_alt_off_outlined,
      title: 'Nothing in this status',
      message: 'No titles have this status right now.',
      actionLabel: 'Show all titles',
      onAction: onClear,
    );
  }
}
