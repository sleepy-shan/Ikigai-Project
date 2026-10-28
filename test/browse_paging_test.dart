import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ikigai_project/data/anilist/anilist_client.dart';
import 'package:ikigai_project/data/models/media.dart';
import 'package:ikigai_project/data/repositories/media_repository.dart';
import 'package:ikigai_project/state/browse_controller.dart';
import 'package:ikigai_project/state/load_state.dart';
import 'package:ikigai_project/state/media_providers.dart';

/// 100 matches at 24 per page = 5 pages; ids are 1..100 in page order.
class _FakeRepository extends MediaRepository {
  _FakeRepository()
    : super(
        AniListClient(
          httpClient: MockClient((_) async => http.Response('{}', 200)),
          maxRetries: 0,
        ),
      );

  static const int total = 100;
  final List<int> requestedPages = [];

  @override
  Future<MediaPage> browse(BrowseQuery query) async {
    requestedPages.add(query.page);
    final first = (query.page - 1) * query.perPage;
    final items = <Media>[
      for (var i = first; i < total && i < first + query.perPage; i++)
        Media(
          id: i + 1,
          type: query.type,
          title: 'Title ${i + 1}',
          coverUrl: '',
        ),
    ];
    return MediaPage(
      items: items,
      page: query.page,
      hasNextPage: first + query.perPage < total,
      total: total,
    );
  }
}

void main() {
  group('BrowseState', () {
    test('pageCount comes from the total and page size', () {
      const s = BrowseState(
        query: BrowseQuery(perPage: 24),
        totalItems: 100,
        hasNextPage: true,
      );
      expect(s.pageCount, 5);
    });

    test('pageCount is never below what the paging flags prove', () {
      // Unknown total: at least the current page, plus one while there is more.
      expect(
        const BrowseState(
          query: BrowseQuery(page: 3),
          hasNextPage: true,
        ).pageCount,
        4,
      );
      expect(const BrowseState(query: BrowseQuery(page: 3)).pageCount, 3);
      // An understated total can't hide a next page.
      expect(
        const BrowseState(
          query: BrowseQuery(perPage: 24),
          totalItems: 24,
          hasNextPage: true,
        ).pageCount,
        2,
      );
      expect(const BrowseState(totalItems: 0).pageCount, 1);
    });

    test('activePreset is only set while the query matches the lineup', () {
      const untouched = BrowseState(
        preset: BrowsePreset.airing,
        query: BrowseQuery(
          sort: MediaSort.trending,
          status: MediaStatus.releasing,
        ),
      );
      expect(untouched.activePreset, BrowsePreset.airing);

      const withGenre = BrowseState(
        preset: BrowsePreset.airing,
        query: BrowseQuery(
          sort: MediaSort.trending,
          status: MediaStatus.releasing,
          genre: 'Action',
        ),
      );
      expect(withGenre.activePreset, isNull);

      const resorted = BrowseState(
        preset: BrowsePreset.airing,
        query: BrowseQuery(
          sort: MediaSort.score,
          status: MediaStatus.releasing,
        ),
      );
      expect(resorted.activePreset, isNull);

      expect(const BrowseState().activePreset, isNull);
    });
  });

  group('BrowseController paging', () {
    late _FakeRepository repo;
    late ProviderContainer container;
    final provider = browseControllerProvider(MediaType.anime);

    setUp(() async {
      repo = _FakeRepository();
      container = ProviderContainer(
        overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      container.listen(provider, (previous, next) {});
      await container.read(provider.notifier).load();
      // build() also schedules its own first load; let both settle.
      await pumpEventQueue();
    });

    BrowseController notifier() => container.read(provider.notifier);
    BrowseState state() => container.read(provider);

    test('starts on page 1 with one page of results', () {
      expect(state().status, LoadStatus.success);
      expect(state().currentPage, 1);
      expect(state().items.length, 24);
      expect(state().pageCount, 5);
    });

    test('goToPage replaces the results instead of appending', () async {
      await notifier().goToPage(3);
      expect(state().currentPage, 3);
      expect(state().items.length, 24);
      expect(state().items.first.id, 49);
      expect(state().items.last.id, 72);
      expect(state().hasNextPage, isTrue);

      await notifier().goToPage(5);
      expect(state().items.length, 4);
      expect(state().items.first.id, 97);
      expect(state().hasNextPage, isFalse);
    });

    test('going to the page already shown does not refetch', () async {
      await notifier().goToPage(2);
      final fetches = repo.requestedPages.length;
      await notifier().goToPage(2);
      expect(repo.requestedPages.length, fetches);
    });

    test('goToPage clamps to the first page', () async {
      await notifier().goToPage(2);
      await notifier().goToPage(0);
      expect(state().currentPage, 1);
      expect(state().items.first.id, 1);
    });

    test('a page past the end falls back to page 1', () async {
      await notifier().goToPage(9);
      expect(state().status, LoadStatus.success);
      expect(state().currentPage, 1);
      expect(state().items.length, 24);
    });

    test('changing sort or filters starts again from page 1', () async {
      await notifier().goToPage(4);
      await notifier().setSort(MediaSort.score);
      expect(state().currentPage, 1);

      await notifier().goToPage(3);
      await notifier().setGenre('Action');
      expect(state().currentPage, 1);
    });

    test('clearFilters returns to the active lineup, not a bare query', () async {
      await notifier().applyPreset(BrowsePreset.airing);
      await notifier().setGenre('Action');
      expect(state().activePreset, isNull);

      await notifier().clearFilters();
      expect(state().activePreset, BrowsePreset.airing);
      expect(state().query.genre, isNull);
      expect(state().query.status, MediaStatus.releasing);
    });

    test('showAll drops the lineup and every filter', () async {
      await notifier().applyPreset(BrowsePreset.topRated);
      await notifier().goToPage(2);
      await notifier().showAll();
      expect(state().preset, isNull);
      expect(state().currentPage, 1);
      expect(state().query.sort, MediaSort.trending);
      expect(state().query.hasFilters, isFalse);
    });
  });
}
