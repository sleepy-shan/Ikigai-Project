import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';
import '../../data/models/media.dart';
import '../../data/repositories/media_repository.dart';

/// The filter values chosen in [FilterSheet].
class FilterSelection {
  const FilterSelection({
    this.genre,
    this.status,
    this.format,
    this.season,
    this.seasonYear,
    this.sort = MediaSort.trending,
  });

  final String? genre;
  final MediaStatus? status;
  final MediaFormat? format;
  final MediaSeason? season;
  final int? seasonYear;
  final MediaSort sort;
}

/// Modal bottom sheet holding browse/search filters.
///
/// Returns a [FilterSelection] when the user taps "Apply".
class FilterSheet extends StatefulWidget {
  const FilterSheet({required this.initial, super.key});

  final BrowseQuery initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  String? _genre;
  MediaStatus? _status;
  MediaFormat? _format;
  MediaSeason? _season;
  int? _year;
  late MediaSort _sort;

  /// Years from 1940 to next year.
  late final List<int> _years;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _genre = initial.genre;
    _status = initial.status;
    _format = initial.format == MediaFormat.unknown ? null : initial.format;
    _season = initial.season == MediaSeason.unknown ? null : initial.season;
    _year = initial.seasonYear;
    _sort = initial.sort;
    final thisYear = DateTime.now().year;
    _years = List.generate(thisYear + 1 - 1940, (i) => thisYear + 1 - i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isManga = widget.initial.type == MediaType.manga;
    final formats = isManga
        ? [MediaFormat.manga, MediaFormat.novel, MediaFormat.oneShot]
        : [
            MediaFormat.tv,
            MediaFormat.tvShort,
            MediaFormat.movie,
            MediaFormat.special,
            MediaFormat.ova,
            MediaFormat.ona,
            MediaFormat.music,
          ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Tokens.space24,
          Tokens.space8,
          Tokens.space24,
          Tokens.space24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Filters', style: theme.textTheme.headlineSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space12),
              Wrap(
                spacing: Tokens.space12,
                runSpacing: Tokens.space12,
                children: [
                  _Dropdown<String>(
                    label: 'Genre',
                    value: _genre,
                    items: kGenres,
                    onChanged: (value) => setState(() => _genre = value),
                    itemLabel: (value) => value,
                  ),
                  _Dropdown<MediaStatus>(
                    label: 'Status',
                    value: _status,
                    items: MediaStatus.values
                        .where((s) => s != MediaStatus.unknown)
                        .toList(),
                    onChanged: (value) => setState(() => _status = value),
                    itemLabel: (value) => value.label,
                  ),
                  _Dropdown<MediaFormat>(
                    label: 'Format',
                    value: _format,
                    items: formats,
                    onChanged: (value) => setState(() => _format = value),
                    itemLabel: (value) => value.label,
                  ),
                  _Dropdown<MediaSeason>(
                    label: 'Season',
                    value: _season,
                    items: MediaSeason.values
                        .where((s) => s != MediaSeason.unknown)
                        .toList(),
                    onChanged: (value) => setState(() => _season = value),
                    itemLabel: (value) => value.label,
                  ),
                  _Dropdown<int>(
                    label: 'Year',
                    value: _year,
                    items: _years,
                    onChanged: (value) => setState(() => _year = value),
                    itemLabel: (value) => '$value',
                  ),
                  _Dropdown<MediaSort>(
                    label: 'Sort by',
                    value: _sort,
                    items: MediaSort.browseOptions,
                    onChanged: (value) =>
                        setState(() => _sort = value ?? MediaSort.trending),
                    itemLabel: (value) => value.label,
                  ),
                ],
              ),
              const SizedBox(height: Tokens.space24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _genre = null;
                          _status = null;
                          _format = null;
                          _season = null;
                          _year = null;
                          _sort = MediaSort.trending;
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ),
                  const SizedBox(width: Tokens.space12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(
                          FilterSelection(
                            genre: _genre,
                            status: _status,
                            format: _format,
                            season: _season,
                            seasonYear: _year,
                            sort: _sort,
                          ),
                        );
                      },
                      child: const Text('Apply filters'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labelled dropdown used inside the filter sheet.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.itemLabel,
  });

  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T value) itemLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T>(
        initialValue: items.contains(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: Tokens.space12,
            vertical: Tokens.space8,
          ),
        ),
        items: [
          DropdownMenuItem<T>(value: null, child: Text('Any $label')),
          for (final item in items)
            DropdownMenuItem<T>(value: item, child: Text(itemLabel(item))),
        ],
        onChanged: onChanged,
      ),
    );
  }
}
