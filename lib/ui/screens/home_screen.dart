import 'package:flutter/material.dart';
import 'package:flutter_carousel_widget/flutter_carousel_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/theme/responsive.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/airing_schedule.dart';
import '../../data/models/media.dart';
import '../../data/models/media_entry.dart';
import '../../state/browse_controller.dart';
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
/// smooth scroll surface. The type toggle at the top swaps the entire
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

    return SmoothCustomScrollView(
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
          SliverToBoxAdapter(child: _ContinueRail(entries: continueEntries)),
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
              preset: BrowsePreset.airing,
            ),
          ),
          // ---- Trending now ---------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Trending now',
              subtitle: 'What AniList users are watching this week',
              eyebrow: 'Hot now',
              rail: MediaRail.trendingAnime,
              preset: BrowsePreset.trending,
            ),
          ),
          // ---- All-time popular -----------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'All-time popular',
              subtitle: 'The most-loved anime of all time',
              eyebrow: 'Legends',
              rail: MediaRail.allTimePopular,
              preset: BrowsePreset.popular,
            ),
          ),
          // ---- Top rated -------------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Top rated',
              subtitle: 'Highest scored anime by the community',
              eyebrow: 'Acclaimed',
              rail: MediaRail.topRated,
              preset: BrowsePreset.topRated,
            ),
          ),
          // ---- Upcoming ---------------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Upcoming',
              subtitle: 'Not yet released — plan what to watch next',
              eyebrow: 'Soon',
              rail: MediaRail.upcoming,
              preset: BrowsePreset.upcoming,
            ),
          ),
          // ---- Top completed ----------------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'Top completed series',
              subtitle: 'Finished favorites worth bingeing',
              eyebrow: 'Completed',
              rail: MediaRail.topCompleted,
              preset: BrowsePreset.topCompleted,
            ),
          ),
        ] else ...[
          // ---- New chapters ---------------------------------------------
          SliverToBoxAdapter(
            child: _RailSection(
              title: 'New chapters',
              subtitle: 'Recently updated manga with fresh chapters',
              eyebrow: 'Fresh',
              rail: MediaRail.newChapters,
              type: MediaType.manga,
              viewAllPath: Routes.calendarFor(MediaType.manga),
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
              preset: BrowsePreset.airing,
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
              preset: BrowsePreset.trending,
            ),
          ),
          // ---- All-time popular -----------------------------------------
          const SliverToBoxAdapter(
            child: _RailSection(
              title: 'All-time popular',
              subtitle: 'The most-loved manga of all time',
              eyebrow: 'Legends',
              rail: MediaRail.allTimePopular,
              type: MediaType.manga,
              preset: BrowsePreset.popular,
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
              preset: BrowsePreset.topRated,
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
              preset: BrowsePreset.upcoming,
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
              preset: BrowsePreset.topCompleted,
            ),
          ),
        ],
        // ---- Footer ------------------------------------------------------
        const SliverAppFooter(),
      ],
    );
  }
}

/// Anime / manga switcher for the home lineup: a dark bordered tray with a
/// raised, outlined selected segment marked by a dot in the primary colour.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});

  final MediaType type;
  final ValueChanged<MediaType> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space16,
        Tokens.space32,
        Tokens.space16,
        Tokens.space12,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToggleSegment(
                label: 'Anime',
                selected: type == MediaType.anime,
                onTap: () => onChanged(MediaType.anime),
              ),
              const SizedBox(width: Tokens.space4),
              _ToggleSegment(
                label: 'Manga',
                selected: type == MediaType.manga,
                onTap: () => onChanged(MediaType.manga),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
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
    final primary = theme.colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Tokens.durationFast,
          curve: Tokens.curveSmooth,
          constraints: const BoxConstraints(minWidth: 104, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surfaceContainerHigh
                : Colors.transparent,
            borderRadius: BorderRadius.circular(Tokens.radiusMd),
            border: Border.all(
              color: selected ? theme.dividerColor : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Tokens.space8),
              ],
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Spotlight carousel: the top trending titles as full-bleed banners with
/// gradient scrims, glass meta chips and CTA buttons, built on
/// `flutter_carousel_widget`.
///
/// Infinite loop, padded ends, the "rotate" effect, a wave
/// indicator below the cards and autoplay. The package owns the autoplay
/// timer, so it pauses on touch/hover, off-screen routes and reduced motion.
///
/// Shares the trending provider with the "Trending" rail below for the same
/// [type], so the carousel costs no extra network request.
class _SpotlightCarousel extends ConsumerWidget {
  const _SpotlightCarousel({required this.type, super.key});

  final MediaType type;

  static const slideCount = 5;
  static const height = 340.0;
  static const _autoAdvance = Duration(seconds: 6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingRail = type == MediaType.anime
        ? MediaRail.trendingAnime
        : MediaRail.trendingManga;
    final async = ref.watch(mediaRailProvider((trendingRail, type)));
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 840;
    return async.when(
      loading: () => const _CarouselLoading(),
      error: (e, s) => _CarouselError(
        onRetry: () => ref.invalidate(mediaRailProvider((trendingRail, type))),
      ),
      data: (page) {
        if (page.items.isEmpty) return const SizedBox.shrink();
        final slides = page.items.take(slideCount).toList();
        return FlutterCarousel.builder(
          height: height,
          itemCount: slides.length,
          // Pages are tight-sized so the banner image fills its slot.
          itemAlignment: null,
          itemBuilder: (context, index, pageIndex) =>
              _CarouselCard(media: slides[index], rank: index + 1),
          infinite: true,
          padEnds: true,
          // Peek the neighbours so the rotate effect is visible.
          viewportFraction: isWide ? 0.85 : 0.92,
          physics: SmoothScrollPhysics(),
          // TODO: apply rotate strength 1.10 once the parameter name is
          // confirmed from CarouselEffect.rotate's signature.

          effect: const CarouselEffect.rotate(),

          autoPlay: const CarouselAutoPlay(interval: _autoAdvance),
          indicator: CarouselIndicator(
            painter: CircularWaveIndicator(
              style: SlideIndicatorStyle(
                activeColor: theme.colorScheme.primary,
              ),
            ),
            placement: CarouselIndicatorPlacement.overlay,
          ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: SkeletonShimmer(
        child: SkeletonBone(
          height: _SpotlightCarousel.height,
          radius: Tokens.radiusXl,
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
          height: _SpotlightCarousel.height,
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
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
      // No RevealOnScroll here: inside a PageView recycled pages would
      // restart at opacity 0 + slide offset on every fast swipe, causing
      // ghosting / overlapping cards.
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.radiusXl),
          child: SizedBox(
            height: _SpotlightCarousel.height,
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
                            borderRadius: BorderRadius.circular(
                              Tokens.radiusLg,
                            ),
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
                                        color: Colors.white.withValues(
                                          alpha: 0.14,
                                        ),
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
                                            Formatters.score(
                                              media.averageScore,
                                            ),
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
                                style:
                                    (isWide
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
            actionLabel: 'View all',
            actionPath: '/calendar?tab=anime',
          ),
          LoadingAiringRail(
            height: _airingStripHeight,
            itemWidth: _airingCardWidth,
            coverHeight: _airingCoverHeight,
          ),
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
              actionLabel: 'View all',
              actionPath: Routes.calendarFor(MediaType.anime),
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

/// Cover height inside [_AiringTodayCard]; the loading skeleton reuses it.
const double _airingCoverHeight = 150;

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
      onTap: () => context.go(Routes.mediaDetail(item.mediaType, item.mediaId)),
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
                        height: _airingCoverHeight,
                        color: theme.disabledColor.withValues(alpha: 0.12),
                      )
                    : Image.network(
                        item.coverUrl!,
                        height: _airingCoverHeight,
                        width: _airingCardWidth,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stack) => Container(
                          height: _airingCoverHeight,
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

/// Inline rail that loads its own data and handles every state.
class _RailSection extends ConsumerWidget {
  const _RailSection({
    required this.title,
    required this.subtitle,
    required this.rail,
    this.preset,
    this.viewAllPath,
    this.type = MediaType.anime,
    this.eyebrow,
  }) : assert(
         preset != null || viewAllPath != null,
         'A rail needs a preset or an explicit View all path.',
       );

  final String title;
  final String subtitle;
  final MediaRail rail;

  /// Browse lineup the "View all" button opens (`/anime?rail=…`).
  final BrowsePreset? preset;

  /// Explicit destination overriding [preset] (e.g. the manga calendar).
  final String? viewAllPath;
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
          actionLabel: 'View all',
          actionPath: viewAllPath ?? Routes.browseRail(type, preset!),
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
                              color: theme.disabledColor.withValues(
                                alpha: 0.12,
                              ),
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
