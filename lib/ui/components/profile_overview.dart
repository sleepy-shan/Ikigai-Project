import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/account.dart';
import '../../data/models/media.dart';
import '../../state/media_providers.dart';
import '../router/app_router.dart';

/// Overview metrics derived from the signed-in user's AniList statistics:
/// totals, units watched/read, time spent and mean scores.
class ProfileOverviewPanel extends StatelessWidget {
  const ProfileOverviewPanel({required this.profile, super.key});

  final ViewerProfile? profile;

  static String _count(int? value) => value == null ? '—' : '$value';

  static String _days(double? value) =>
      value == null ? '—' : value.toStringAsFixed(1);

  static String _score(double? value) =>
      value == null || value <= 0 ? '—' : value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final metrics = <_Metric>[
      _Metric(
        Icons.collections_bookmark_rounded,
        'Total anime',
        _count(profile?.totalCount),
      ),
      _Metric(
        Icons.play_circle_outline_rounded,
        'Episodes watched',
        _count(profile?.episodesWatched),
      ),
      _Metric(
        Icons.schedule_rounded,
        'Days watched',
        _days(profile?.daysWatched),
      ),
      _Metric(
        Icons.star_border_rounded,
        'Mean score',
        _score(profile?.meanScore),
      ),
      _Metric(
        Icons.menu_book_rounded,
        'Total manga',
        _count(profile?.mangaCount),
      ),
      _Metric(
        Icons.auto_stories_rounded,
        'Chapters read',
        _count(profile?.chaptersRead),
      ),
      _Metric(
        Icons.library_books_rounded,
        'Volumes read',
        _count(profile?.volumesRead),
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.query_stats_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: Tokens.space8),
                Text(
                  'Statistics',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space12),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = Tokens.space12;
                final columns = constraints.maxWidth >= 760
                    ? 4
                    : constraints.maxWidth >= 460
                    ? 3
                    : 2;
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: itemWidth,
                        child: _MetricTile(metric: metric),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space12,
        vertical: Tokens.space12,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(metric.icon, size: 18, color: scheme.primary),
          const SizedBox(height: Tokens.space8),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Top genres across the user's anime and manga lists, drawn as a bar list.
class ProfileGenresPanel extends StatelessWidget {
  const ProfileGenresPanel({required this.profile, super.key});

  final ViewerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final genres = (profile?.topGenres ?? const <GenreStat>[])
        .take(8)
        .toList(growable: false);
    if (genres.isEmpty) return const SizedBox.shrink();
    final max = genres.first.count;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.category_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: Tokens.space8),
                Text(
                  'Genre overview',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space12),
            for (final stat in genres)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Tokens.space4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        stat.genre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: Tokens.space12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Tokens.radiusPill),
                        child: LinearProgressIndicator(
                          value: max <= 0 ? 0.0 : stat.count / max,
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(scheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: Tokens.space12),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${stat.count}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Recent AniList activity: list progress, status changes, posts, messages.
class ProfileActivityPanel extends ConsumerWidget {
  const ProfileActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final feed = ref.watch(activityProvider);
    final items = feed.value ?? const <UserActivity>[];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: Tokens.space8),
                Text(
                  'Activity history',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space12),
            if (feed.isLoading && items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Tokens.space12),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Tokens.space4),
                child: Text(
                  'No recent activity on your AniList account yet.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final activity in items.take(8))
                _ActivityRow(activity: activity),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});

  final UserActivity activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mediaId = activity.mediaId;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Tokens.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Icon(
              _activityIcon(activity),
              size: 16,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: Tokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _describeActivity(activity),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Tokens.space2),
                Text(
                  _ago(activity.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (mediaId == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusSm),
      onTap: () => context.go(
        Routes.mediaDetail(activity.mediaType ?? MediaType.anime, mediaId),
      ),
      child: row,
    );
  }
}

IconData _activityIcon(UserActivity activity) => switch (activity.status) {
  'COMPLETED' => Icons.check_circle_rounded,
  'PLANNING' => Icons.calendar_month_rounded,
  'PAUSED' => Icons.pause_circle_filled_rounded,
  'DROPPED' => Icons.cancel_rounded,
  'REPEATING' => Icons.replay_circle_filled_rounded,
  'CURRENT' => Icons.play_circle_fill_rounded,
  _ => activity.kind == ActivityKind.listUpdate
      ? Icons.edit_note_rounded
      : Icons.chat_bubble_outline_rounded,
};

/// One human sentence for an activity entry.
String _describeActivity(UserActivity activity) {
  if (activity.kind != ActivityKind.listUpdate) {
    final text = activity.text;
    if (text != null && text.isNotEmpty) return text;
    return activity.kind == ActivityKind.message
        ? 'Sent a message'
        : 'Posted an update';
  }
  final title = activity.title ?? 'a title';
  final isManga = activity.mediaType == MediaType.manga;
  final unit = isManga ? 'chapter' : 'episode';
  final verb = isManga ? 'Read' : 'Watched';
  final startVerb = isManga ? 'reading' : 'watching';
  final progress = activity.progress ?? 0;
  return switch (activity.status) {
    'CURRENT' => progress > 0
        ? '$verb $unit $progress of $title'
        : 'Started $startVerb $title',
    'REPEATING' => progress > 0
        ? '${isManga ? 'Reread' : 'Rewatched'} $unit $progress of $title'
        : 'Started re$startVerb $title',
    'COMPLETED' => 'Completed $title',
    'PLANNING' => isManga ? 'Plans to read $title' : 'Plans to watch $title',
    'PAUSED' => 'Paused $title',
    'DROPPED' => 'Dropped $title',
    _ => progress > 0 ? '$verb $unit $progress of $title' : title,
  };
}

/// Compact preview of the newest AniList notifications, with a link to the
/// full Notifications screen. Hidden entirely while empty/loading so it never
/// competes with the statistics.
class ProfileNotificationsPanel extends ConsumerWidget {
  const ProfileNotificationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items =
        ref.watch(notificationsProvider).value ??
        const <UserNotification>[];
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: Tokens.space8),
                Text(
                  'Notifications',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go(Routes.notifications),
                  child: const Text('View all'),
                ),
              ],
            ),
            for (final item in items.take(3))
              InkWell(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                onTap: () => context.go(
                  Routes.mediaDetail(item.mediaType, item.mediaId),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: Tokens.space8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.play_circle_outline_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: Tokens.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${item.message} · ${_ago(item.createdAt)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact relative time ("3h ago") for the activity and notification rows.
String _ago(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}
