import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/data/models/media.dart';
import 'package:ikigai_project/data/repositories/media_repository.dart';
import 'package:ikigai_project/ui/components/browse_filters.dart';
import 'package:ikigai_project/ui/components/state_views.dart';

void main() {
  group('BrowseQuery new filters', () {
    test('defaults are safe-only with no extra filters', () {
      const q = BrowseQuery();
      expect(q.isAdult, isFalse);
      expect(q.source, isNull);
      expect(q.countryOfOrigin, isNull);
      expect(q.minScore, isNull);
      expect(q.hasFilters, isFalse);
    });

    test('each new filter counts as an active filter', () {
      expect(const BrowseQuery(source: MediaSource.manga).hasFilters, isTrue);
      expect(const BrowseQuery(countryOfOrigin: 'KR').hasFilters, isTrue);
      expect(const BrowseQuery(minScore: 75).hasFilters, isTrue);
      expect(const BrowseQuery(isAdult: true).hasFilters, isTrue);
    });

    test('copyWith keeps new filters when omitted and clears on null', () {
      const q = BrowseQuery(
        source: MediaSource.original,
        countryOfOrigin: 'JP',
        minScore: 80,
      );
      // Older setters call copyWith(clearFilters: true) without these.
      final kept = q.copyWith(page: 2, genre: 'Action', clearFilters: true);
      expect(kept.source, MediaSource.original);
      expect(kept.countryOfOrigin, 'JP');
      expect(kept.minScore, 80);

      final cleared = q.copyWith(source: null, countryOfOrigin: null);
      expect(cleared.source, isNull);
      expect(cleared.countryOfOrigin, isNull);
      expect(cleared.minScore, 80);
    });
  });

  group('browsePosterColumns', () {
    test('is one column denser than the default at every breakpoint', () {
      for (final width in [360.0, 700.0, 1000.0, 1300.0, 1600.0, 1900.0]) {
        expect(browsePosterColumns(width), posterColumns(width) + 1);
      }
    });
  });

  group('activeFilterCount / editBrowseQuery', () {
    test('counts filters but not search or sort', () {
      const q = BrowseQuery(
        search: 'naruto',
        sort: MediaSort.score,
        genre: 'Action',
        minScore: 80,
        isAdult: true,
      );
      expect(q.activeFilterCount, 3);
      expect(const BrowseQuery().activeFilterCount, 0);
    });

    test('editBrowseQuery sets, clears and keeps filters, resets page', () {
      const q = BrowseQuery(
        genre: 'Action',
        status: MediaStatus.finished,
        countryOfOrigin: 'JP',
        page: 4,
      );
      final changed = editBrowseQuery(q, genre: 'Drama');
      expect(changed.genre, 'Drama');
      expect(changed.status, MediaStatus.finished);
      expect(changed.countryOfOrigin, 'JP');
      expect(changed.page, 1);

      final cleared = editBrowseQuery(q, status: null, country: null);
      expect(cleared.status, isNull);
      expect(cleared.countryOfOrigin, isNull);
      expect(cleared.genre, 'Action');
    });

    test('resetBrowseFilters keeps search and sort only', () {
      const q = BrowseQuery(
        search: 'berserk',
        sort: MediaSort.popularity,
        genre: 'Horror',
        isAdult: true,
      );
      final reset = resetBrowseFilters(q);
      expect(reset.search, 'berserk');
      expect(reset.sort, MediaSort.popularity);
      expect(reset.hasFilters, isTrue); // search still counts for the chips
      expect(reset.activeFilterCount, 0);
    });
  });
}
