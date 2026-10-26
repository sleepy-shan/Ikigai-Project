import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/history_entry.dart';
import '../data/models/media.dart';
import '../data/repositories/history_repository.dart';
import 'providers.dart';

final historyRepositoryProvider = Provider<LocalHistoryRepository>((ref) {
  return LocalHistoryRepository(ref.watch(sharedPreferencesProvider));
});

/// Recently opened titles, newest first.
class HistoryController extends Notifier<List<HistoryEntry>> {
  LocalHistoryRepository get _repo => ref.read(historyRepositoryProvider);

  @override
  List<HistoryEntry> build() => _repo.readAll();

  Future<void> record(Media media) async {
    state = await _repo.record(media);
  }

  Future<void> remove(HistoryEntry entry) async {
    state = await _repo.remove(entry.mediaId, entry.type);
  }

  Future<void> clear() async {
    await _repo.clear();
    state = const [];
  }
}

final historyControllerProvider =
    NotifierProvider<HistoryController, List<HistoryEntry>>(
      HistoryController.new,
    );
