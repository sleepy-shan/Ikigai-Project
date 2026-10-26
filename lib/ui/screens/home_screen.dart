import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/airing_schedule.dart';
import '../../data/models/media.dart';
import '../../data/models/media_entry.dart';
import '../../state/media_providers.dart';
import '../../state/my_lists_controller.dart';
import '../components/media_grid.dart';
import '../components/rails.dart';
import '../components/app_footer.dart';
import '../components/section_header.dart';
import '../components/state_views.dart';
import '../router/app_router.dart';

/// Dashboard: type toggle + spotlight carousel + continue rail + rails.
///
/// Uses a [CustomScrollView] with slivers so the whole page glides as one
/// smooth scroll surface. The [SegmentedButton] at the top swaps the entire
/// lineup between anime and manga.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  MediaType _type = MediaType.anime;

  @override
  Widget build(BuildContext context) {
    final continueEntries = ref.watch(continueWatchingProvider);
    final isAnime = _type == MediaType.anime;

    return CustomScrollView(
      physics: const SmoothScrollPhysics(),
      slivers: [
        // ---- Anime / manga toggle --------------------------------------
        SliverToBoxAdapter(
          child: _TypeToggle(
            type: _type,
            onChanged: (type) => setState(() => _type = type),
          ),
        ),
        // ---- Spotlight carousel --------------------------------------
        SliverToBoxAdapter(
          // Fresh carousel state (page, timer) per type.
          child: _SpotlightCarousel(key: ValueKey(_type), type: _type),
        ),
        // ---- Continue -----------------------------------------------
        if (continueEntries.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Continue watching / reading',
              subtitle: 'Jump back into what you were tracking',
              eyebrow: 'Pick up',
              actionLabel: 'Watchlist',
              actionPath: Routes.lists,
            ),
          ),
          SliverToBoxAdapter(
            child: _ContinueRail(entries: continueEntries),
          ),
        ],
        if (isAnime) ...[
          // ---- Releasing today ------------------------------------------
          const SliverToBoxAdapter(child: _AiringTodaySection()),
          // ---- Currently airing -----------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Currently airing',
              subtitle: 'Shows airing right now this season',
              eyebrow: 'On air',
              rail: MediaRail.airingNow,
              seeAllPath: Routes.anime,
            ),
          ),
          // ---- Trending now ---------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Trending now',
              subtitle: 'What AniList users are watching this week',
              eyebrow: 'Hot now',
              rail: MediaRail.trendingAnime,
              seeAllPath: Routes.anime,
            ),
          ),
          // ---- Genre quick-jump (unique strip) -------------------------
          const SliverToBoxAdapter(child: _GenreStrip()),
          // ---- All-time popular -----------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'All-time popular',
              subtitle: 'The most-loved anime of all time',
              eyebrow: 'Legends',
              rail: MediaRail.allTimePopular,
              seeAllPath: Routes.anime,
            ),
          ),
          // ---- Top rated -------------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Top rated',
              subtitle: 'Highest scored anime by the community',
              eyebrow: 'Acclaimed',
              rail: MediaRail.topRated,
              seeAllPath: Routes.anime,
            ),
          ),
          // ---- Upcoming ---------------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Upcoming',
              subtitle: 'Not yet released — plan what to watch next',
              eyebrow: 'Soon',
              rail: MediaRail.upcoming,
              seeAllPath: Routes.anime,
            ),
          ),
          // ---- Top completed ----------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Top completed series',
              subtitle: 'Finished favorites worth bingeing',
              eyebrow: 'Completed',
              rail: MediaRail.topCompleted,
              seeAllPath: Routes.anime,
            ),
          ),
        ] else ...[
          // ---- New chapters ---------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'New chapters',
              subtitle: 'Recently updated manga with fresh chapters',
              eyebrow: 'Fresh',
              rail: MediaRail.newChapters,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
          // ---- Currently publishing --------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Currently publishing',
              subtitle: 'Ongoing manga with new chapters on the way',
              eyebrow: 'Publishing',
              rail: MediaRail.airingNow,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
          // ---- Trending now ---------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Trending manga',
              subtitle: 'What AniList users are reading this week',
              eyebrow: 'Hot now',
              rail: MediaRail.trendingManga,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
          // ---- Genre quick-jump (unique strip) -------------------------
          const SliverToBoxAdapter(child: _GenreStrip()),
          // ---- All-time popular -----------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'All-time popular',
              subtitle: 'The most-loved manga of all time',
              eyebrow: 'Legends',
              rail: MediaRail.allTimePopular,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
          // ---- Top rated -------------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Top rated',
              subtitle: 'Highest scored manga by the community',
              eyebrow: 'Acclaimed',
              rail: MediaRail.topRated,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
          // ---- Upcoming ---------------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Upcoming',
              subtitle: 'Not yet released — plan what to read next',
              eyebrow: 'Soon',
              rail: MediaRail.upcoming,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
          // ---- Top completed ----------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Top completed series',
              subtitle: 'Finished favorites worth reading in full',
              eyebrow: 'Completed',
              rail: MediaRail.topCompleted,
              type: MediaType.manga,
              seeAllPath: Routes.manga,
            ),
          ),
        ],
        // ---- Footer ------------------------------------------------------
        const SliverAppFooter(),
      ],
    );
  }
}

/// Anime / manga switcher for the home lineup.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});

  final MediaType type;
  final ValueChanged<MediaType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space16,
        Tokens.space16,
        Tokens.space4,
      ),
      child: Center(
        child: SegmentedButton<MediaType>(
          segments: const [
            ButtonSegment(
              value: MediaType.anime,
              label: Text('Anime'),
              icon: Icon(Icons.movie_outlined, size: 18),
            ),
            ButtonSegment(
              value: MediaType.manga,
              label: Text('Manga'),
              icon: Icon(Icons.menu_book_outlined, size: 18),
            ),
          ],
          selected: {type},
          onSelectionChanged: (selection) => onChanged(selection.first),
          showSelectedIcon: false,
        ),
      ),
    );
  }
}

/// Auto-advancing spotlight carousel: the top trending titles as full-bleed
/// banners with gradient scrims, glass meta chips and CTA buttons.
///
/// Shares the trending provider with the "Trending" rail below for the same
/// [type], so the carousel costs no extra network request.
class _SpotlightCarousel extends ConsumerStatefulWidget {
  const _SpotlightCarousel({required this.type, super.key});

  final MediaType type;

  @override
  ConsumerState<_SpotlightCarousel> createState() =>
      _SpotlightCarouselState();
}

class _SpotlightCarouselState extends ConsumerState<_SpotlightCarousel> {
  static const slideCount = 5;
  static const height = 340.0;
  static const _autoAdvance = Duration(seconds: 6);

  late final PageController _pages;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pages = PageController();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _ensureTimer(int count) {
    if (_timer != null || count < 2) return;
    _timer = Timer.periodic(_autoAdvance, (_) {
      if (!mounted || !_pages.hasClients) return;
      // Don't fight the user: skip auto-advance while dragging/scrolling.
      try {
        if (_pages.position.isScrollingNotifier.value) return;
      } catch (_) {}
      _pages.animateToPage(
        (_index + 1) % count,
        duration: Tokens.durationMedium,
        curve: Tokens.curveSmooth,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final trendingRail = widget.type == MediaType.anime
        ? MediaRail.trendingAnime
        : MediaRail.trendingManga;
    final async = ref.watch(mediaRailProvider((trendingRail, widget.type)));
    return async.when(
      loading: () => const _CarouselLoading(),
      error: (e, s) => _CarouselError(
        onRetry: () =>
            ref.invalidate(mediaRailProvider((trendingRail, widget.type))),
      ),
      data: (page) {
        if (page.items.isEmpty) return const SizedBox.shrink();
        final slides = page.items.take(slideCount).toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureTimer(slides.length);
        });
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: PageView.builder(
                controller: _pages,
                itemCount: slides.length,
                // Clamping: no bounce-back / back-and-forth on fast swipes,
                // hard edge so neighbour pages never bleed through.
                physics: const ClampingScrollPhysics(),
                clipBehavior: Clip.hardEdge,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _CarouselCard(media: slides[i], rank: i + 1),
              ),
            ),
            const SizedBox(height: Tokens.space8),
            _CarouselDots(
              count: slides.length,
              index: _index,
              onTap: (i) => _pages.animateToPage(
                i,
                duration: Tokens.durationMedium,
                curve: Tokens.curveSmooth,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fixed-height loading block matching the carousel so slides swap in
/// without a layout jump.
class _CarouselLoading extends StatelessWidget {
  const _CarouselLoading();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.radiusXl),
        child: Container(
          height: _SpotlightCarouselState.height,
          color: theme.disabledColor.withValues(alpha: 0.10),
          child: const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fixed-height error block matching the carousel, with a retry action.
class _CarouselError extends StatelessWidget {
  const _CarouselError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Tokens.radiusXl),
        child: Container(
          height: _SpotlightCarouselState.height,
          color: Theme.of(context).disabledColor.withValues(alpha: 0.10),
          child: Center(
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry spotlight'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable page dots under the carousel.
class _CarouselDots extends StatelessWidget {
  const _CarouselDots({
    required this.count,
    required this.index,
    required this.onTap,
  });

  final int count;
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: Tokens.durationFast,
              curve: Tokens.curveSmooth,
              width: i == index ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i == index
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                borderRadius: BorderRadius.circular(Tokens.radiusPill),
              ),
            ),
          ),
      ],
    );
  }
}

class _CarouselCard extends StatelessWidget {
  const _CarouselCard({required this.media, required this.rank});

  final Media media;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 840;
    final bg = media.bannerUrl?.isNotEmpty == true
        ? media.bannerUrl!
        : media.coverUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      // No RevealOnScroll here: inside a PageView recycled pages would
      // restart at opacity 0 + slide offset on every fast swipe, causing
      // ghosting / overlapping cards.
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.radiusXl),
          child: SizedBox(
            height: _SpotlightCarouselState.height,
            width: double.infinity,
            child: Stack(
              children: [
              // Backdrop.
              if (bg.isNotEmpty)
                Positioned.fill(
                  child: Image.network(
                    bg,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      decoration: const BoxDecoration(
                        gradient: Tokens.heroGradient,
                      ),
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: Tokens.heroGradient,
                    ),
                  ),
                ),
              // Scrims.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.82),
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.05),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Tokens.brand.withValues(alpha: 0.22),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              // Content (bottom-anchored so every slide is the same height).
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.all(isWide ? 32 : 20),
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isWide) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Tokens.radiusLg),
                        child: media.coverUrl.isEmpty
                            ? const SizedBox(width: 150, height: 215)
                            : Image.network(
                                media.coverUrl,
                                width: 150,
                                height: 215,
                                fit: BoxFit.cover,
                              ),
                      ),
                      const SizedBox(width: 24),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Wrap so badges never clip on 320px phones.
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  gradient: Tokens.brandGradient,
                                  borderRadius: BorderRadius.circular(
                                    Tokens.radiusPill,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'SPOTLIGHT #$rank • TRENDING',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        shadows: [
                                          Shadow(
                                            blurRadius: 8,
                                            color: Color(0x88000000),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (media.averageScore != null &&
                                  media.averageScore! > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(
                                      Tokens.radiusPill,
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: Tokens.warning,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        Formatters.score(media.averageScore),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          shadows: [
                                            Shadow(
                                              blurRadius: 8,
                                              color: Color(0x88000000),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            media.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: (isWide
                                    ? theme.textTheme.displaySmall
                                    : theme.textTheme.headlineMedium)
                                ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              height: 1.1,
                              shadows: const [
                                Shadow(
                                  blurRadius: 12,
                                  color: Color(0x99000000),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (media.genres.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final g in media.genres.take(3))
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        Tokens.radiusPill,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      g,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _HeroButton(
                                label: 'View details',
                                icon: Icons.play_arrow_rounded,
                                filled: true,
                                onTap: () => context.go(
                                  Routes.mediaDetail(media.type, media.id),
                                ),
                              ),
                              _HeroButton(
                                label: 'Browse anime',
                                icon: Icons.explore_outlined,
                                filled: false,
                                onTap: () => context.go(Routes.anime),
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
            ],
          ),
        ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Container(
        decoration: BoxDecoration(
          gradient: Tokens.brandGradient,
          borderRadius: BorderRadius.circular(Tokens.radiusPill),
          boxShadow: Tokens.glowShadow(Theme.of(context).colorScheme.primary),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(Tokens.radiusPill),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
        backgroundColor: Colors.white.withValues(alpha: 0.08),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

/// Episodes airing today, from the AniList airing schedule.
///
/// Loading shows skeletons; error and empty hide the section entirely —
/// the full schedule lives on the calendar page.
class _AiringTodaySection extends ConsumerWidget {
  const _AiringTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(airingTodayProvider);
    return async.when(
      loading: () => const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Releasing today',
            subtitle: 'New episodes dropping throughout the day',
            eyebrow: 'Today',
          ),
          LoadingRail(height: _airingStripHeight, itemWidth: _airingCardWidth),
        ],
      ),
      error: (e, s) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: 'Releasing today',
              subtitle:
                  '${items.length} episode${items.length == 1 ? '' : 's'} dropping throughout the day',
              eyebrow: 'Today',
              actionLabel: 'Calendar',
              actionPath: Routes.calendar,
            ),
            ArrowRail(
              height: _airingStripHeight,
              itemCount: items.length,
              separatorWidth: Tokens.railGap,
              itemExtent: _airingCardWidth + Tokens.railGap,
              itemBuilder: (context, index) => SizedBox(
                width: _airingCardWidth,
                child: _AiringTodayCard(item: items[index]),
              ),
            ),
          ],
        );
      },
    );
  }
}

const double _airingCardWidth = 124;
const double _airingStripHeight = 212;

/// Compact episode card for the "Releasing today" strip.
class _AiringTodayCard extends StatelessWidget {
  const _AiringTodayCard({required this.item});

  final AiringScheduleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 12-hour clock, e.g. "8:00 PM".
    final time = Formatters.clockTime(
      DateTime.fromMillisecondsSinceEpoch(item.airingAt * 1000),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(Tokens.radiusLg),
      onTap: () =>
          context.go(Routes.mediaDetail(item.mediaType, item.mediaId)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Tokens.radiusLg),
                child: item.coverUrl == null || item.coverUrl!.isEmpty
                    ? Container(
                        height: 150,
                        color: theme.disabledColor.withValues(alpha: 0.12),
                      )
                    : Image.network(
                        item.coverUrl!,
                        height: 150,
                        width: _airingCardWidth,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stack) => Container(
                          height: 150,
                          color: theme.disabledColor.withValues(alpha: 0.12),
                        ),
                      ),
              ),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: Tokens.brandGradient,
                    borderRadius: BorderRadius.circular(Tokens.radiusPill),
                  ),
                  child: Text(
                    'EP ${item.episode}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Tokens.space8),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Row(
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$time • ${Formatters.timeUntil(item.airingAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quick genre jump strip — short static content, so `StaticStrip`
/// (`SingleChildScrollView + Row`) instead of a virtualized viewport.
class _GenreStrip extends StatelessWidget {
  const _GenreStrip();

  static const _genres = [
    ('Action', Icons.bolt_outlined),
    ('Romance', Icons.favorite_outline),
    ('Fantasy', Icons.auto_awesome_outlined),
    ('Sci-Fi', Icons.rocket_launch_outlined),
    ('Comedy', Icons.sentiment_satisfied_alt_outlined),
    ('Drama', Icons.theater_comedy_outlined),
    ('Horror', Icons.dark_mode_outlined),
    ('Sports', Icons.sports_soccer_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Browse by vibe',
          subtitle: 'Pick a genre to jump into browse with a filter',
          eyebrow: 'Genres',
        ),
        StaticStrip(
          height: 44,
          children: [
            for (var i = 0; i < _genres.length; i++)
              Builder(
                builder: (context) {
                  final (label, icon) = _genres[i];
                  return ActionChip(
                    avatar: Icon(
                      icon,
                      size: 16,
                      color: theme.colorScheme.onSurface,
                    ),
                    label: Text(
                      label,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    onPressed: () => context.go(Routes.searchWith(label)),
                  );
                },
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space16),
          child: Text(
            'Tip: drag, swipe, or use the arrows — rails glide with smooth physics.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline rail that loads its own data and handles every state.
class _RailSection extends ConsumerWidget {
  const _RailSection({
    required this.title,
    required this.subtitle,
    required this.rail,
    required this.seeAllPath,
    this.type = MediaType.anime,
    this.eyebrow,
  });

  final String title;
  final String subtitle;
  final MediaRail rail;
  final String seeAllPath;
  final MediaType type;
  final String? eyebrow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mediaRailProvider((rail, type)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          eyebrow: eyebrow,
          actionLabel: 'See all',
          actionPath: seeAllPath,
        ),
        SizedBox(
          height: 252,
          child: async.when(
            loading: () => const LoadingRail(),
            error: (error, stack) => _RailError(
              onRetry: () => ref.invalidate(mediaRailProvider((rail, type))),
            ),
            data: (page) {
              if (page.items.isEmpty) {
                return const EmptyView(
                  message: 'No titles available right now.',
                  icon: Icons.movie_filter_outlined,
                );
              }
              return MediaRailList(items: page.items);
            },
          ),
        ),
      ],
    );
  }
}

class _RailError extends StatelessWidget {
  const _RailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: Tokens.space8),
          Text(
            "Couldn't load titles. AniList may be rate-limiting.",
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// "Continue" rail: entry poster + progress + a one-tap increment.
///
/// Virtualized [ArrowRail] with fixed extent (300 + [Tokens.railGap]) + arrows.
class _ContinueRail extends ConsumerWidget {
  const _ContinueRail({required this.entries});

  final List<MediaEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow phones get a slimmer card so 320px viewports still peek next.
    final cardWidth = context.isPhone ? 260.0 : 300.0;
    return ArrowRail(
      height: 148,
      itemCount: entries.length,
      separatorWidth: Tokens.railGap,
      itemExtent: cardWidth + Tokens.railGap,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return SizedBox(
          width: cardWidth,
          child: RepaintBoundary(child: _ContinueCard(entry: entry)),
        );
      },
    );
  }
}

class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry});

  final MediaEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final fraction = entry.fraction;
    const width = 300.0;
    return SizedBox(
      width: width,
      child: HoverLift(
        lift: 0,
        scale: 1.0,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(Tokens.space12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusMd),
                  child: SizedBox(
                    width: 58,
                    height: 86,
                    child: entry.coverUrl == null || entry.coverUrl!.isEmpty
                        ? ColoredBox(
                            color: theme.disabledColor.withValues(alpha: 0.12),
                          )
                        : Image.network(
                            entry.coverUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) => ColoredBox(
                              color: theme.disabledColor.withValues(alpha: 0.12),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: Tokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: Tokens.brandGradient,
                          borderRadius: BorderRadius.circular(
                            Tokens.radiusPill,
                          ),
                        ),
                        child: Text(
                          entry.status.label.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: Tokens.space4),
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: Tokens.space2),
                      Text(
                        '${entry.progress}'
                        '${entry.totalUnits != null ? '/${entry.totalUnits}' : ''}'
                        ' ${entry.unit}s',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (fraction != null) ...[
                        const SizedBox(height: Tokens.space8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            Tokens.radiusPill,
                          ),
                          child: LinearProgressIndicator(
                            value: fraction,
                            minHeight: 5,
                            backgroundColor: theme.dividerColor,
                            valueColor: AlwaysStoppedAnimation(
                              theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Tokens.space8),
                Container(
                  decoration: BoxDecoration(
                    gradient: Tokens.brandGradient,
                    shape: BoxShape.circle,
                    boxShadow: Tokens.glowShadow(theme.colorScheme.primary),
                  ),
                  child: IconButton.filledTonal(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                    ),
                    tooltip: 'Mark one more ${entry.unit} watched',
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () async {
                      await ref
                          .read(myListsControllerProvider.notifier)
                          .incrementProgress(entry.mediaId);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
