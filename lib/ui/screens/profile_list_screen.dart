import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/app_exception.dart';
import '../../data/models/account.dart';
import '../../data/models/media.dart';
import '../../state/media_providers.dart';
import '../components/app_footer.dart';
import '../components/media_grid.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

/// One section of the signed-in user's AniList anime list, with a grid/list
/// switch. Read-only: tapping a title opens its detail page.
class ProfileListScreen extends ConsumerStatefulWidget {
  const ProfileListScreen({required this.section, super.key});

  final ProfileSection section;

  @override
  ConsumerState<ProfileListScreen> createState() => _ProfileListScreenState();
}

class _ProfileListScreenState extends ConsumerState<ProfileListScreen> {
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final list = ref.watch(accountListProvider(section));

    return CustomScrollView(
      physics: const SmoothScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _ListHeader(
            section: section,
            count: list.value?.length,
            grid: _grid,
            onToggle: (value) => setState(() => _grid = value),
          ),
        ),
        ...list.when<List<Widget>>(
          loading: () => [
            SliverToBoxAdapter(
              child: _grid
                  ? const LoadingPosterGrid()
                  : const LoadingListRows(count: 6),
            ),
          ],
          error: (error, stack) => [
            SliverError(
              message: error is AppException
                  ? error.userMessage
                  : 'Could not load this list. Please try again.',
              onRetry: () => ref.invalidate(accountListProvider(section)),
            ),
          ],
          data: (entries) {
            if (entries.isEmpty) {
              return [
                SliverEmpty(
                  icon: Icons.inbox_outlined,
                  title: 'Nothing in ${section.label}',
                  message: 'This section of your AniList list is empty.',
                  actionLabel: 'Back to profile',
                  onAction: () => context.go(Routes.profile),
                ),
              ];
            }
            if (_grid) {
              return [
                SliverPosterGrid(
                  items: [for (final entry in entries) entry.media],
                ),
              ];
            }
            return [
              SliverPadding(
                padding: const EdgeInsets.only(bottom: Tokens.space32),
                sliver: SliverList.builder(
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _AccountEntryRow(
                    entry: entries[index],
                    showMeta: !section.favouritesOnly,
                    showStatus: section == ProfileSection.all,
                  ),
                ),
              ),
            ];
          },
        ),
        const SliverAppFooter(),
      ],
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.section,
    required this.count,
    required this.grid,
    required this.onToggle,
  });

  final ProfileSection section;
  final int? count;
  final bool grid;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space8,
        Tokens.space20,
        Tokens.space16,
        Tokens.space8,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to profile',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go(Routes.profile),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium,
                ),
                Text(
                  count == null
                      ? 'From your AniList account'
                      : '$count ${count == 1 ? 'title' : 'titles'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Grid',
                  visualDensity: VisualDensity.compact,
                  isSelected: grid,
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  selectedIcon: const Icon(Icons.grid_view_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: grid
                        ? scheme.primary.withValues(alpha: 0.16)
                        : Colors.transparent,
                    foregroundColor: grid ? scheme.primary : null,
                  ),
                  onPressed: () => onToggle(true),
                ),
                IconButton(
                  tooltip: 'List',
                  visualDensity: VisualDensity.compact,
                  isSelected: !grid,
                  icon: const Icon(Icons.view_list_rounded, size: 18),
                  selectedIcon: const Icon(Icons.view_list_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: !grid
                        ? scheme.primary.withValues(alpha: 0.16)
                        : Colors.transparent,
                    foregroundColor: !grid ? scheme.primary : null,
                  ),
                  onPressed: () => onToggle(false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only row for one AniList list entry: poster, title, status, progress.
class _AccountEntryRow extends StatelessWidget {
  const _AccountEntryRow({
    required this.entry,
    required this.showMeta,
    required this.showStatus,
  });

  final AccountListEntry entry;

  /// False for favourites, which have no progress to show.
  final bool showMeta;

  /// True for "All", where the mixed statuses are worth labelling.
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = entry.media;
    final chip = showStatus ? _statusVisual(entry.status, media.type) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space16,
        vertical: Tokens.space8,
      ),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => context.go(Routes.mediaDetail(media.type, media.id)),
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusSm),
                  child: media.coverUrl.isEmpty
                      ? Container(
                          width: 56,
                          height: 82,
                          color: theme.disabledColor.withValues(alpha: 0.15),
                        )
                      : Image.network(
                          media.coverUrl,
                          width: 56,
                          height: 82,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stack) => Container(
                            width: 56,
                            height: 82,
                            color: theme.disabledColor.withValues(alpha: 0.15),
                          ),
                        ),
                ),
                const SizedBox(width: Tokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (showMeta || chip != null) ...[
                        const SizedBox(height: Tokens.space4),
                        Wrap(
                          spacing: Tokens.space8,
                          runSpacing: Tokens.space4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (chip != null)
                              _StatusChip(label: chip.label, color: chip.color),
                            if (showMeta) _Progress(entry: entry),
                            if (entry.scoreLabel != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!entry.scoreFormat.usesSmileys)
                                    const Icon(
                                      Icons.star_rounded,
                                      size: 14,
                                      color: Tokens.warning,
                                    ),
                                  Text(
                                    entry.scoreLabel!,
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.entry});

  final AccountListEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entry.media.totalUnits;
    final unit = entry.media.type.unitPlural;
    final label = total != null
        ? '${entry.progress}/$total $unit'
        : '${entry.progress} $unit';
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolved = isDark
        ? color
        : HSLColor.fromColor(color)
              .withLightness(
                (HSLColor.fromColor(color).lightness - 0.18).clamp(0.0, 1.0),
              )
              .toColor();
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: resolved.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: resolved,
        ),
      ),
    );
  }
}

/// Label and colour for an AniList `MediaListStatus` wire value.
({String label, Color color})? _statusVisual(String wire, MediaType type) =>
    switch (wire) {
      'CURRENT' => (label: type.trackingVerb, color: Tokens.statusWatching),
      'COMPLETED' => (label: 'Completed', color: Tokens.statusCompleted),
      'PLANNING' => (label: 'Planning', color: Tokens.statusPlanning),
      'PAUSED' => (label: 'Paused', color: Tokens.statusPaused),
      'DROPPED' => (label: 'Dropped', color: Tokens.statusDropped),
      'REPEATING' => (
        label: type == MediaType.manga ? 'Rereading' : 'Rewatching',
        color: Tokens.statusRewatching,
      ),
      _ => null,
    };
