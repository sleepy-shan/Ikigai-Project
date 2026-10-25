import 'package:ikigai_project/data/models/media.dart';
import 'package:ikigai_project/data/models/media_entry.dart';
import 'package:ikigai_project/data/repositories/tracking_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A tiny in-memory stand-in is not needed: the local repository uses
/// SharedPreferences, whose test mock backs an in-memory map.
Future<LocalTrackingRepository> _repo() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return LocalTrackingRepository(prefs);
}

Media _media({
  int id = 1,
  MediaType type = MediaType.anime,
  int? episodes = 12,
}) {
  return Media(
    id: id,
    type: type,
    title: 'Title $id',
    coverUrl: 'https://example.test/$id.jpg',
    episodes: episodes,
    chapters: type == MediaType.manga ? (episodes ?? 10) : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalTrackingRepository', () {
    test('adds an entry and emits it on the stream', () async {
      final repo = await _repo();

      final events = <List<MediaEntry>>[];
      final subscription = repo.watchEntries().listen(events.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.first, isEmpty);

      await repo.addOrUpdate(media: _media(), status: ListStatus.planning);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.last, hasLength(1));
      expect(events.last.single.mediaId, 1);
      expect(events.last.single.title, 'Title 1');
      expect(events.last.single.status, ListStatus.planning);
      expect(events.last.single.progress, 0);

      await subscription.cancel();
    });

    test('updates an existing entry instead of duplicating it', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.planning);
      await repo.addOrUpdate(
        media: _media(),
        status: ListStatus.watching,
        progress: 3,
      );

      final entries = await repo.watchEntries().first;
      expect(entries, hasLength(1));
      expect(entries.single.status, ListStatus.watching);
      expect(entries.single.progress, 3);
    });

    test('setStatus marks completed entries with a completion date', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.planning);

      final entry = await repo.setStatus(1, ListStatus.completed);
      expect(entry.status, ListStatus.completed);
      // Total is known, so completion fills progress.
      expect(entry.progress, 12);
      expect(entry.completedAt, isNotNull);
    });

    test('setProgress clamps to the known total', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.watching);

      final tooHigh = await repo.setProgress(1, 99);
      expect(tooHigh.progress, 12);

      final back = await repo.setProgress(1, 4);
      expect(back.progress, 4);
    });

    test('incrementProgress completes the entry at the total', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.watching);

      var entry = await repo.setProgress(1, 11);
      expect(entry.progress, 11);
      entry = await repo.incrementProgress(1);
      expect(entry.progress, 12);
      expect(entry.status, ListStatus.completed);
      expect(entry.completedAt, isNotNull);
    });

    test('incrementProgress works when the total is unknown', () async {
      final repo = await _repo();
      await repo.addOrUpdate(
        media: _media(id: 5, episodes: null),
        status: ListStatus.watching,
      );
      final entry = await repo.incrementProgress(5);
      expect(entry.progress, 1);
      expect(entry.status, ListStatus.watching);
    });

    test('setScore clamps to 0-10', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.watching);

      expect((await repo.setScore(1, 8)).score, 8);
      expect((await repo.setScore(1, 42)).score, 10);
      expect((await repo.setScore(1, null)).score, isNull);
    });

    test('remove deletes the entry', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.watching);

      await repo.remove(1);
      final entries = await repo.watchEntries().first;
      expect(entries, isEmpty);
    });

    test('clear removes every entry', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(id: 1), status: ListStatus.watching);
      await repo.addOrUpdate(media: _media(id: 2), status: ListStatus.watching);

      await repo.clear();
      expect(await repo.watchEntries().first, isEmpty);
    });

    test('entryFor returns null for unknown ids', () async {
      final repo = await _repo();
      expect(await repo.entryFor(404), isNull);
    });

    test('manga entries use chapter units', () async {
      final repo = await _repo();
      final entry = await repo.addOrUpdate(
        media: _media(id: 9, type: MediaType.manga, episodes: 20),
        status: ListStatus.watching,
      );
      expect(entry.type, MediaType.manga);
      expect(entry.unit, 'chapter');
      expect(entry.totalUnits, 20);
      expect((await repo.setProgress(9, 3)).progress, 3);
    });
  });

  group('LocalTrackingRepository regressions', () {
    test('re-adding a tracked title keeps its progress and score', () async {
      final repo = await _repo();
      await repo.addOrUpdate(
        media: _media(),
        status: ListStatus.watching,
        progress: 5,
      );
      await repo.setScore(1, 9);

      final entry = await repo.addOrUpdate(
        media: _media(),
        status: ListStatus.watching,
      );
      expect(entry.progress, 5);
      expect(entry.score, 9);
    });

    test('restart on a completed title reopens it as watching', () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.completed);

      final entry = await repo.setProgress(1, 0);
      expect(entry.status, ListStatus.watching);
      expect(entry.completedAt, isNull);
    });

    test('explicit status change to watching is not forced back to completed',
        () async {
      final repo = await _repo();
      await repo.addOrUpdate(media: _media(), status: ListStatus.watching);
      await repo.setProgress(1, 12); // reaches total → completed
      final entry = await repo.setStatus(1, ListStatus.watching);
      expect(entry.status, ListStatus.watching);
      expect(entry.progress, 12);
    });

    test('incrementProgress keeps paused and dropped statuses', () async {
      final repo = await _repo();
      await repo.addOrUpdate(
        media: _media(id: 7, episodes: null),
        status: ListStatus.paused,
      );
      final entry = await repo.incrementProgress(7);
      expect(entry.status, ListStatus.paused);
      expect(entry.progress, 1);
    });

    test('an unreadable store is backed up before a write replaces it',
        () async {
      SharedPreferences.setMockInitialValues({
        'ikigai.tracking.v1': '[{"media_id": "not-a-valid-entry"',
      });
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalTrackingRepository(prefs);

      await repo.addOrUpdate(media: _media(), status: ListStatus.planning);

      expect(
        prefs.getString('ikigai.tracking.v1.corrupt-backup'),
        '[{"media_id": "not-a-valid-entry"',
      );
    });
  });
}
