import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/account.dart';
import '../router/app_router.dart';

/// Icon + colour used for a [ProfileSection] row.
///
/// Colours mirror the AniList status hues (see [Tokens.statusWatching] etc.)
/// so the strip reads like AniList's own statistics panel.
({IconData icon, Color color}) _visualFor(
  ProfileSection section,
  ColorScheme scheme,
) => switch (section) {
  ProfileSection.all => (
    icon: Icons.collections_bookmark_rounded,
    color: scheme.primary,
  ),
  ProfileSection.watching => (
    icon: Icons.play_circle_fill_rounded,
    color: Tokens.statusWatching,
  ),
  ProfileSection.completed => (
    icon: Icons.check_circle_rounded,
    color: Tokens.statusCompleted,
  ),
  ProfileSection.planning => (
    icon: Icons.calendar_month_rounded,
    color: Tokens.statusPlanning,
  ),
  ProfileSection.paused => (
    icon: Icons.pause_circle_filled_rounded,
    color: Tokens.statusPaused,
  ),
  ProfileSection.dropped => (
    icon: Icons.cancel_rounded,
    color: Tokens.statusDropped,
  ),
  ProfileSection.rewatching => (
    icon: Icons.replay_circle_filled_rounded,
    color: Tokens.statusRewatching,
  ),
  ProfileSection.favourites => (
    icon: Icons.favorite_rounded,
    color: Tokens.statusFavourite,
  ),
};

/// Card listing every [ProfileSection] with its logo and count.
///
/// Each row is tappable and opens that section of the user's AniList list
/// (`/profile/list/<section>`). Uses one column on phones and two from tablet
/// width up so the list stays readable without stretching rows edge to edge.
class ProfileStatsPanel extends StatelessWidget {
  const ProfileStatsPanel({required this.profile, super.key});

  final ViewerProfile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, size: 18, color: scheme.primary),
                const SizedBox(width: Tokens.space8),
                Text(
                  'Anime list',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  'Tap to browse',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Tokens.space12),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = Tokens.space12;
                final columns = constraints.maxWidth >= 560 ? 2 : 1;
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: Tokens.space4,
                  children: [
                    for (final section in ProfileSection.values)
                      SizedBox(
                        width: itemWidth,
                        child: _StatRow(
                          section: section,
                          count: section.countIn(profile),
                        ),
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

class _StatRow extends StatelessWidget {
  const _StatRow({required this.section, required this.count});

  final ProfileSection section;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visual = _visualFor(section, scheme);
    // Light mode: saturated hues (esp. paused yellow) read poorly on a tinted
    // chip, so darken for contrast. Dark mode keeps the vivid hue. The
    // theme-primary "All" row already contrasts, so it is left alone.
    final isDark = theme.brightness == Brightness.dark;
    final base = visual.color;
    final color = (isDark || section == ProfileSection.all)
        ? base
        : HSLColor.fromColor(base)
              .withLightness(
                (HSLColor.fromColor(base).lightness - 0.18).clamp(0.0, 1.0),
              )
              .toColor();

    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusMd),
      onTap: () => context.go(Routes.profileList(section)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Tokens.space4,
          horizontal: Tokens.space4,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Icon(visual.icon, size: 18, color: color),
            ),
            const SizedBox(width: Tokens.space12),
            Expanded(
              child: Text(
                section.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: Tokens.space8),
            Text(
              '$count',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
