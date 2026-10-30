import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/airing_schedule.dart';
import '../../data/models/media.dart';
import '../../state/calendar_controller.dart';
import '../../state/load_state.dart';
import '../components/app_footer.dart';
import '../components/sliver_headers.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

/// Hoisted formatters: allocating `DateFormat` per build/row is wasteful.
final _monthDayFormat = DateFormat.MMMd();
final _monthDayYearFormat = DateFormat.yMMMd();
final _monthYearFormat = DateFormat.yMMMM();
final _monthShortYearFormat = DateFormat('MMM yyyy');
final _monthShortFormat = DateFormat.MMM();
final _dayKeyFormat = DateFormat('yyyy-MM-dd');
final _weekdayFormat = DateFormat('EEEE');
final _weekdayShortFormat = DateFormat('EEE');

/// Width at which the layout switches from the phone arrangement (scrolling
/// day tiles, stacked toolbar) to the desktop one (seven tiles in a row,
/// tabs and week controls on one line).
const double _wideBreakpoint = 720;

/// Height of one release card; the grid uses a fixed extent so the poster,
/// title, time row and platform chip always fit.
const double _cardHeight = 150;

/// Weekly release calendar with separate Anime / Manga tabs.
///
/// Layout follows the Schedule reference: title + time-zone picker, the
/// Anime/Manga tabs with the week controls, a strip of seven day tiles, and a
/// grid of release cards for the selected day with a sort control. While a
/// week loads, a shimmer skeleton with the real card's proportions is shown.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({this.initialTab, super.key});

  /// Tab to open on (`?tab=anime|manga`); null keeps the last-used tab.
  final CalendarTab? initialTab;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  String? _selectedDayKey;

  @override
  void initState() {
    super.initState();
    _applyInitialTab();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) _applyInitialTab();
  }

  void _applyInitialTab() {
    final tab = widget.initialTab;
    if (tab == null) return;
    // Provider state can't be modified during build/initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(calendarControllerProvider.notifier).setTab(tab);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(calendarControllerProvider.select((s) => s.tab));
    final status = ref.watch(
      calendarControllerProvider.select(
        (s) => s.tab == CalendarTab.anime ? s.status : s.mangaStatus,
      ),
    );
    void selectDay(String key) => setState(() => _selectedDayKey = key);

    return SmoothCustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: _Header()),
        const SliverToBoxAdapter(child: _Toolbar()),
        switch (status) {
          LoadStatus.initial || LoadStatus.loading => _ScheduleBody(
            tab: tab,
            loading: true,
            selectedDayKey: _selectedDayKey,
            onSelectDay: selectDay,
          ),
          LoadStatus.error => _ErrorSliver(tab: tab),
          LoadStatus.success => _ScheduleBody(
            tab: tab,
            loading: false,
            selectedDayKey: _selectedDayKey,
            onSelectDay: selectDay,
          ),
        },
        const SliverAppFooter(),
      ],
    );
  }
}

class _ErrorSliver extends ConsumerWidget {
  const _ErrorSliver({required this.tab});

  final CalendarTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = ref.watch(
      calendarControllerProvider.select(
        (s) => tab == CalendarTab.anime
            ? (s.errorMessage ?? 'Could not load the schedule.')
            : (s.mangaErrorMessage ?? 'Could not load manga releases.'),
      ),
    );
    final controller = ref.read(calendarControllerProvider.notifier);
    return SliverError(message: message, onRetry: controller.load);
  }
}

// ---------------------------------------------------------------------------
// Header: title, "Live Season" pill, subtitle, time-zone picker
// ---------------------------------------------------------------------------

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tab = ref.watch(calendarControllerProvider.select((s) => s.tab));
    final total = ref.watch(
      calendarControllerProvider.select(
        (s) =>
            s.tab == CalendarTab.anime ? s.items.length : s.mangaItems.length,
      ),
    );
    final loading = ref.watch(
      calendarControllerProvider.select(
        (s) => s.tab == CalendarTab.anime
            ? s.status != LoadStatus.success
            : s.mangaStatus != LoadStatus.success,
      ),
    );
    final weekOffset = ref.watch(
      calendarControllerProvider.select((s) => s.weekOffset),
    );
    final zone = ref.watch(calendarControllerProvider.select((s) => s.zone));

    final weekLabel = switch (weekOffset) {
      0 => 'This week',
      1 => 'Next week',
      -1 => 'Last week',
      _ => 'Week ${_isoWeekNumber(calendarWeekStart(zone, weekOffset))}',
    };
    final count = loading ? 0 : total;
    final countLabel = tab == CalendarTab.anime
        ? '$count ${count == 1 ? 'release' : 'releases'}'
        : '$count new manga';
    final suffix = tab == CalendarTab.anime
        ? ' across simulcast platforms'
        : ' starting this week';
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space20,
            Tokens.space16,
            Tokens.space16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Tokens.space12,
                      runSpacing: Tokens.space4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Schedule',
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const _LiveSeasonPill(),
                      ],
                    ),
                    const SizedBox(height: Tokens.space4),
                    if (loading)
                      const SizedBox(
                        height: 20,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SkeletonShimmer(
                            child: SkeletonBone(
                              width: 240,
                              height: 14,
                              radius: 4,
                            ),
                          ),
                        ),
                      )
                    else
                      Text.rich(
                        TextSpan(
                          style: muted,
                          children: [
                            TextSpan(text: '$weekLabel · '),
                            TextSpan(
                              text: countLabel,
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextSpan(text: suffix),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: Tokens.space12),
              _ZonePicker(zone: zone),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// "● Live Season" pill beside the title.
class _LiveSeasonPill extends StatelessWidget {
  const _LiveSeasonPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Live Season',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "TZ: JST (UTC+9) ⌄" menu. Changing it re-buckets the whole week.
class _ZonePicker extends ConsumerWidget {
  const _ZonePicker({required this.zone});

  final CalendarZone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showPrefix = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final controller = ref.read(calendarControllerProvider.notifier);

    return PopupMenuButton<CalendarZone>(
      tooltip: 'Time zone',
      initialValue: zone,
      onSelected: controller.setZone,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      itemBuilder: (context) => [
        for (final z in CalendarZone.values)
          CheckedPopupMenuItem(
            value: z,
            checked: z == zone,
            child: Text(z.label),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space12,
          vertical: Tokens.space8,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 15, color: scheme.primary),
            const SizedBox(width: Tokens.space8),
            if (showPrefix) ...[
              Text(
                'TZ:',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Tokens.space4),
            ],
            Text(
              zone.label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: Tokens.space4),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar: Anime / Manga tabs + week controls
// ---------------------------------------------------------------------------

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekOffset = ref.watch(
      calendarControllerProvider.select((s) => s.weekOffset),
    );
    final zone = ref.watch(calendarControllerProvider.select((s) => s.zone));
    final isLoading = ref.watch(
      calendarControllerProvider.select(
        (s) =>
            s.status == LoadStatus.loading ||
            s.mangaStatus == LoadStatus.loading,
      ),
    );
    final controller = ref.read(calendarControllerProvider.notifier);
    final monday = calendarWeekStart(zone, weekOffset);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final weekNumber = _isoWeekNumber(monday);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space16,
              Tokens.space20,
              Tokens.space16,
              Tokens.space20,
            ),
            child: Row(
              children: [
                const _TabPills(),
                const Spacer(),
                _WideWeekControls(
                  rangeLabel: _rangeLabel(monday, sunday),
                  weekNumber: weekNumber,
                  isLoading: isLoading,
                  isCurrentWeek: weekOffset == 0,
                  onPrevious: controller.previousWeek,
                  onNext: controller.nextWeek,
                  onToday: controller.thisWeek,
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space16,
            Tokens.space16,
            Tokens.space12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _TabPills(),
              const SizedBox(height: Tokens.space16),
              _CompactWeekBar(
                monthLabel: _monthLabel(monday, sunday),
                weekNumber: weekNumber,
                isLoading: isLoading,
                onPrevious: controller.previousWeek,
                onNext: controller.nextWeek,
                onToday: controller.thisWeek,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// "✓ Anime (118)" / "Manga (13)" pill toggles.
class _TabPills extends ConsumerWidget {
  const _TabPills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(calendarControllerProvider.select((s) => s.tab));
    final animeCount = ref.watch(
      calendarControllerProvider.select((s) => s.items.length),
    );
    final mangaCount = ref.watch(
      calendarControllerProvider.select((s) => s.mangaItems.length),
    );
    final controller = ref.read(calendarControllerProvider.notifier);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TabPill(
          label: 'Anime ($animeCount)',
          icon: Icons.live_tv_outlined,
          selected: tab == CalendarTab.anime,
          onTap: () => controller.setTab(CalendarTab.anime),
        ),
        const SizedBox(width: Tokens.space8),
        _TabPill(
          label: 'Manga ($mangaCount)',
          icon: Icons.menu_book_outlined,
          selected: tab == CalendarTab.manga,
          onTap: () => controller.setTab(CalendarTab.manga),
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: label,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Tokens.durationFast,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surfaceContainerLow,
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.space16,
                vertical: Tokens.space8,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? Icons.check_rounded : icon,
                    size: 16,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop: "[cal] Oct 26 – Nov 1, 2026 [WEEK 44]" and a "‹ TODAY ›" group.
class _WideWeekControls extends StatelessWidget {
  const _WideWeekControls({
    required this.rangeLabel,
    required this.weekNumber,
    required this.isLoading,
    required this.isCurrentWeek,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String rangeLabel;
  final int weekNumber;
  final bool isLoading;
  final bool isCurrentWeek;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = Border.all(color: scheme.outlineVariant);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space12,
            vertical: Tokens.space8,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: border,
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Tokens.space8),
              Text(
                rangeLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: Tokens.space8),
              _WeekBadge(weekNumber: weekNumber),
            ],
          ),
        ),
        const SizedBox(width: Tokens.space12),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: border,
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous week',
                visualDensity: VisualDensity.compact,
                onPressed: isLoading ? null : onPrevious,
                icon: const Icon(Icons.chevron_left_rounded, size: 20),
              ),
              TextButton(
                onPressed: isLoading || isCurrentWeek ? null : onToday,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurface,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.space12,
                  ),
                  textStyle: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                child: const Text('TODAY'),
              ),
              IconButton(
                tooltip: 'Next week',
                visualDensity: VisualDensity.compact,
                onPressed: isLoading ? null : onNext,
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Phone: "‹ ›  November 2026  [WEEK 44]            Jump to Today".
class _CompactWeekBar extends StatelessWidget {
  const _CompactWeekBar({
    required this.monthLabel,
    required this.weekNumber,
    required this.isLoading,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String monthLabel;
  final int weekNumber;
  final bool isLoading;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        // The left cluster scales down instead of overflowing on very
        // narrow phones, so "Jump to Today" always stays visible.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NavButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Previous week',
                    onPressed: isLoading ? null : onPrevious,
                  ),
                  const SizedBox(width: Tokens.space8),
                  _NavButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Next week',
                    onPressed: isLoading ? null : onNext,
                  ),
                  const SizedBox(width: Tokens.space12),
                  Text(
                    monthLabel,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: Tokens.space8),
                  _WeekBadge(weekNumber: weekNumber),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: Tokens.space8),
        TextButton(
          onPressed: isLoading ? null : onToday,
          style: TextButton.styleFrom(
            foregroundColor: scheme.primary,
            visualDensity: VisualDensity.compact,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          child: const Text('Jump to Today'),
        ),
      ],
    );
  }
}

/// Small rounded square arrow button used by the phone week bar.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurface,
          disabledBackgroundColor: scheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
          ),
        ),
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

/// "WEEK 44" pill in the primary tint.
class _WeekBadge extends StatelessWidget {
  const _WeekBadge({required this.weekNumber});

  final int weekNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
      child: Text(
        'WEEK $weekNumber',
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// ISO-8601 week number (weeks start Monday; week 1 holds the first
/// Thursday of the year). Computed in UTC so DST cannot skew the day count.
int _isoWeekNumber(DateTime date) {
  final thursday = DateTime.utc(
    date.year,
    date.month,
    date.day + 4 - date.weekday,
  );
  final firstJan = DateTime.utc(thursday.year, 1, 1);
  return thursday.difference(firstJan).inDays ~/ 7 + 1;
}

/// "Oct 26 – Nov 1, 2026" (years on both ends across New Year).
String _rangeLabel(DateTime monday, DateTime sunday) {
  if (monday.year != sunday.year) {
    return '${_monthDayYearFormat.format(monday)} – '
        '${_monthDayYearFormat.format(sunday)}';
  }
  return '${_monthDayFormat.format(monday)} – '
      '${_monthDayYearFormat.format(sunday)}';
}

/// "November 2026", or "Oct – Nov 2026" when the week spans two months.
String _monthLabel(DateTime monday, DateTime sunday) {
  if (monday.year == sunday.year && monday.month == sunday.month) {
    return _monthYearFormat.format(monday);
  }
  if (monday.year == sunday.year) {
    return '${_monthShortFormat.format(monday)} – '
        '${_monthShortFormat.format(sunday)} ${sunday.year}';
  }
  return '${_monthShortYearFormat.format(monday)} – '
      '${_monthShortYearFormat.format(sunday)}';
}

// ---------------------------------------------------------------------------
// Body: day strip + selected day
// ---------------------------------------------------------------------------

/// Everything a release card needs, for anime episodes and manga alike.
class _ReleaseData {
  const _ReleaseData({
    required this.mediaId,
    required this.mediaType,
    required this.title,
    required this.primaryLabel,
    required this.timeLabel,
    this.coverUrl,
    this.secondaryLabel,
    this.formatBadge,
    this.aired = false,
    this.dateOnly = false,
    this.score,
    this.platform,
  });

  final int mediaId;
  final MediaType mediaType;
  final String title;
  final String? coverUrl;
  final String primaryLabel;
  final String? secondaryLabel;
  final String? formatBadge;
  final String timeLabel;
  final bool aired;

  /// Manga only has a release date, so the time row shows a calendar icon.
  final bool dateOnly;
  final int? score;
  final String? platform;
}

String? _formatBadge(MediaFormat format) => switch (format) {
  MediaFormat.tv => 'TV',
  MediaFormat.tvShort => 'SHORT',
  MediaFormat.movie => 'MOVIE',
  MediaFormat.special => 'SPECIAL',
  MediaFormat.ova => 'OVA',
  MediaFormat.ona => 'ONA',
  MediaFormat.music => 'MUSIC',
  _ => null,
};

_ReleaseData _episodeData(AiringScheduleItem item, CalendarZone zone) {
  final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return _ReleaseData(
    mediaId: item.mediaId,
    mediaType: item.mediaType,
    title: item.title,
    coverUrl: item.coverUrl,
    primaryLabel: 'Episode ${item.episode}',
    secondaryLabel: item.totalEpisodes != null
        ? '/ ${item.totalEpisodes}'
        : null,
    formatBadge: _formatBadge(item.format),
    timeLabel: Formatters.clockTime(zone.wall(item.airingAt)),
    aired: item.airingAt <= nowSeconds,
    score: item.averageScore,
    platform: item.platform,
  );
}

_ReleaseData _mangaData(Media media) {
  return _ReleaseData(
    mediaId: media.id,
    mediaType: media.type,
    title: media.title,
    coverUrl: media.coverUrl.isEmpty ? null : media.coverUrl,
    primaryLabel: media.chapters != null
        ? 'Chapter ${media.chapters}'
        : media.volumes != null
        ? 'Volume ${media.volumes}'
        : media.format.label,
    formatBadge: media.format.label.toUpperCase(),
    timeLabel: Formatters.date(media.startDate),
    dateOnly: true,
    score: media.averageScore,
  );
}

/// Orders one day's episodes for the chosen sort.
List<AiringScheduleItem> _sortEpisodes(
  List<AiringScheduleItem> items,
  CalendarSort sort,
) {
  final sorted = [...items];
  switch (sort) {
    case CalendarSort.airTime:
      sorted.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    case CalendarSort.popularity:
      sorted.sort((a, b) {
        final byPopularity = (b.popularity ?? 0).compareTo(a.popularity ?? 0);
        return byPopularity != 0
            ? byPopularity
            : a.airingAt.compareTo(b.airingAt);
      });
    case CalendarSort.countdown:
      // Next to air first; episodes that already aired go last, newest first.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final upcoming = sorted.where((i) => i.airingAt > now).toList()
        ..sort((a, b) => a.airingAt.compareTo(b.airingAt));
      final aired = sorted.where((i) => i.airingAt <= now).toList()
        ..sort((a, b) => b.airingAt.compareTo(a.airingAt));
      return [...upcoming, ...aired];
  }
  return sorted;
}

/// Day strip + selected-day grid for the active tab.
class _ScheduleBody extends ConsumerWidget {
  const _ScheduleBody({
    required this.tab,
    required this.loading,
    required this.selectedDayKey,
    required this.onSelectDay,
  });

  final CalendarTab tab;

  /// True while the week is being fetched: counts and cards render as
  /// shimmer bones instead of stale or empty data.
  final bool loading;
  final String? selectedDayKey;
  final ValueChanged<String> onSelectDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekOffset = ref.watch(
      calendarControllerProvider.select((s) => s.weekOffset),
    );
    final zone = ref.watch(calendarControllerProvider.select((s) => s.zone));
    final sort = ref.watch(calendarControllerProvider.select((s) => s.sort));
    final weekStart = calendarWeekStart(zone, weekOffset);

    if (tab == CalendarTab.manga) {
      final items = loading
          ? const <Media>[]
          : ref.watch(calendarControllerProvider.select((s) => s.mangaItems));
      final byDay = <String, List<_ReleaseData>>{};
      for (final media in items) {
        final parsed = media.startDate == null
            ? null
            : DateTime.tryParse(media.startDate!);
        if (parsed == null) continue;
        byDay
            .putIfAbsent(_dayKeyFormat.format(parsed), () => [])
            .add(_mangaData(media));
      }
      return _DayLayout(
        weekStart: weekStart,
        zone: zone,
        loading: loading,
        releasesByDay: byDay,
        unitSingular: 'manga',
        unitPlural: 'manga',
        showSort: false,
        sort: sort,
        weekEmptyTitle: 'No manga releases this week',
        weekEmptyMessage:
            'No manga with a known start date begins in this week. '
            'AniList only tracks a start day for manga (no airing time), '
            'so this tab groups new releases by date — try another week.',
        weekEmptyIcon: Icons.menu_book_outlined,
        selectedDayKey: selectedDayKey,
        onSelectDay: onSelectDay,
      );
    }

    final items = loading
        ? const <AiringScheduleItem>[]
        : ref.watch(calendarControllerProvider.select((s) => s.items));
    final grouped = <String, List<AiringScheduleItem>>{};
    for (final item in items) {
      grouped
          .putIfAbsent(_dayKeyFormat.format(zone.wall(item.airingAt)), () => [])
          .add(item);
    }
    final byDay = <String, List<_ReleaseData>>{
      for (final entry in grouped.entries)
        entry.key: [
          for (final item in _sortEpisodes(entry.value, sort))
            _episodeData(item, zone),
        ],
    };
    return _DayLayout(
      weekStart: weekStart,
      zone: zone,
      loading: loading,
      releasesByDay: byDay,
      unitSingular: 'episode',
      unitPlural: 'episodes',
      showSort: true,
      sort: sort,
      weekEmptyTitle: 'Nothing airing this week',
      weekEmptyMessage:
          'AniList has no scheduled episodes for this week yet. '
          'Try another week — the schedule usually updates ahead of time.',
      weekEmptyIcon: Icons.event_busy_outlined,
      selectedDayKey: selectedDayKey,
      onSelectDay: onSelectDay,
    );
  }
}

/// One day of the visible week.
class _StripDay {
  const _StripDay({required this.date, required this.releases});

  final DateTime date;
  final List<_ReleaseData> releases;
}

/// Day strip (all seven days of the week) above the selected day's grid.
class _DayLayout extends StatelessWidget {
  const _DayLayout({
    required this.weekStart,
    required this.zone,
    required this.loading,
    required this.releasesByDay,
    required this.unitSingular,
    required this.unitPlural,
    required this.showSort,
    required this.sort,
    required this.weekEmptyTitle,
    required this.weekEmptyMessage,
    required this.weekEmptyIcon,
    required this.selectedDayKey,
    required this.onSelectDay,
  });

  final DateTime weekStart;
  final CalendarZone zone;
  final bool loading;
  final Map<String, List<_ReleaseData>> releasesByDay;
  final String unitSingular;
  final String unitPlural;
  final bool showSort;
  final CalendarSort sort;
  final String weekEmptyTitle;
  final String weekEmptyMessage;
  final IconData weekEmptyIcon;
  final String? selectedDayKey;
  final ValueChanged<String> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final todayKey = _dayKeyFormat.format(zone.wallNow);
    final days = <_StripDay>[
      for (var i = 0; i < 7; i++)
        _StripDay(
          date: DateTime(weekStart.year, weekStart.month, weekStart.day + i),
          releases:
              releasesByDay[_dayKeyFormat.format(
                DateTime(weekStart.year, weekStart.month, weekStart.day + i),
              )] ??
              const [],
        ),
    ];

    final keys = [for (final d in days) _dayKeyFormat.format(d.date)];
    var activeKey = selectedDayKey;
    if (activeKey == null || !keys.contains(activeKey)) {
      if (keys.contains(todayKey)) {
        activeKey = todayKey;
      } else {
        // Not the current week: open on the first day that has releases.
        final firstWithItems = days.indexWhere((d) => d.releases.isNotEmpty);
        activeKey = keys[firstWithItems < 0 ? 0 : firstWithItems];
      }
    }
    final active = days[keys.indexOf(activeKey)];
    final weekIsEmpty = !loading && days.every((d) => d.releases.isEmpty);
    final count = active.releases.length;

    final Widget content;
    if (loading) {
      content = const _CardGrid(skeleton: true, releases: []);
    } else if (weekIsEmpty) {
      content = _InlineEmpty(
        icon: weekEmptyIcon,
        title: weekEmptyTitle,
        message: weekEmptyMessage,
      );
    } else if (count == 0) {
      content = _InlineEmpty(
        icon: Icons.event_available_outlined,
        title: 'Nothing on ${_weekdayFormat.format(active.date)}',
        message: 'Pick another day to see its releases.',
      );
    } else {
      content = _CardGrid(skeleton: false, releases: active.releases);
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: Tokens.space32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DayStrip(
              days: days,
              loading: loading,
              activeKey: activeKey,
              todayKey: todayKey,
              onSelectDay: onSelectDay,
            ),
            const SizedBox(height: Tokens.space16),
            const Divider(height: 1),
            _SelectedDayHeader(
              title: _weekdayFormat.format(active.date),
              countLabel: '$count ${count == 1 ? unitSingular : unitPlural}',
              showCount: loading || !weekIsEmpty,
              loading: loading,
              sort: showSort && !weekIsEmpty ? sort : null,
            ),
            content,
          ],
        ),
      ),
    );
  }
}

/// "Saturday — [28 episodes]" with the sort control on the right.
class _SelectedDayHeader extends ConsumerWidget {
  const _SelectedDayHeader({
    required this.title,
    required this.countLabel,
    required this.showCount,
    required this.loading,
    required this.sort,
  });

  final String title;
  final String countLabel;
  final bool showCount;
  final bool loading;

  /// Null hides the sort control (manga, or an empty week).
  final CalendarSort? sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final controller = ref.read(calendarControllerProvider.notifier);

    final heading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: Tokens.space8),
          Text('—', style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(width: Tokens.space8),
          if (loading)
            const SkeletonShimmer(
              child: SkeletonBone(
                width: 108,
                height: 28,
                radius: Tokens.radiusPill,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.space12,
                vertical: Tokens.space4,
              ),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(Tokens.radiusPill),
              ),
              child: Text(
                countLabel,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        final sortControl = sort == null
            ? null
            : _SortControl(selected: sort!, onChanged: controller.setSort);
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space20,
            Tokens.space16,
            Tokens.space16,
          ),
          child: wide || sortControl == null
              ? Row(
                  children: [
                    Flexible(child: heading),
                    const Spacer(),
                    ?sortControl,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    heading,
                    const SizedBox(height: Tokens.space12),
                    sortControl,
                  ],
                ),
        );
      },
    );
  }
}

/// "Sort by: Air Time | Popularity | Countdown".
class _SortControl extends StatelessWidget {
  const _SortControl({required this.selected, required this.onChanged});

  final CalendarSort selected;
  final ValueChanged<CalendarSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Sort by:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: Tokens.space12),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(Tokens.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in CalendarSort.values)
                  _SortSegment(
                    label: option.label,
                    selected: option == selected,
                    onTap: () => onChanged(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SortSegment extends StatelessWidget {
  const _SortSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: 'Sort by $label',
      onTap: onTap,
      child: AnimatedContainer(
        duration: Tokens.durationFast,
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Tokens.radiusSm + 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusSm + 2),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Tokens.space12,
                vertical: Tokens.space8,
              ),
              child: Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day strip + tiles
// ---------------------------------------------------------------------------

/// Seven day tiles. Phones: horizontally scrolling tiles with the weekday,
/// a big date number and a count. Desktop: an even row of seven wider tiles.
class _DayStrip extends StatefulWidget {
  const _DayStrip({
    required this.days,
    required this.loading,
    required this.activeKey,
    required this.todayKey,
    required this.onSelectDay,
  });

  final List<_StripDay> days;
  final bool loading;
  final String activeKey;
  final String todayKey;
  final ValueChanged<String> onSelectDay;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  final ScrollController _scroll = ScrollController();
  String? _lastRevealedKey;

  static const double _compactTileWidth = 64;
  static const double _compactGap = 8;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the active phone tile visible (e.g. when "Today" is Saturday).
  void _revealActive() {
    if (_lastRevealedKey == widget.activeKey) return;
    _lastRevealedKey = widget.activeKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = widget.days.indexWhere(
        (d) => _dayKeyFormat.format(d.date) == widget.activeKey,
      );
      if (index < 0) return;
      final tileStart = index * (_compactTileWidth + _compactGap);
      final viewport = _scroll.position.viewportDimension;
      final target = (tileStart - (viewport - _compactTileWidth) / 2).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: Tokens.durationMedium,
        curve: Tokens.curveSmooth,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideBreakpoint;
        if (wide) {
          return Padding(
            // Top inset leaves room for the TODAY chip that overlaps the
            // tile's top edge.
            padding: const EdgeInsets.fromLTRB(
              Tokens.space16,
              Tokens.space12,
              Tokens.space16,
              Tokens.space8,
            ),
            child: SizedBox(
              height: 118,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.days.length; i++) ...[
                    if (i > 0) const SizedBox(width: Tokens.space12),
                    Expanded(child: _tile(widget.days[i], wide: true)),
                  ],
                ],
              ),
            ),
          );
        }
        _revealActive();
        return SizedBox(
          height: 140,
          child: ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            // Let the selected tile's glow render outside the list bounds.
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(
              horizontal: Tokens.space16,
              vertical: Tokens.space12,
            ),
            itemCount: widget.days.length,
            separatorBuilder: (_, _) => const SizedBox(width: _compactGap),
            itemBuilder: (context, i) => SizedBox(
              width: _compactTileWidth,
              child: _tile(widget.days[i], wide: false),
            ),
          ),
        );
      },
    );
  }

  Widget _tile(_StripDay day, {required bool wide}) {
    final key = _dayKeyFormat.format(day.date);
    final selected = key == widget.activeKey;
    final isToday = key == widget.todayKey;
    void onTap() => widget.onSelectDay(key);
    return wide
        ? _WideDayTile(
            date: day.date,
            count: day.releases.length,
            loading: widget.loading,
            selected: selected,
            isToday: isToday,
            onTap: onTap,
          )
        : _CompactDayTile(
            date: day.date,
            count: day.releases.length,
            loading: widget.loading,
            selected: selected,
            isToday: isToday,
            onTap: onTap,
          );
  }
}

/// Colors shared by both tile styles, derived from the active theme so the
/// selected tile follows the user's accent choice (Settings → Accent).
class _TileColors {
  _TileColors(ColorScheme scheme, {required this.selected})
    : background = selected ? scheme.primary : scheme.surfaceContainerLow,
      border = selected ? scheme.primary : scheme.outlineVariant,
      primaryText = selected ? scheme.onPrimary : scheme.onSurface,
      secondaryText = selected
          ? scheme.onPrimary.withValues(alpha: 0.78)
          : scheme.onSurfaceVariant,
      pillBackground = selected
          ? scheme.onPrimary.withValues(alpha: 0.16)
          : scheme.surfaceContainerHighest,
      pillText = selected ? scheme.onPrimary : scheme.onSurfaceVariant,
      accentText = selected ? scheme.onPrimary : scheme.primary;

  final bool selected;
  final Color background;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color pillBackground;
  final Color pillText;
  final Color accentText;
}

String _releaseWord(int count) => count == 1 ? 'release' : 'releases';

/// Count pill that turns into a shimmer bone while the week loads.
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.text,
    required this.loading,
    required this.colors,
    this.minWidth = 0,
    this.fontSize,
  });

  final String text;
  final bool loading;
  final _TileColors colors;
  final double minWidth;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) {
      return SkeletonShimmer(
        child: SkeletonBone(
          width: minWidth > 32 ? minWidth : 32,
          height: 20,
          radius: Tokens.radiusPill,
        ),
      );
    }
    return Container(
      constraints: BoxConstraints(minWidth: minWidth),
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space2,
      ),
      decoration: BoxDecoration(
        color: colors.pillBackground,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          maxLines: 1,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.pillText,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Phone tile: weekday (or TODAY), big date number, release count pill.
class _CompactDayTile extends StatelessWidget {
  const _CompactDayTile({
    required this.date,
    required this.count,
    required this.loading,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final int count;
  final bool loading;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = _TileColors(scheme, selected: selected);
    final weekday = isToday
        ? 'TODAY'
        : _weekdayShortFormat.format(date).toUpperCase();

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${_weekdayFormat.format(date)} ${_monthDayFormat.format(date)}'
          '${isToday ? ', today' : ''}, $count ${_releaseWord(count)}',
      excludeSemantics: true,
      onTap: onTap,
      child: AnimatedContainer(
        duration: Tokens.durationFast,
        curve: Tokens.curveSmooth,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          border: Border.all(
            color: isToday && !selected ? scheme.primary : colors.border,
          ),
          boxShadow: selected ? Tokens.glowShadow(scheme.primary) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            onTap: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekday,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isToday ? colors.accentText : colors.secondaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: Tokens.space4),
                Text(
                  '${date.day}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
                const SizedBox(height: Tokens.space8),
                _CountPill(
                  text: loading ? '00' : '$count',
                  loading: loading,
                  colors: colors,
                  minWidth: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop tile: "THU · OCT 29", big date number, "9 releases" pill. Today
/// carries a TODAY chip on its top edge; the selected tile is filled and
/// glows.
class _WideDayTile extends StatelessWidget {
  const _WideDayTile({
    required this.date,
    required this.count,
    required this.loading,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final int count;
  final bool loading;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = _TileColors(scheme, selected: selected);
    final label =
        '${_weekdayShortFormat.format(date).toUpperCase()} · '
        '${_monthShortFormat.format(date).toUpperCase()} ${date.day}';

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${_weekdayFormat.format(date)} ${_monthDayFormat.format(date)}'
          '${isToday ? ', today' : ''}, $count ${_releaseWord(count)}',
      excludeSemantics: true,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedContainer(
              duration: Tokens.durationFast,
              curve: Tokens.curveSmooth,
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
                border: Border.all(
                  color: isToday && !selected
                      ? scheme.primary.withValues(alpha: 0.7)
                      : colors.border,
                ),
                boxShadow: selected ? Tokens.glowShadow(scheme.primary) : null,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Tokens.space8,
                      vertical: Tokens.space12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.secondaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: Tokens.space4),
                        Text(
                          '${date.day}',
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: Tokens.space8),
                        _CountPill(
                          text: loading
                              ? '00 releases'
                              : '$count ${_releaseWord(count)}',
                          loading: loading,
                          colors: colors,
                          fontSize: 11,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isToday)
            Positioned(
              top: -9,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(child: _TodayChip(scheme: scheme)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "● TODAY" chip sitting on the top edge of today's desktop tile.
class _TodayChip extends StatelessWidget {
  const _TodayChip({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        // Opaque so the tile's border does not show through the chip.
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.18),
          scheme.surface,
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'TODAY',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty message shown inside the selected-day section.
class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space16,
        vertical: Tokens.space24,
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: Tokens.space12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Tokens.space4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Card grid + release card
// ---------------------------------------------------------------------------

int _cardColumns(double width) {
  if (width >= 1250) return 4;
  if (width >= 950) return 3;
  if (width >= 620) return 2;
  return 1;
}

/// Responsive grid of release cards. With [skeleton] set it renders two rows
/// of [_ReleaseCardSkeleton]s, so the loading state has the exact proportions
/// of the real cards.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.skeleton, required this.releases});

  final bool skeleton;
  final List<_ReleaseData> releases;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _cardColumns(constraints.maxWidth);
        final itemCount = skeleton ? columns * 2 : releases.length;
        final grid = GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            0,
            Tokens.space16,
            Tokens.space8,
          ),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: Tokens.space16,
            crossAxisSpacing: Tokens.space16,
            mainAxisExtent: _cardHeight,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) => RepaintBoundary(
            child: skeleton
                ? const _ReleaseCardSkeleton()
                : _ReleaseCard(data: releases[index]),
          ),
        );
        return grid;
      },
    );
  }
}

/// Site-brand tint for the platform chip; null falls back to a neutral chip.
Color? _platformColor(String site) {
  final s = site.toLowerCase();
  if (s.contains('crunchyroll')) return const Color(0xFFF47521);
  if (s.contains('netflix')) return const Color(0xFFE5484D);
  if (s.contains('bilibili')) return const Color(0xFF3FA9F5);
  if (s.contains('youtube')) return const Color(0xFFFF4E45);
  if (s.contains('tencent')) return const Color(0xFF4C8DFF);
  if (s.contains('wetv')) return const Color(0xFFA66CFF);
  if (s.contains('muse')) return const Color(0xFF2FBF9B);
  if (s.contains('hulu')) return const Color(0xFF1CE783);
  if (s.contains('disney')) return const Color(0xFF4B7BFF);
  if (s.contains('prime') || s.contains('amazon')) {
    return const Color(0xFF00A8E1);
  }
  if (s.contains('hidive')) return const Color(0xFF00BAFF);
  if (s.contains('iqiyi')) return const Color(0xFF00CC36);
  return null;
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final brand = _platformColor(site) ?? scheme.onSurfaceVariant;
    // Brand colors are tuned for dark UIs; deepen them on light surfaces so
    // the label keeps its contrast.
    final text = isLight ? Color.lerp(brand, Colors.black, 0.4)! : brand;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.14),
        border: Border.all(color: brand.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(Tokens.radiusSm),
      ),
      child: Text(
        site,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: text,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Release card: poster with format badge, title + bell, episode, then the
/// time, score and streaming platform. Shared by anime and manga.
class _ReleaseCard extends ConsumerWidget {
  const _ReleaseCard({required this.data});

  final _ReleaseData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reminded = ref.watch(
      calendarRemindersProvider.select((s) => s.contains(data.mediaId)),
    );
    final hasScore = data.score != null && data.score! > 0;

    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            context.go(Routes.mediaDetail(data.mediaType, data.mediaId)),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space12 + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Poster(data: data),
              const SizedBox(width: Tokens.space12 + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            data.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            iconSize: 16,
                            tooltip: reminded ? 'Remove reminder' : 'Remind me',
                            color: reminded
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            onPressed: () => ref
                                .read(calendarRemindersProvider.notifier)
                                .toggle(data.mediaId),
                            icon: Icon(
                              reminded
                                  ? Icons.notifications_active_rounded
                                  : Icons.notifications_none_rounded,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.space2),
                    Text.rich(
                      TextSpan(
                        text: data.primaryLabel,
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          if (data.secondaryLabel != null)
                            TextSpan(
                              text: ' ${data.secondaryLabel}',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    Divider(height: 1, color: scheme.outlineVariant),
                    const SizedBox(height: Tokens.space8),
                    Row(
                      children: [
                        Icon(
                          data.dateOnly
                              ? Icons.event_outlined
                              : data.aired
                              ? Icons.check_circle_outline_rounded
                              : Icons.schedule_rounded,
                          size: 14,
                          color: data.aired
                              ? Tokens.success
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            data.timeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (hasScore) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: Tokens.warning,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            Formatters.score(data.score),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: Tokens.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ] else
                          Text(
                            '–',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    if (data.platform != null) ...[
                      const SizedBox(height: Tokens.space8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _PlatformChip(site: data.platform!),
                      ),
                    ],
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

/// Loading twin of [_ReleaseCard]: the same shell, padding, poster ratio and
/// text rows, with shimmering bones in place of the content. Only the bones
/// are inside the shimmer, so the card surface itself stays solid.
class _ReleaseCardSkeleton extends StatelessWidget {
  const _ReleaseCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(Tokens.space12 + 2),
        child: SkeletonShimmer(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AspectRatio(
                aspectRatio: 0.7,
                child: SkeletonBone(radius: Tokens.radiusMd),
              ),
              const SizedBox(width: Tokens.space12 + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonLine(height: 16),
                    const SizedBox(height: Tokens.space8),
                    const SkeletonLine(fraction: 0.7, height: 16),
                    const SizedBox(height: Tokens.space8),
                    const SkeletonLine(fraction: 0.4, height: 13),
                    const Spacer(),
                    const SkeletonLine(fraction: 0.55, height: 14),
                    const SizedBox(height: Tokens.space12),
                    SkeletonBone(
                      width: 84,
                      height: 20,
                      radius: Tokens.radiusSm,
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

/// Poster with the format badge ("TV", "ONA", "SHORT") on its corner.
class _Poster extends StatelessWidget {
  const _Poster({required this.data});

  final _ReleaseData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = Container(
      color: theme.disabledColor.withValues(alpha: 0.15),
      child: const Center(
        child: Icon(Icons.image_not_supported_outlined, size: 20),
      ),
    );
    final cover = data.coverUrl;

    return AspectRatio(
        aspectRatio: 0.7,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover == null || cover.isEmpty)
                fallback
              else
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  errorBuilder: (context, error, stack) => fallback,
                ),
              if (data.formatBadge != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      data.formatBadge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
    );
  }
}
