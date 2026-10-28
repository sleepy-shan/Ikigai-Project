import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/repositories/media_repository.dart';

const Object _keep = Object();

/// Returns a copy of [q] with the given filters replaced (pass `null` to clear
/// one, omit to keep it) and the page reset to 1.
///
/// [BrowseQuery.copyWith] mixes "null clears" and "null keeps" depending on
/// the field, so every filter UI goes through this one helper instead.
BrowseQuery editBrowseQuery(
  BrowseQuery q, {
  Object? genre = _keep,
  Object? status = _keep,
  Object? format = _keep,
  Object? season = _keep,
  Object? seasonYear = _keep,
  Object? source = _keep,
  Object? country = _keep,
  Object? minScore = _keep,
  bool? isAdult,
}) {
  return BrowseQuery(
    type: q.type,
    sort: q.sort,
    search: q.search,
    genre: identical(genre, _keep) ? q.genre : genre as String?,
    status: identical(status, _keep) ? q.status : status as MediaStatus?,
    format: identical(format, _keep) ? q.format : format as MediaFormat?,
    season: identical(season, _keep) ? q.season : season as MediaSeason?,
    seasonYear:
        identical(seasonYear, _keep) ? q.seasonYear : seasonYear as int?,
    source: identical(source, _keep) ? q.source : source as MediaSource?,
    countryOfOrigin:
        identical(country, _keep) ? q.countryOfOrigin : country as String?,
    minScore: identical(minScore, _keep) ? q.minScore : minScore as int?,
    isAdult: isAdult ?? q.isAdult,
    perPage: q.perPage,
  );
}

/// Same query with every filter removed (search and sort stay).
BrowseQuery resetBrowseFilters(BrowseQuery q) =>
    BrowseQuery(type: q.type, sort: q.sort, search: q.search);

String browseSortLabel(MediaSort sort) => switch (sort) {
      MediaSort.popularity => 'Popular',
      MediaSort.trending => 'Trending',
      MediaSort.score => 'Top rated',
      MediaSort.favourites => 'Favorites',
      MediaSort.startDate => 'Newest',
      MediaSort.updated => 'Updated',
      MediaSort.titleRomaji => 'A – Z',
    };

/// Every browse filter as grouped chips.
///
/// Stateless: the owner keeps the [BrowseQuery] and gets a new one through
/// [onChanged] on every tap. The desktop sidebar applies each change live,
/// the mobile sheet keeps a draft and applies it on "Show results".
class BrowseFilterForm extends StatelessWidget {
  const BrowseFilterForm({
    required this.query,
    required this.onChanged,
    super.key,
  });

  final BrowseQuery query;
  final ValueChanged<BrowseQuery> onChanged;

  bool get _isManga => query.type == MediaType.manga;

  @override
  Widget build(BuildContext context) {
    final formats = _isManga
        ? const [MediaFormat.manga, MediaFormat.novel, MediaFormat.oneShot]
        : const [
            MediaFormat.tv,
            MediaFormat.tvShort,
            MediaFormat.movie,
            MediaFormat.special,
            MediaFormat.ova,
            MediaFormat.ona,
            MediaFormat.music,
          ];
    final statuses =
        MediaStatus.values.where((s) => s != MediaStatus.unknown).toList();
    final seasons =
        MediaSeason.values.where((s) => s != MediaSeason.unknown).toList();
    final thisYear = DateTime.now().year;
    final years = List.generate(thisYear + 2 - 1970, (i) => thisYear + 1 - i);
    final genre =
        query.genre == null || query.genre!.isEmpty ? null : query.genre;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Section(
          title: 'Genre',
          child: _ChipGroup<String>(
            values: kGenres,
            selected: genre,
            label: (g) => g,
            collapsedCount: 10,
            onChanged: (g) => onChanged(editBrowseQuery(query, genre: g)),
          ),
        ),
        _Section(
          title: 'Format',
          child: _ChipGroup<MediaFormat>(
            values: formats,
            selected: query.format == MediaFormat.unknown ? null : query.format,
            label: (f) => f.label,
            onChanged: (f) => onChanged(editBrowseQuery(query, format: f)),
          ),
        ),
        _Section(
          title: 'Status',
          child: _ChipGroup<MediaStatus>(
            values: statuses,
            selected: query.status,
            label: (s) => s.label,
            onChanged: (s) => onChanged(editBrowseQuery(query, status: s)),
          ),
        ),
        _Section(
          title: 'Year',
          child: _Select<int>(
            allLabel: 'Any year',
            value: query.seasonYear,
            items: [
              for (final year in years)
                DropdownMenuItem(value: year, child: Text('$year')),
            ],
            onChanged: (y) => onChanged(editBrowseQuery(query, seasonYear: y)),
          ),
        ),
        _Section(
          title: 'Minimum score',
          child: _ChipGroup<int>(
            values: kScoreThresholds,
            selected: query.minScore,
            label: (s) => '${(s / 10).toStringAsFixed(1)}+',
            onChanged: (s) => onChanged(editBrowseQuery(query, minScore: s)),
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: Tokens.space8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: const Text('More filters'),
            children: [
        // AniList seasons only exist for anime.
        if (!_isManga)
          _Section(
            title: 'Season',
            child: _ChipGroup<MediaSeason>(
              values: seasons,
              selected: query.season,
              label: (s) => s.label,
              onChanged: (s) => onChanged(editBrowseQuery(query, season: s)),
            ),
          ),
        _Section(
          title: 'Country of origin',
          child: _ChipGroup<String>(
            values: kCountries.keys.toList(),
            selected: query.countryOfOrigin,
            label: (code) => kCountries[code] ?? code,
            onChanged: (c) => onChanged(editBrowseQuery(query, country: c)),
          ),
        ),
        _Section(
          title: 'Adapted from',
          child: _Select<MediaSource>(
            allLabel: 'Any source',
            value: query.source,
            items: [
              for (final source in MediaSource.values)
                DropdownMenuItem(value: source, child: Text(source.label)),
            ],
            onChanged: (s) => onChanged(editBrowseQuery(query, source: s)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Include adult (18+) titles'),
          value: query.isAdult,
          onChanged: (v) => onChanged(editBrowseQuery(query, isAdult: v)),
        ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: Tokens.space8),
          child,
        ],
      ),
    );
  }
}

/// Single-select chips. Tapping the selected chip clears it. When
/// [collapsedCount] is set, only that many chips show until "Show all"
/// (a selected chip beyond the cut-off is always kept visible).
class _ChipGroup<T> extends StatefulWidget {
  const _ChipGroup({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.collapsedCount,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) label;
  final ValueChanged<T?> onChanged;
  final int? collapsedCount;

  @override
  State<_ChipGroup<T>> createState() => _ChipGroupState<T>();
}

class _ChipGroupState<T> extends State<_ChipGroup<T>> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final limit = widget.collapsedCount;
    final collapsible = limit != null && widget.values.length > limit;
    final visible = !collapsible || _expanded
        ? widget.values
        : [
            for (var i = 0; i < widget.values.length; i++)
              if (i < limit || widget.values[i] == widget.selected)
                widget.values[i],
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Tokens.space8,
          runSpacing: Tokens.space8,
          children: [
            for (final value in visible)
              ChoiceChip(
                label: Text(widget.label(value)),
                selected: value == widget.selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (_) => widget.onChanged(
                  value == widget.selected ? null : value,
                ),
              ),
          ],
        ),
        if (collapsible)
          TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            ),
            child: Text(
              _expanded
                  ? 'Show less'
                  : 'Show all ${widget.values.length}',
            ),
          ),
      ],
    );
  }
}

/// Outlined dropdown with an "any" entry that clears the filter.
class _Select<T> extends StatelessWidget {
  const _Select({
    required this.allLabel,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String allLabel;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: Tokens.space12, right: Tokens.space8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border.all(
          color: hasValue ? scheme.primary : scheme.outlineVariant,
          width: hasValue ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: value,
          isExpanded: true,
          menuMaxHeight: 320,
          borderRadius: BorderRadius.circular(Tokens.radiusSm),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          items: [
            DropdownMenuItem<T?>(
              value: null,
              child: Text(
                allLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            for (final item in items)
              DropdownMenuItem<T?>(
                value: item.value,
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: item.child,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
