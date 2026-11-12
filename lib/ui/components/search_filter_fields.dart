import 'package:material_ui/material_ui.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../state/search_filters.dart';

// ---------------------------------------------------------------------------
// Labels
// ---------------------------------------------------------------------------

/// "Fall (Oct-Dec)" style label for the season dropdown.
String seasonLabel(MediaSeason season) => switch (season) {
      MediaSeason.winter => 'Winter (Jan-Mar)',
      MediaSeason.spring => 'Spring (Apr-Jun)',
      MediaSeason.summer => 'Summer (Jul-Sep)',
      MediaSeason.fall => 'Fall (Oct-Dec)',
      MediaSeason.unknown => 'Unknown',
    };

/// Airing-flavoured wording of [MediaStatus] for anime.
String airingStatusLabel(MediaStatus status) => switch (status) {
      MediaStatus.finished => 'Finished Airing',
      MediaStatus.releasing => 'Currently Airing',
      MediaStatus.notYetReleased => 'Not Yet Aired',
      MediaStatus.cancelled => 'Cancelled',
      MediaStatus.hiatus => 'On Hiatus',
      MediaStatus.unknown => 'Unknown',
    };

/// Manga wording of [MediaStatus].
String publishingStatusLabel(MediaStatus status) => switch (status) {
      MediaStatus.finished => 'Finished',
      MediaStatus.releasing => 'Publishing',
      MediaStatus.notYetReleased => 'Not Yet Published',
      MediaStatus.cancelled => 'Cancelled',
      MediaStatus.hiatus => 'On Hiatus',
      MediaStatus.unknown => 'Unknown',
    };

/// Formats offered for manga.
const List<MediaFormat> kMangaFormats = [
  MediaFormat.manga,
  MediaFormat.novel,
  MediaFormat.oneShot,
];

String animeFormatLabel(MediaFormat format) =>
    format == MediaFormat.tv ? 'TV Series' : format.label;

/// "8.0+" for a score on AniList's 0-100 scale.
String scoreLabel(int score) => '${(score / 10).toStringAsFixed(1)}+';

/// Formats offered for anime.
const List<MediaFormat> kAnimeFormats = [
  MediaFormat.tv,
  MediaFormat.tvShort,
  MediaFormat.movie,
  MediaFormat.special,
  MediaFormat.ova,
  MediaFormat.ona,
  MediaFormat.music,
];

/// Years from next year back to 1940, newest first.
List<int> filterYears() {
  final latest = DateTime.now().year + 1;
  return List.generate(latest - 1940 + 1, (i) => latest - i);
}

/// One removable chip per active criterion, in display order.
List<({SearchFilterKey key, String label})> activeFilterChips(
  SearchFilters f, {
  bool manga = false,
}) {
  final season = f.season;
  final year = f.seasonYear;
  final seasonText = [
    if (season != null) season.label,
    if (year != null) '$year',
  ].join(' ');
  final from = f.yearFrom;
  final to = f.yearTo;
  return [
    if (f.genres.isNotEmpty)
      (key: SearchFilterKey.genres, label: 'Genre: ${f.genres.join(', ')}'),
    if (seasonText.isNotEmpty)
      (
        key: SearchFilterKey.season,
        label: season == null ? 'Year: $seasonText' : 'Season: $seasonText',
      ),
    if (f.format != null)
      (
        key: SearchFilterKey.format,
        label: 'Format: ${animeFormatLabel(f.format!)}',
      ),
    if (f.status != null)
      (
        key: SearchFilterKey.status,
        label:
            'Status: ${manga ? publishingStatusLabel(f.status!) : airingStatusLabel(f.status!)}',
      ),
    if (from != null || to != null)
      (
        key: SearchFilterKey.yearRange,
        label: from != null && to != null
            ? 'Years: $from–$to'
            : from != null
                ? 'From $from'
                : 'Until $to',
      ),
    if (f.minScore != null)
      (key: SearchFilterKey.minScore, label: 'Score: ${scoreLabel(f.minScore!)}'),
    if (f.source != null)
      (key: SearchFilterKey.source, label: 'Source: ${f.source!.label}'),
  ];
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// Small uppercase section label with an optional right-aligned hint,
/// e.g. "1. GENRES ........ 2 Selected".
class FilterLabel extends StatelessWidget {
  const FilterLabel(this.title, {this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Tokens.space8),
            Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Rounded, hairline-bordered shell shared by every filter control. The
/// border lights up in the accent colour while a value is set.
class FilterFieldBox extends StatelessWidget {
  const FilterFieldBox({
    required this.child,
    this.highlighted = false,
    this.onTap,
    this.padding = const EdgeInsets.only(left: 14, right: 8),
    super.key,
  });

  final Widget child;
  final bool highlighted;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Tokens.radiusMd + 2);
    return Material(
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: highlighted
              ? scheme.primary.withValues(alpha: 0.65)
              : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: padding,
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}

/// Dropdown with an "any" entry that clears the criterion.
class FilterSelect<T> extends StatelessWidget {
  const FilterSelect({
    required this.value,
    required this.anyLabel,
    required this.items,
    required this.onChanged,
    super.key,
  });

  final T? value;
  final String anyLabel;
  final List<({T value, String label})> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = items.any((item) => item.value == value);
    return FilterFieldBox(
      highlighted: value != null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: known ? value : null,
          isExpanded: true,
          menuMaxHeight: 320,
          borderRadius: BorderRadius.circular(Tokens.radiusMd),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text(
                anyLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            for (final item in items)
              DropdownMenuItem<T?>(
                value: item.value,
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

List<String> _toggled(List<String> selected, String genre) {
  final next = {...selected};
  if (!next.remove(genre)) next.add(genre);
  // Keep the canonical order so equal selections compare equal.
  return [
    for (final g in kGenres)
      if (next.contains(g)) g,
  ];
}

/// Multi-select genre chips ("Action ✓") for the mobile sheet.
class GenreChips extends StatelessWidget {
  const GenreChips({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: Tokens.space8,
      runSpacing: Tokens.space8,
      children: [
        for (final genre in kGenres)
          Builder(
            builder: (context) {
              final on = selected.contains(genre);
              return Semantics(
                button: true,
                selected: on,
                label: genre,
                excludeSemantics: true,
                onTap: () => onChanged(_toggled(selected, genre)),
                child: Material(
                  color: on
                      ? scheme.primary.withValues(alpha: 0.14)
                      : theme.scaffoldBackgroundColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusLg - 2),
                    side: BorderSide(
                      color: on ? scheme.primary : scheme.outlineVariant,
                      width: on ? 1.5 : 1,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onChanged(_toggled(selected, genre)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Text(
                        on ? '$genre ✓' : genre,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: on ? scheme.primary : scheme.onSurface,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Multi-select genre dropdown ("Action, Sci-Fi, Cyberpunk") for the desktop
/// panel. The menu stays open while several genres are ticked.
class GenreMenuField extends StatelessWidget {
  const GenreMenuField({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return MenuAnchor(
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, 320)),
          ),
          menuChildren: [
            for (final genre in kGenres)
              CheckboxMenuButton(
                value: selected.contains(genre),
                closeOnActivate: false,
                onChanged: (_) => onChanged(_toggled(selected, genre)),
                child: Text(genre),
              ),
          ],
          builder: (context, controller, child) => FilterFieldBox(
            highlighted: selected.isNotEmpty,
            onTap: () =>
                controller.isOpen ? controller.close() : controller.open(),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected.isEmpty ? 'Any genre' : selected.join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: selected.isEmpty
                        ? TextStyle(color: scheme.onSurfaceVariant)
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: Tokens.space4),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Minimum community score slider in half-point steps ("8.0+"). Zero means
/// no minimum.
class ScoreField extends StatelessWidget {
  const ScoreField({required this.value, required this.onChanged, super.key});

  /// Score on AniList's 0-100 scale, or null for "any".
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final points = ((value ?? 0) / 10).clamp(0.0, 9.5).toDouble();
    return FilterFieldBox(
      highlighted: value != null,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.star_border_rounded,
            size: 20,
            color: value == null ? scheme.onSurfaceVariant : Tokens.sun,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                activeTrackColor:
                    value == null ? Colors.transparent : scheme.primary,
                inactiveTrackColor: scheme.outlineVariant.withValues(
                  alpha: 0.6,
                ),
                thumbColor:
                    value == null ? scheme.onSurfaceVariant : scheme.primary,
                overlayColor: scheme.primary.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
              ),
              child: Slider(
                value: points,
                min: 0,
                max: 9.5,
                divisions: 19,
                semanticFormatterCallback: (v) =>
                    v <= 0 ? 'No minimum score' : '${v.toStringAsFixed(1)} or higher',
                onChanged: (v) {
                  final score = (v * 10).round();
                  onChanged(score <= 0 ? null : score);
                },
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              value == null ? 'None' : scoreLabel(value!),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "2018  to  2024" pair of year dropdowns.
class YearRangeField extends StatelessWidget {
  const YearRangeField({
    required this.from,
    required this.to,
    required this.onFromChanged,
    required this.onToChanged,
    super.key,
  });

  final int? from;
  final int? to;
  final ValueChanged<int?> onFromChanged;
  final ValueChanged<int?> onToChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final years = [
      for (final y in filterYears()) (value: y, label: '$y'),
    ];
    return Row(
      children: [
        Expanded(
          child: FilterSelect<int>(
            value: from,
            anyLabel: 'Any',
            items: years,
            onChanged: onFromChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space12),
          child: Text(
            'to',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: FilterSelect<int>(
            value: to,
            anyLabel: 'Any',
            items: years,
            onChanged: onToChanged,
          ),
        ),
      ],
    );
  }
}

/// Removable active-filter pill: "Genre: Action, Sci-Fi  ✕".
class ActiveFilterPill extends StatelessWidget {
  const ActiveFilterPill({
    required this.label,
    required this.onRemove,
    super.key,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: theme.cardColor,
      shape: StadiumBorder(side: BorderSide(color: theme.dividerColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRemove,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 10, top: 9, bottom: 9),
          // A pill like "Genre: Action, Comedy, Drama, ..." can be longer than
          // the screen: cap it at the viewport and ellipsise the text.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - 2 * Tokens.space16)
                  .clamp(120.0, double.infinity)
                  .toDouble(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: Tokens.space8),
                Semantics(
                  button: true,
                  label: 'Remove filter $label',
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: scheme.onSurfaceVariant,
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
