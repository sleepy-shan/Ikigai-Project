import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_scroll.dart';
import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media.dart';
import '../router/app_router.dart';

/// Standard poster card used in every grid — now with hover lift,
/// gradient scrim, and glass badges for a more premium feel.
///
/// Performance: the artwork is isolated in a [RepaintBoundary] and the
/// image uses `gaplessPlayback` so hover animations and rebuilds do not
/// flicker or re-decode. A [Hero] on the cover gives a smooth shared
/// transition into the detail page.
class PosterCard extends StatelessWidget {
  const PosterCard({required this.media, this.width, super.key});

  final Media media;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: HoverLift(
        lift: 5,
        scale: 1.02,
        glow: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          onTap: () => context.go(Routes.mediaDetail(media.type, media.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _PosterImage(media: media)),
              const SizedBox(height: Tokens.space12),
              Text(
                media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: Tokens.space4),
              Text(
                _subtitle(media),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(Media media) {
    final bits = <String>[
      media.format != MediaFormat.unknown
          ? media.format.label
          : media.type.label,
      if (media.seasonYear != null) '${media.seasonYear}',
    ];
    return bits.join(' • ');
  }
}

/// Poster artwork with graceful handling for missing/broken images.
class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = media.coverUrl;
    if (url.isEmpty) {
      return _PosterPlaceholder(media: media);
    }
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          boxShadow: Tokens.cardShadow(theme.brightness),
          border: Border.all(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.09)
                : const Color(0xFFE3E4EC),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Tokens.radiusLg - 1),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'media-cover-${media.id}',
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return ColoredBox(
                      color: theme.disabledColor.withValues(alpha: 0.12),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stack) =>
                      _PosterPlaceholder(media: media),
                ),
              ),
            // Bottom gradient scrim for legibility + premium depth.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.28),
                    ],
                    stops: const [0.0, 0.62, 1.0],
                  ),
                ),
              ),
            ),
            if (media.averageScore != null && media.averageScore! > 0)
              Positioned(
                left: Tokens.space8,
                top: Tokens.space8,
                child: _ScoreBadge(score: media.averageScore!),
              ),
            if (media.nextAiringEpisode != null)
              Positioned(
                right: Tokens.space8,
                bottom: Tokens.space8,
                child: _AiringBadge(
                  episode: media.nextAiringEpisode!.episode,
                  airingAt: media.nextAiringEpisode!.airingAt,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.22),
            theme.colorScheme.secondary.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_not_supported_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Tokens.space4),
              Text(
                media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 13, color: Tokens.warning),
          const SizedBox(width: Tokens.space4),
          Text(
            Formatters.score(score),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiringBadge extends StatelessWidget {
  const _AiringBadge({required this.episode, required this.airingAt});

  final int episode;
  final int airingAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space8,
        vertical: Tokens.space4,
      ),
      decoration: BoxDecoration(
        gradient: Tokens.brandGradient,
        borderRadius: BorderRadius.circular(Tokens.radiusPill),
        boxShadow: Tokens.glowShadow(Theme.of(context).colorScheme.primary),
      ),
      child: Text(
        'EP $episode • ${Formatters.timeUntil(airingAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Horizontal rail card (bigger artwork, used on the home dashboard).
class MediaRailCard extends StatelessWidget {
  const MediaRailCard({required this.media, this.width = 148, super.key});

  final Media media;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: HoverLift(
        // No lift/scale on rails: scaling beyond the 148px extent makes
        // neighbours overlap during fast horizontal scrolls.
        lift: 0,
        scale: 1.0,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          onTap: () => context.go(Routes.mediaDetail(media.type, media.id)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _PosterImage(media: media)),
              const SizedBox(height: Tokens.space12),
              Text(
                media.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Tokens.space2),
              Text(
                PosterCard._subtitle(media),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
