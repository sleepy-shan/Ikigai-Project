import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/media.dart';
import '../router/app_router.dart';

// Text metrics shared by the card and the grid that sizes it. The grid gives
// every card an exact height (poster + text block), so the two must agree.
const double _titleSize = 13.5;
const double _titleLineHeight = 1.25;
const double _metaSize = 11.5;
const double _metaLineHeight = 1.3;
const double _textGapTop = 10;
const double _textGapMid = 3;

/// Height of the two reserved title lines at the current text scale.
///
/// The scaler is applied to the font size first and the line height after,
/// which is how text is laid out (matters for non-linear font scaling).
double _titleBlockHeight(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(_titleSize) * _titleLineHeight * 2;

/// Height of the text block under a poster at the current text scale:
/// two reserved title lines plus one meta line.
///
/// Reserving both title lines keeps the meta rows aligned across a grid row
/// whether a title wraps or not.
double browseCardTextHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return _textGapTop +
      _titleBlockHeight(context) +
      _textGapMid +
      scaler.scale(_metaSize) * _metaLineHeight +
      1; // slack for sub-pixel rounding
}

/// Poster card for the Anime/Manga browse grid.
///
/// Artwork first: the score sits top-left, a live status (Airing / Soon)
/// top-right, and the episode or chapter count on a soft scrim at the bottom.
/// Below it a two-line title and one muted meta line (format · year).
/// On hover the artwork zooms slightly and the card picks up an accent glow.
class BrowseCard extends StatefulWidget {
  const BrowseCard({required this.media, super.key});

  final Media media;

  @override
  State<BrowseCard> createState() => _BrowseCardState();
}

class _BrowseCardState extends State<BrowseCard> {
  bool _active = false; // hovered or keyboard-focused

  void _setActive(bool value) {
    if (value != _active) setState(() => _active = value);
  }

  Media get _media => widget.media;

  int? get _year {
    final fromSeason = _media.seasonYear;
    if (fromSeason != null) return fromSeason;
    final date = _media.startDate;
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  String get _meta {
    final year = _year;
    return [
      _media.format != MediaFormat.unknown
          ? _media.format.label
          : _media.type.label,
      if (year != null) '$year',
    ].join(' · ');
  }

  String? get _count {
    final m = _media;
    if (m.type == MediaType.anime) {
      final n = m.episodes;
      if (n == null || n <= 0) return null;
      return n == 1 ? '1 ep' : '$n eps';
    }
    final chapters = m.chapters;
    if (chapters != null && chapters > 0) return '$chapters ch';
    final volumes = m.volumes;
    if (volumes != null && volumes > 0) {
      return volumes == 1 ? '1 vol' : '$volumes vols';
    }
    return null;
  }

  ({String label, Color color})? get _liveStatus {
    switch (_media.status) {
      case MediaStatus.releasing:
        return (
          label: _media.type == MediaType.manga ? 'Ongoing' : 'Airing',
          color: Tokens.success,
        );
      case MediaStatus.notYetReleased:
        return (label: 'Soon', color: Tokens.sun);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Tokens.radiusLg);
    final score = _media.averageScore;
    final count = _count;
    final live = _liveStatus;

    return Semantics(
      button: true,
      label: _media.title,
      child: InkWell(
        borderRadius: radius,
        onHover: _setActive,
        onFocusChange: _setActive,
        onTap: () => context.go(Routes.mediaDetail(_media.type, _media.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: Tokens.durationMedium,
                curve: Tokens.curveSmooth,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: _active
                        ? scheme.primary.withValues(alpha: 0.75)
                        : scheme.outlineVariant,
                  ),
                  boxShadow: _active
                      ? [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.28),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : const [],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg - 1),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedScale(
                        scale: _active ? 1.06 : 1.0,
                        duration: Tokens.durationSlow,
                        curve: Tokens.curveSmooth,
                        child: _Cover(media: _media),
                      ),
                      if (count != null)
                        const Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0xB8000000)],
                              ),
                            ),
                          ),
                        ),
                      if (score != null && score > 0)
                        Positioned(
                          top: Tokens.space8,
                          left: Tokens.space8,
                          child: _ScoreBadge(label: Formatters.score(score)),
                        ),
                      if (live != null)
                        Positioned(
                          top: Tokens.space8,
                          right: Tokens.space8,
                          child: _StatusPill(
                            label: live.label,
                            color: live.color,
                          ),
                        ),
                      if (count != null)
                        Positioned(
                          left: Tokens.space8,
                          right: Tokens.space8,
                          bottom: Tokens.space8,
                          child: _CountLabel(
                            icon: _media.type == MediaType.anime
                                ? Icons.play_circle_rounded
                                : Icons.auto_stories_rounded,
                            label: count,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              height: browseCardTextHeight(context),
              child: Padding(
                padding: const EdgeInsets.only(top: _textGapTop),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _titleBlockHeight(context),
                      child: Text(
                        _media.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontSize: _titleSize,
                          fontWeight: FontWeight.w700,
                          height: _titleLineHeight,
                          color: _active ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: _textGapMid),
                    Text(
                      _meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: _metaSize,
                        height: _metaLineHeight,
                        color: scheme.onSurfaceVariant,
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

/// Glass-dark chip used for every badge on top of artwork, so text stays
/// readable on any cover.
class _BadgeShell extends StatelessWidget {
  const _BadgeShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(Tokens.radiusMd - 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: child,
      ),
    );
  }
}

const TextStyle _badgeText = TextStyle(
  color: Colors.white,
  fontSize: 11.5,
  fontWeight: FontWeight.w700,
  height: 1.15,
);

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _BadgeShell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 14, color: Tokens.sun),
          const SizedBox(width: 3),
          Text(label, style: _badgeText),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _BadgeShell(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const SizedBox(width: 6, height: 6),
          ),
          const SizedBox(width: 5),
          Text(label, style: _badgeText.copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }
}

class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _badgeText.copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.media});

  final Media media;

  @override
  Widget build(BuildContext context) {
    final url = media.coverUrl;
    if (url.isEmpty) return _CoverPlaceholder(type: media.type);
    return Hero(
      tag: 'media-cover-${media.id}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Decode at card size, not full size: less memory while paging.
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth * dpr).ceil().clamp(120, 640).toInt()
              : null;
          return Image.network(
            url,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            frameBuilder: (context, child, frame, wasSyncLoaded) {
              if (wasSyncLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: Tokens.durationMedium,
                curve: Curves.easeOut,
                child: child,
              );
            },
            errorBuilder: (context, error, stack) =>
                _CoverPlaceholder(type: media.type),
          );
        },
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.type});

  final MediaType type;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Center(
        child: Icon(
          type == MediaType.manga
              ? Icons.menu_book_rounded
              : Icons.movie_rounded,
          size: 32,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
