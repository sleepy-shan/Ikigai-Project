import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/data/models/history_entry.dart';
import 'package:ikigai_project/data/models/media.dart';
import 'package:ikigai_project/data/repositories/history_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalHistoryRepository> _repo([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return LocalHistoryRepository(prefs);
}

Media _media(int id, {MediaType type = MediaType.anime}) => Media(
  id: id,
  type: type,
  title: 'Title $id',
  coverUrl: 'https://example.test/$id.jpg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalHistoryRepository', () {
    test('starts empty', () async {
      final repo = await _repo();
      expect(repo.readAll(), isEmpty);
    });

    test('records newest first', () async {
      final repo = await _repo();
      await repo.record(_media(1));
      await repo.record(_media(2));

      expect(repo.readAll().map((e) => e.mediaId), [2, 1]);
    });

    test('re-opening a title moves it to the top without duplicating', () async {
      final repo = await _repo();
      await repo.record(_media(1));
      await repo.record(_media(2));
      await repo.record(_media(1));

      expect(repo.readAll().map((e) => e.mediaId), [1, 2]);
    });

    test('same id as anime and manga are separate rows', () async {
      final repo = await _repo();
      await repo.record(_media(7));
      await repo.record(_media(7, type: MediaType.manga));

      expect(repo.readAll(), hasLength(2));
    });

    test('keeps only the most recent entries', () async {
      final repo = await _repo();
      for (var i = 1; i <= LocalHistoryRepository.maxEntries + 5; i++) {
        await repo.record(_media(i));
      }

      final all = repo.readAll();
      expect(all, hasLength(LocalHistoryRepository.maxEntries));
      expect(all.first.mediaId, LocalHistoryRepository.maxEntries + 5);
    });

    test('removes one title and clears all', () async {
      final repo = await _repo();
      await repo.record(_media(1));
      await repo.record(_media(2));

      await repo.remove(1, MediaType.anime);
      expect(repo.readAll().map((e) => e.mediaId), [2]);

      await repo.clear();
      expect(repo.readAll(), isEmpty);
    });

    test('survives corrupt storage and skips bad rows', () async {
      final corrupt = await _repo({'ikigai.history.v1': '{not json'});
      expect(corrupt.readAll(), isEmpty);

      final partial = await _repo({
        'ikigai.history.v1':
            '[{"id":1,"type":"ANIME","title":"Ok","viewedAt":"2026-01-01T00:00:00.000"},'
            '{"id":"x"}, 5]',
      });
      expect(partial.readAll().map((e) => e.title), ['Ok']);
    });
  });

  group('HistoryEntry', () {
    test('round-trips through json', () {
      final entry = HistoryEntry.fromMedia(
        _media(3, type: MediaType.manga),
        viewedAt: DateTime(2026, 10, 27, 8),
      );
      final back = HistoryEntry.tryFromJson(entry.toJson())!;

      expect(back.mediaId, 3);
      expect(back.type, MediaType.manga);
      expect(back.title, 'Title 3');
      expect(back.coverUrl, 'https://example.test/3.jpg');
      expect(back.viewedAt, DateTime(2026, 10, 27, 8));
    });
  });
}
