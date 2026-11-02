import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/design_tokens.dart';
import '../../core/utils/debouncer.dart';
import '../../data/models/media.dart';
import '../../state/search_controller.dart';
import '../../state/search_filters.dart';
import 'search_filter_fields.dart';

/// Where the editor is shown.
enum FiltersLayout {
  /// Inline "Refine Filters" card with a three-column grid (desktop).
  panel,

  /// Numbered sections in a bottom sheet (phone).
  sheet,
}

final NumberFormat _countFormat = NumberFormat('#,###');

/// Opens the Filters & Criteria bottom sheet for [tab] (anime or manga).
Future<void> showSearchFiltersSheet(BuildContext context, SearchTab tab) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(Tokens.radiusXl + 4),
      ),
    ),
    builder: (context) =>
        SearchFiltersEditor(tab: tab, layout: FiltersLayout.sheet),
  );
}

/// Edits the Anime (eight) or Manga (five) search criteria as a draft and
/// applies them all at once. The Apply button shows how many titles the draft would match.
class SearchFiltersEditor extends ConsumerStatefulWidget {
  const SearchFiltersEditor({
    required this.tab,
    required this.layout,
    super.key,
  });

  /// [SearchTab.anime] or [SearchTab.manga].
  final SearchTab tab;
  final FiltersLayout layout;

  @override
  ConsumerState<SearchFiltersEditor> createState() =>
      _SearchFiltersEditorState();
}

class _SearchFiltersEditorState extends ConsumerState<SearchFiltersEditor> {
  final Debouncer _countDebounce = Debouncer(
    duration: const Duration(milliseconds: 350),
  );
  late SearchFilters _draft;
  int? _count;
  int _countId = 0;

  bool get _isManga => widget.tab == SearchTab.manga;

  @override
  void initState() {
    super.initState();
    final state = ref.read(searchControllerProvider);
    _draft = state.filtersOf(widget.tab);
    _count = state.mediaPageOf(widget.tab).total;
    if (_count == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshCount();
      });
    }
  }

  @override
  void dispose() {
    _countDebounce.dispose();
    super.dispose();
  }

  void _set(SearchFilters next) {
    if (next == _draft) return;
    setState(() {
      _draft = next;
      _count = null;
    });
    _countDebounce.run(_refreshCount);
  }

  Future<void> _refreshCount() async {
    final id = ++_countId;
    final count = await ref
        .read(searchControllerProvider.notifier)
        .previewCount(widget.tab, _draft);
    if (!mounted || id != _countId) return;
    setState(() => _count = count);
  }

  void _apply() {
    ref
        .read(searchControllerProvider.notifier)
        .applyFilters(widget.tab, _draft);
    if (widget.layout == FiltersLayout.sheet) Navigator.of(context).pop();
  }

  void _reset() => _set(SearchFilters.none);

  void _setYearFrom(int? year) {
    var to = _draft.yearTo;
    if (year != null && to != null && year > to) to = year;
    _set(_draft.copyWith(yearFrom: year, yearTo: to));
  }

  void _setYearTo(int? year) {
    var from = _draft.yearFrom;
    if (year != null && from != null && year < from) from = year;
    _set(_draft.copyWith(yearFrom: from, yearTo: year));
  }

  // -- controls -------------------------------------------------------------

  Widget _seasonSelect() => FilterSelect<MediaSeason>(
        value: _draft.season,
        anyLabel: 'Any season',
        items: [
          for (final s in MediaSeason.values)
            if (s != MediaSeason.unknown) (value: s, label: seasonLabel(s)),
        ],
        onChanged: (s) => _set(_draft.copyWith(season: s)),
      );

  Widget _yearSelect() => FilterSelect<int>(
        value: _draft.seasonYear,
        anyLabel: 'Any year',
        items: [
          for (final y in filterYears()) (value: y, label: '$y'),
        ],
        onChanged: (y) => _set(_draft.copyWith(seasonYear: y)),
      );

  Widget _formatSelect() => FilterSelect<MediaFormat>(
        value: _draft.format,
        anyLabel: 'Any format',
        items: [
          for (final f in _isManga ? kMangaFormats : kAnimeFormats)
            (value: f, label: animeFormatLabel(f)),
        ],
        onChanged: (f) => _set(_draft.copyWith(format: f)),
      );

  Widget _statusSelect() => FilterSelect<MediaStatus>(
        value: _draft.status,
        anyLabel: 'Any status',
        items: [
          for (final s in MediaStatus.values)
            if (s != MediaStatus.unknown)
              (
                value: s,
                label: _isManga
                    ? publishingStatusLabel(s)
                    : airingStatusLabel(s),
              ),
        ],
        onChanged: (s) => _set(_draft.copyWith(status: s)),
      );

  Widget _sourceSelect() => FilterSelect<MediaSource>(
        value: _draft.source,
        anyLabel: 'Any source',
        items: [
          for (final s in MediaSource.values) (value: s, label: s.label),
        ],
        onChanged: (s) => _set(_draft.copyWith(source: s)),
      );

  Widget _rangeField() => YearRangeField(
        from: _draft.yearFrom,
        to: _draft.yearTo,
        onFromChanged: _setYearFrom,
        onToChanged: _setYearTo,
      );

  Widget _scoreField() => ScoreField(
        value: _draft.minScore,
        onChanged: (v) => _set(_draft.copyWith(minScore: v)),
      );

  String get _rangeHint {
    final from = _draft.yearFrom;
    final to = _draft.yearTo;
    if (from == null && to == null) return 'any';
    return '${from ?? 'any'} - ${to ?? 'any'}';
  }

  String get _applyLabel => _count == null
      ? 'Apply Filters'
      : 'Apply Filters (${_countFormat.format(_count)})';

  @override
  Widget build(BuildContext context) {
    // The applied filters can change behind the editor (a chip's ✕): follow
    // them so the open panel never shows stale values.
    ref.listen(searchControllerProvider.select((s) => s.filtersOf(widget.tab)), (
      _,
      next,
    ) {
      if (next == _draft || !mounted) return;
      setState(() {
        _draft = next;
        _count = null;
      });
      _countDebounce.run(_refreshCount);
    });
    return switch (widget.layout) {
      FiltersLayout.panel => _buildPanel(context),
      FiltersLayout.sheet => _buildSheet(context),
    };
  }

  // -- desktop panel --------------------------------------------------------

  Widget _buildPanel(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final genresCell = _Cell(
      'Genres',
      number: 1,
      trailing:
          _draft.genres.isEmpty ? 'any' : '${_draft.genres.length} selected',
      child: GenreMenuField(
        selected: _draft.genres,
        onChanged: (g) => _set(_draft.copyWith(genres: g)),
      ),
    );
    final formatTrailing = _draft.format == null
        ? 'any'
        : animeFormatLabel(_draft.format!).toUpperCase();
    final scoreCell = _Cell(
      'Min community score',
      number: 8,
      trailing: _draft.minScore == null
          ? 'any'
          : '${(_draft.minScore! / 10).toStringAsFixed(1)} / 10',
      child: _scoreField(),
    );
    final cells = <Widget>[
      if (_isManga) ...[
        genresCell,
        _Cell('Year', number: 2, trailing: 'specific', child: _yearSelect()),
        _Cell(
          'Format',
          number: 3,
          trailing: formatTrailing,
          child: _formatSelect(),
        ),
        _Cell(
          'Publishing status',
          number: 4,
          trailing: 'live & archive',
          child: _statusSelect(),
        ),
        _Cell(
          'Year range',
          number: 5,
          trailing: _rangeHint,
          child: _rangeField(),
        ),
      ] else ...[
        genresCell,
        _Cell(
          'Single year',
          number: 2,
          trailing: 'specific',
          child: _yearSelect(),
        ),
        _Cell(
          'Broadcast season',
          number: 3,
          trailing: _draft.season?.name ?? 'any',
          child: _seasonSelect(),
        ),
        _Cell(
          'Media format',
          number: 4,
          trailing: formatTrailing,
          child: _formatSelect(),
        ),
        _Cell(
          'Airing status',
          number: 5,
          trailing: 'live & archive',
          child: _statusSelect(),
        ),
        _Cell(
          'Year range span',
          number: 6,
          trailing: _rangeHint,
          child: _rangeField(),
        ),
        _Cell(
          'Original source',
          number: 7,
          trailing: 'original, manga, ln',
          child: _sourceSelect(),
        ),
        scoreCell,
      ],
    ];

    return Container(
      padding: const EdgeInsets.all(Tokens.space24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Refine Filters (${SearchFilters.criteriaFor(manga: _isManga)} Criteria)',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: Tokens.space12),
          Divider(height: 1, color: theme.dividerColor),
          const SizedBox(height: Tokens.space20),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = Tokens.space24;
              final width = constraints.maxWidth;
              final columns = width >= 820 ? 3 : (width >= 520 ? 2 : 1);
              final cellWidth = (width - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: Tokens.space20,
                children: [
                  for (final cell in cells)
                    SizedBox(width: cellWidth, child: cell),
                ],
              );
            },
          ),
          const SizedBox(height: Tokens.space24),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Tokens.space12,
            runSpacing: Tokens.space8,
            children: [
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset all filters'),
                style: TextButton.styleFrom(foregroundColor: scheme.primary),
              ),
              FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Tokens.radiusMd + 2),
                  ),
                ),
                child: Text(
                  _applyLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -- phone sheet ----------------------------------------------------------

  Widget _buildSheet(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final media = MediaQuery.sizeOf(context);
    final maxHeight = media.height * 0.94;
    // On very narrow phones the "8 options" pill squeezes the title away.
    final showOptionsPill = media.width >= 360;

    Widget section(
      int number,
      String title, {
      String? trailing,
      required Widget child,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Tokens.space20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilterLabel('$number. $title', trailing: trailing),
            child,
          ],
        ),
      );
    }

    Widget pair(Widget a, Widget b) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: a),
            const SizedBox(width: Tokens.space12),
            Expanded(child: b),
          ],
        );

    final seasonYear = [
      if (_draft.season != null) _draft.season!.label,
      if (_draft.seasonYear != null) '${_draft.seasonYear}',
    ].join(' ');

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Tokens.space12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.outlineVariant,
              borderRadius: BorderRadius.circular(Tokens.radiusPill),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space20,
              Tokens.space16,
              Tokens.space8,
              Tokens.space8,
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, color: scheme.onSurface),
                const SizedBox(width: Tokens.space12),
                Flexible(
                  child: Text(
                    'Filters & Criteria',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (showOptionsPill) ...[
                  const SizedBox(width: Tokens.space12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Tokens.radiusPill),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      '${SearchFilters.criteriaFor(manga: _isManga)} options',
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space20,
                Tokens.space8,
                Tokens.space20,
                Tokens.space8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section(
                    1,
                    'Genres',
                    trailing: _draft.genres.isEmpty
                        ? null
                        : '${_draft.genres.length} Selected',
                    child: GenreChips(
                      selected: _draft.genres,
                      onChanged: (g) => _set(_draft.copyWith(genres: g)),
                    ),
                  ),
                  if (_isManga) ...[
                    section(
                      2,
                      'Year',
                      trailing: _draft.seasonYear?.toString(),
                      child: _yearSelect(),
                    ),
                    section(3, 'Format', child: _formatSelect()),
                    section(4, 'Publishing Status', child: _statusSelect()),
                    section(
                      5,
                      'Year Range',
                      trailing: _draft.yearFrom == null && _draft.yearTo == null
                          ? null
                          : _rangeHint,
                      child: _rangeField(),
                    ),
                  ] else ...[
                    section(
                      2,
                      'Season & Year',
                      trailing: seasonYear.isEmpty ? null : seasonYear,
                      child: pair(_seasonSelect(), _yearSelect()),
                    ),
                    section(
                      3,
                      'Media Format & Status',
                      child: pair(_formatSelect(), _statusSelect()),
                    ),
                    section(
                      4,
                      'Year Range Span',
                      trailing: _draft.yearFrom == null && _draft.yearTo == null
                          ? null
                          : _rangeHint,
                      child: _rangeField(),
                    ),
                    section(
                      5,
                      'Minimum Score',
                      trailing: _draft.minScore == null
                          ? null
                          : '${(_draft.minScore! / 10).toStringAsFixed(1)} / 10.0',
                      child: _scoreField(),
                    ),
                    section(6, 'Original Source', child: _sourceSelect()),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space16,
              Tokens.space12,
              Tokens.space16,
              Tokens.space16,
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(foregroundColor: scheme.primary),
                ),
                const SizedBox(width: Tokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            _applyLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: Tokens.space8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One labelled cell of the desktop grid ("3. BROADCAST SEASON ... fall").
class _Cell extends StatelessWidget {
  const _Cell(
    this.title, {
    required this.number,
    required this.trailing,
    required this.child,
  });

  final String title;
  final int number;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterLabel('$number. $title', trailing: trailing),
        child,
      ],
    );
  }
}
