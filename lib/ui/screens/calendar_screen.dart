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
final _rangeFormat = DateFormat.MMMd();
final _dayKeyFormat = DateFormat('yyyy-MM-dd');
final _weekdayFormat = DateFormat('EEEE');
final _dayNumFormat = DateFormat('MMM d');

/// Weekly release calendar with separate Anime / Manga tabs.
///
/// Layout follows the Schedule reference: title + release count, a week
/// pill selector, a day rail (vertical on wide screens, chips on narrow),
/// and a grid of horizontal episode cards for the selected day. Each card
/// shows the release date + time (or an "Aired" marker once past).
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  String? _selectedDayKey;

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(
      calendarControllerProvider.select((s) => s.tab),
    );
    final status = ref.watch(
      calendarControllerProvider.select(
        (s) => s.tab == CalendarTab.anime ? s.status : s.mangaStatus,
      ),
    );
    final isReloading = ref.watch(
      calendarControllerProvider.select(
        (s) => s.tab == CalendarTab.anime
            ? s.status == LoadStatus.loading && s.items.isNotEmpty
            : s.mangaStatus == LoadStatus.loading &&
                  s.mangaItems.isNotEmpty,
      ),
    );

    return CustomScrollView(
      physics: const SmoothScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: _Header()),
        const SliverToBoxAdapter(child: _WeekPill()),
        if (isReloading)
          const SliverToBoxAdapter(
            child: LinearProgressIndicator(minHeight: 2),
          ),
        switch (status) {
          LoadStatus.initial || LoadStatus.loading => _LoadingSlivers(tab: tab),
          LoadStatus.error => _ErrorSlivers(tab: tab),
          LoadStatus.success => _ScheduleBody(
            tab: tab,
            selectedDayKey: _selectedDayKey,
            onSelectDay: (key) =>
                setState(() => _selectedDayKey = key),
          ),
        },
        const SliverAppFooter(),
      ],
    );
  }
}

class _LoadingSlivers extends ConsumerWidget {
  const _LoadingSlivers({required this.tab});

  final CalendarTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItems = ref.watch(
      calendarControllerProvider.select(
        (s) => tab == CalendarTab.anime
            ? s.items.isNotEmpty
            : s.mangaItems.isNotEmpty,
      ),
    );
    if (hasItems) {
      // Keep-previous-data while reloading; selection passthrough is fine
      // because the body re-derives a valid day when keys change.
      return _ScheduleBody(
        tab: tab,
        selectedDayKey: null,
        onSelectDay: (_) {},
      );
    }
    return const SliverToBoxAdapter(child: LoadingPosterGrid());
  }
}

class _ErrorSlivers extends ConsumerWidget {
  const _ErrorSlivers({required this.tab});

  final CalendarTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasItems = ref.watch(
      calendarControllerProvider.select(
        (s) => tab == CalendarTab.anime
            ? s.items.isNotEmpty
            : s.mangaItems.isNotEmpty,
      ),
    );
    if (hasItems) {
      return _ScheduleBody(
        tab: tab,
        selectedDayKey: null,
        onSelectDay: (_) {},
      );
    }
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

/// Title row: "Schedule", "This week · N releases", Anime/Manga tabs.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tab = ref.watch(
      calendarControllerProvider.select((s) => s.tab),
    );
    final animeCount = ref.watch(
      calendarControllerProvider.select((s) => s.items.length),
    );
    final mangaCount = ref.watch(
      calendarControllerProvider.select((s) => s.mangaItems.length),
    );
    final controller = ref.read(calendarControllerProvider.notifier);
    final total = tab == CalendarTab.anime ? animeCount : mangaCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space20,
        Tokens.space16,
        Tokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Schedule', style: theme.textTheme.headlineMedium),
          const SizedBox(height: Tokens.space2),
          Text(
            'This week · $total releases',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.space12),
          SegmentedButton<CalendarTab>(
            segments: [
              ButtonSegment(
                value: CalendarTab.anime,
                label: Text('Anime ($animeCount)'),
                icon: const Icon(Icons.live_tv_outlined, size: 18),
              ),
              ButtonSegment(
                value: CalendarTab.manga,
                label: Text('Manga ($mangaCount)'),
                icon: const Icon(Icons.menu_book_outlined, size: 18),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (selected) =>
                controller.setTab(selected.first),
          ),
        ],
      ),
    );
  }
}

/// Week pill selector: "< Oct 12 – Oct 18 >".
class _WeekPill extends ConsumerWidget {
  const _WeekPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final weekOffset = ref.watch(
      calendarControllerProvider.select((s) => s.weekOffset),
    );
    final isLoading = ref.watch(
      calendarControllerProvider.select(
        (s) =>
            s.status == LoadStatus.loading ||
            s.mangaStatus == LoadStatus.loading,
      ),
    );
    final controller = ref.read(calendarControllerProvider.notifier);

    // Calendar arithmetic (not Duration) so DST changes cannot shift the day.
    final thisMonday = _mondayOf(DateTime.now());
    final monday = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day + 7 * weekOffset,
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final label =
        '${_rangeFormat.format(monday)} – ${_rangeFormat.format(sunday)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space4,
        Tokens.space16,
        Tokens.space12,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous week',
                visualDensity: VisualDensity.compact,
                onPressed: isLoading ? null : controller.previousWeek,
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              GestureDetector(
                onTap: isLoading ? null : controller.thisWeek,
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next week',
                visualDensity: VisualDensity.compact,
                onPressed: isLoading ? null : controller.nextWeek,
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

DateTime _mondayOf(DateTime date) {
  return DateTime(date.year, date.month, date.day - (date.weekday - 1));
}

/// Day rail + selected-day grid for the active tab.
class _ScheduleBody extends ConsumerWidget {
  const _ScheduleBody({
    required this.tab,
    required this.selectedDayKey,
    required this.onSelectDay,
  });

  final CalendarTab tab;
  final String? selectedDayKey;
  final ValueChanged<String> onSelectDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tab == CalendarTab.manga) {
      final items = ref.watch(
        calendarControllerProvider.select((s) => s.mangaItems),
      );
      if (items.isEmpty) {
        return const SliverEmpty(
          title: 'No manga releases this week',
          message:
              'No manga with a known start date begins in this week. '
              'AniList only tracks a start day for manga (no airing time), '
              'so this tab groups new releases by date — try another week.',
          icon: Icons.menu_book_outlined,
        );
      }
      final days = _groupMangaByDay(items);
      return _DayLayout<MangaDay>(
        days: days,
        keyOf: (d) => d.key,
        labelOf: (d) => '${d.items.length} manga',
        titleOf: (d) => _weekdayFormat.format(d.date),
        selectedDayKey: selectedDayKey,
        onSelectDay: onSelectDay,
        cardBuilder: (media) => _MangaCard(media: media),
        itemsOf: (d) => d.items,
      );
    }

    final items = ref.watch(
      calendarControllerProvider.select((s) => s.items),
    );
    if (items.isEmpty) {
      return const SliverEmpty(
        title: 'Nothing airing this week',
        message:
            'AniList has no scheduled episodes for this week yet. '
            'Try another week — the schedule usually updates ahead of time.',
        icon: Icons.event_busy_outlined,
      );
    }
    final days = _groupAnimeByDay(items);
    return _DayLayout<AnimeDay>(
      days: days,
      keyOf: (d) => d.key,
      labelOf: (d) => '${d.items.length} episodes',
      titleOf: (d) => _weekdayFormat.format(d.date),
      selectedDayKey: selectedDayKey,
      onSelectDay: onSelectDay,
      cardBuilder: (item) => _EpisodeCard(item: item),
      itemsOf: (d) => d.items,
    );
  }
}

/// Generic day-rail + grid layout shared by the anime and manga tabs.
class _DayLayout<D> extends StatelessWidget {
  const _DayLayout({
    required this.days,
    required this.keyOf,
    required this.labelOf,
    required this.titleOf,
    required this.selectedDayKey,
    required this.onSelectDay,
    required this.cardBuilder,
    required this.itemsOf,
  });

  final List<D> days;
  final String Function(D day) keyOf;
  final String Function(D day) labelOf;
  final String Function(D day) titleOf;
  final String? selectedDayKey;
  final ValueChanged<String> onSelectDay;
  final Widget Function(dynamic item) cardBuilder;
  final List<dynamic> Function(D day) itemsOf;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayKey = _dayKeyFormat.format(now);
    var activeKey = selectedDayKey;
    if (activeKey == null || !days.any((d) => keyOf(d) == activeKey)) {
      activeKey = days.any((d) => keyOf(d) == todayKey)
          ? todayKey
          : keyOf(days.first);
    }
    final active = days.firstWhere(
      (d) => keyOf(d) == activeKey,
      orElse: () => days.first,
    );
    final activeItems = itemsOf(active);
    final isToday = keyOf(active) == todayKey;

    return SliverToBoxAdapter(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final rail = _DayRail<D>(
            days: days,
            keyOf: keyOf,
            labelOf: labelOf,
            titleOf: titleOf,
            activeKey: activeKey!,
            vertical: wide,
            onSelectDay: onSelectDay,
          );
          final section = _SelectedDaySection(
            title: titleOf(active),
            isToday: isToday,
            countLabel: labelOf(active),
            grid: _CardGrid(
              itemCount: activeItems.length,
              itemBuilder: (context, i) =>
                  cardBuilder(activeItems[i]),
            ),
          );
          if (wide) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space16,
                0,
                Tokens.space16,
                Tokens.space32,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 220, child: rail),
                  const SizedBox(width: Tokens.space16),
                  Expanded(child: section),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: Tokens.space32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                rail,
                section,
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Day selector: vertical list on wide screens, horizontal chips on narrow.
class _DayRail<D> extends StatelessWidget {
  const _DayRail({
    required this.days,
    required this.keyOf,
    required this.labelOf,
    required this.titleOf,
    required this.activeKey,
    required this.vertical,
    required this.onSelectDay,
  });

  final List<D> days;
  final String Function(D day) keyOf;
  final String Function(D day) labelOf;
  final String Function(D day) titleOf;
  final String activeKey;
  final bool vertical;
  final ValueChanged<String> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final todayKey = _dayKeyFormat.format(now);

    DateTime dateOf(D day) => DateTime.parse(keyOf(day));

    Widget badge(int count) => Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Tokens.space8,
            vertical: Tokens.space2,
          ),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Tokens.radiusSm),
          ),
          child: Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        );

    int countOf(D day) {
      final label = labelOf(day);
      return int.tryParse(label.split(' ').first) ?? 0;
    }

    if (!vertical) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: Tokens.space16,
          vertical: Tokens.space4,
        ),
        child: Row(
          spacing: Tokens.space12,
          children: [
            for (final day in days)
              ChoiceChip(
                label: Text(
                  '${titleOf(day)} · ${countOf(day)}',
                ),
                selected: keyOf(day) == activeKey,
                onSelected: (_) => onSelectDay(keyOf(day)),
              ),
          ],
        ),
      );
    }

    return Column(
      spacing: Tokens.space8,
      children: [
        for (final day in days)
          Builder(
            builder: (context) {
              final selected = keyOf(day) == activeKey;
              final isToday = keyOf(day) == todayKey;
              return InkWell(
                borderRadius: BorderRadius.circular(Tokens.radiusMd),
                onTap: () => onSelectDay(keyOf(day)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.space12,
                    vertical: Tokens.space8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? scheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(Tokens.radiusMd),
                    border: selected
                        ? Border(
                            left: BorderSide(
                              color: scheme.primary,
                              width: 3,
                            ),
                          )
                        : const Border(
                            left: BorderSide(
                              color: Colors.transparent,
                              width: 3,
                            ),
                          ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              spacing: Tokens.space8,
                              children: [
                                Text(
                                  titleOf(day),
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: selected || isToday
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                if (isToday)
                                  Text(
                                    'TODAY',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              _dayNumFormat.format(dateOf(day)),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      badge(countOf(day)),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// "Monday  Today — 9 episodes" header plus the episode grid.
class _SelectedDaySection extends StatelessWidget {
  const _SelectedDaySection({
    required this.title,
    required this.isToday,
    required this.countLabel,
    required this.grid,
  });

  final String title;
  final bool isToday;
  final String countLabel;
  final Widget grid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space8,
            Tokens.space16,
            Tokens.space8,
          ),
          child: Row(
            spacing: Tokens.space8,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              if (isToday)
                Text(
                  'Today',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                '— $countLabel',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        grid,
      ],
    );
  }
}

/// Responsive grid of horizontal release cards.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.itemCount, required this.itemBuilder});

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _cardColumns(constraints.maxWidth);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space16,
            Tokens.space4,
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
            childAspectRatio: 2.55,
          ),
          itemCount: itemCount,
          itemBuilder: (context, index) => RepaintBoundary(
            child: itemBuilder(context, index),
          ),
        );
      },
    );
  }
}

int _cardColumns(double width) {
  if (width >= 1250) return 4;
  if (width >= 950) return 3;
  if (width >= 620) return 2;
  return 1;
}

/// Horizontal anime episode card: cover, title, episode, time/aired + score.
class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({required this.item});

  final AiringScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final airDate =
        DateTime.fromMillisecondsSinceEpoch(item.airingAt * 1000);
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final aired = item.airingAt <= nowSeconds;
    final timeLabel = Formatters.clockTime(airDate);
    final episodeLabel = item.totalEpisodes != null
        ? 'Episode ${item.episode} / ${item.totalEpisodes}'
        : 'Episode ${item.episode}';

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () =>
            context.go(Routes.mediaDetail(item.mediaType, item.mediaId)),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space12),
          child: Row(
            spacing: Tokens.space16,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: SizedBox(
                  width: 56,
                  height: 78,
                  child: item.coverUrl == null || item.coverUrl!.isEmpty
                      ? Container(
                          color: theme.disabledColor.withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                          ),
                        )
                      : Image.network(
                          item.coverUrl!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stack) => Container(
                            color: theme.disabledColor
                                .withValues(alpha: 0.15),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                    Text(
                      episodeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Tokens.space4),
                    Row(
                      spacing: Tokens.space8,
                      children: [
                        if (aired)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: Tokens.space2,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Tokens.space4,
                                  vertical: Tokens.space2,
                                ),
                                decoration: BoxDecoration(
                                  color: Tokens.success
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(
                                    Tokens.radiusSm,
                                  ),
                                ),
                                child: const Text(
                                  '✓ Aired',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Tokens.success,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            timeLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        if (item.averageScore != null &&
                            item.averageScore! > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: Tokens.warning,
                              ),
                              const SizedBox(width: Tokens.space2),
                              Text(
                                Formatters.score(item.averageScore),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Tokens.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                      ],
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

/// Horizontal manga release card: cover, title, date + status.
class _MangaCard extends StatelessWidget {
  const _MangaCard({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateLabel = Formatters.date(media.startDate);
    final chapterLabel = media.chapters != null
        ? 'Chapter ${media.chapters}'
        : media.volumes != null
            ? 'Volume ${media.volumes}'
            : media.format.label;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: InkWell(
        onTap: () => context.go(Routes.mediaDetail(media.type, media.id)),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space12),
          child: Row(
            spacing: Tokens.space16,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusSm),
                child: SizedBox(
                  width: 56,
                  height: 78,
                  child: media.coverUrl.isEmpty
                      ? Container(
                          color: theme.disabledColor.withValues(alpha: 0.15),
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 20,
                          ),
                        )
                      : Image.network(
                          media.coverUrl,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (context, error, stack) => Container(
                            color: theme.disabledColor
                                .withValues(alpha: 0.15),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Tokens.space2),
                    Text(
                      chapterLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: Tokens.space4),
                    Row(
                      spacing: Tokens.space8,
                      children: [
                        Text(
                          dateLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (media.averageScore != null &&
                            media.averageScore! > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: Tokens.warning,
                              ),
                              const SizedBox(width: Tokens.space2),
                              Text(
                                Formatters.score(media.averageScore),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Tokens.warning,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                      ],
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

/// One anime calendar day.
class AnimeDay {
  const AnimeDay({
    required this.key,
    required this.date,
    required this.items,
  });

  final String key;
  final DateTime date;
  final List<AiringScheduleItem> items;
}

/// One manga calendar day.
class MangaDay {
  const MangaDay({
    required this.key,
    required this.date,
    required this.items,
  });

  final String key;
  final DateTime date;
  final List<Media> items;
}

List<AnimeDay> _groupAnimeByDay(List<AiringScheduleItem> items) {
  final days = <String, List<AiringScheduleItem>>{};
  for (final item in items) {
    final date = DateTime.fromMillisecondsSinceEpoch(item.airingAt * 1000);
    final key = _dayKeyFormat.format(date);
    days.putIfAbsent(key, () => []).add(item);
  }
  final keys = days.keys.toList()..sort();
  return [
    for (final key in keys)
      AnimeDay(date: DateTime.parse(key), key: key, items: days[key]!),
  ];
}

List<MangaDay> _groupMangaByDay(List<Media> items) {
  final days = <String, List<Media>>{};
  for (final item in items) {
    final parsed = item.startDate == null
        ? null
        : DateTime.tryParse(item.startDate!);
    if (parsed == null) continue;
    final key = _dayKeyFormat.format(parsed);
    days.putIfAbsent(key, () => []).add(item);
  }
  final keys = days.keys.toList()..sort();
  return [
    for (final key in keys)
      MangaDay(date: DateTime.parse(key), key: key, items: days[key]!),
  ];
}
