import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/history_entry.dart';
import '../models/media.dart';

/// Recently opened titles, stored in this browser's localStorage.
///
/// Newest first, one row per title (re-opening moves it to the top), capped
/// at [maxEntries] so the store cannot grow without bound.
class LocalHistoryRepository {
  LocalHistoryRepository(this._prefs);

  static const String _storageKey = 'ikigai.history.v1';
  static const int maxEntries = 50;

  final SharedPreferences _prefs;

  List<HistoryEntry> readAll() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          ?HistoryEntry.tryFromJson(item),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Marks [media] as just opened and returns the updated list.
  Future<List<HistoryEntry>> record(Media media, {DateTime? now}) async {
    final entry = HistoryEntry.fromMedia(media, viewedAt: now);
    final next = [
      entry,
      for (final e in readAll())
        if (!(e.mediaId == entry.mediaId && e.type == entry.type)) e,
    ].take(maxEntries).toList();
    await _write(next);
    return next;
  }

  Future<List<HistoryEntry>> remove(int mediaId, MediaType type) async {
    final next = [
      for (final e in readAll())
        if (!(e.mediaId == mediaId && e.type == type)) e,
    ];
    await _write(next);
    return next;
  }

  Future<void> clear() => _prefs.remove(_storageKey);

  Future<void> _write(List<HistoryEntry> entries) {
    return _prefs.setString(
      _storageKey,
      jsonEncode([for (final e in entries) e.toJson()]),
    );
  }
}
