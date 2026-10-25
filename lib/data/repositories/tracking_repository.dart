import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_exception.dart';
import '../models/media.dart';
import '../models/media_entry.dart';

/// Common contract for the tracking backend.
///
/// AniList is the account backend (login/identity). The tracking list itself
/// is stored locally in this browser via [LocalTrackingRepository]; adding
/// direct AniList list sync later means adding another implementation of this
/// interface, not rewriting screens.
///
/// Keeping this interface small means a new integration can be added
/// without touching UI code.
abstract interface class TrackingRepository {
  /// Streams the user's entries; emits on every mutation.
  Stream<List<MediaEntry>> watchEntries();

  /// Adds a title to the list (or updates it when already tracked).
  ///
  /// For a tracked title, a null [progress] or [score] keeps the stored value.
  /// Returns the resulting entry.
  Future<MediaEntry> addOrUpdate({
    required Media media,
    required ListStatus status,
    int? progress,
    int? score,
    String? notes,
  });

  /// Updates only the status of an existing entry.
  Future<MediaEntry> setStatus(int mediaId, ListStatus status);

  /// Updates progress by an absolute amount.
  Future<MediaEntry> setProgress(int mediaId, int progress);

  /// Increments progress by one unit (e.g. "watched next episode").
  Future<MediaEntry> incrementProgress(int mediaId);

  /// Updates the score (0-10 scale; null clears it).
  Future<MediaEntry> setScore(int mediaId, int? score);

  /// Removes a title from the list entirely.
  Future<void> remove(int mediaId);

  /// Removes every tracked title.
  Future<void> clear();

  /// The user's entry for [mediaId], or null when untracked.
  Future<MediaEntry?> entryFor(int mediaId);
}

/// Storage-backed tracking store.
///
/// Data lives in the browser's localStorage, which is appropriate for
/// preferences and personal list state only — never for tokens or private
/// credentials (the AniList OAuth token is stored under its own key and
/// only ever sent to AniList itself).
class LocalTrackingRepository implements TrackingRepository {
  LocalTrackingRepository(this._prefs);

  static const String _storageKey = 'ikigai.tracking.v1';
  static const String _legacyStorageKey = 'sandwich.tracking.v1';

  /// Where an unreadable store is preserved before a write replaces it.
  static const String _corruptBackupKey = 'ikigai.tracking.v1.corrupt-backup';

  final SharedPreferences _prefs;
  final _controller = StreamController<List<MediaEntry>>.broadcast();

  @override
  Stream<List<MediaEntry>> watchEntries() async* {
    // Emit the current snapshot first so listeners always get an initial
    // value, then every subsequent mutation.
    yield _readAll();
    yield* _controller.stream;
  }

  /// Adds a title, or updates it when it is already tracked.
  ///
  /// For an existing entry, [progress] and [score] are only changed when the
  /// caller supplies them. Previously an omitted progress reset the entry to
  /// 0 and an omitted score erased the rating.
  @override
  Future<MediaEntry> addOrUpdate({
    required Media media,
    required ListStatus status,
    int? progress,
    int? score,
    String? notes,
  }) async {
    final entries = _readAll();
    final now = DateTime.now();
    final index = entries.indexWhere(
      (e) => e.mediaId == media.id && e.type == media.type,
    );

    final MediaEntry entry;
    if (index >= 0) {
      final existing = entries[index];
      final base = existing.copyWith(
        title: media.title,
        coverUrl: media.coverUrl.isEmpty ? existing.coverUrl : media.coverUrl,
        totalUnits: media.totalUnits,
        score: score == null ? existing.score : _clampScore(score),
        notes: notes ?? existing.notes,
        updatedAt: now,
      );
      entry = _withStatus(
        base,
        status,
        progress: progress ?? existing.progress,
        now: now,
      );
      entries[index] = entry;
    } else {
      final total = media.totalUnits;
      final startProgress = progress == null
          ? 0
          : (total == null ? progress : progress.clamp(0, total).toInt());
      final draft = MediaEntry(
        mediaId: media.id,
        type: media.type,
        title: media.title,
        coverUrl: media.coverUrl,
        totalUnits: total,
        status: status,
        progress: startProgress,
        score: score == null ? null : _clampScore(score),
        notes: notes,
        startedAt: now,
        completedAt: null,
        createdAt: now,
        updatedAt: now,
      );
      entry = _withStatus(draft, status, progress: startProgress, now: now);
      entries.add(entry);
    }

    await _writeAll(entries);
    return entry;
  }

  @override
  Future<MediaEntry> setStatus(int mediaId, ListStatus status) async {
    return _mutate(mediaId, (entry) {
      final now = DateTime.now();
      return _withStatus(
        entry.copyWith(updatedAt: now),
        status,
        progress: entry.progress,
        now: now,
      );
    });
  }

  @override
  Future<MediaEntry> setProgress(int mediaId, int progress) async {
    return _mutate(mediaId, (entry) {
      final now = DateTime.now();
      return _withStatus(
        entry.copyWith(updatedAt: now),
        entry.status,
        progress: _clampProgress(progress, entry.totalUnits),
        now: now,
        fromProgressChange: true,
      );
    });
  }

  @override
  Future<MediaEntry> incrementProgress(int mediaId) async {
    return _mutate(mediaId, (entry) {
      final now = DateTime.now();
      final next = _clampProgress(entry.progress + 1, entry.totalUnits);
      return _withStatus(
        entry.copyWith(updatedAt: now),
        entry.status,
        progress: next,
        now: now,
        fromProgressChange: true,
      );
    });
  }

  @override
  Future<MediaEntry> setScore(int mediaId, int? score) async {
    return _mutate(mediaId, (entry) {
      return entry.copyWith(
        score: score == null ? null : _clampScore(score),
        updatedAt: DateTime.now(),
      );
    });
  }

  @override
  Future<void> remove(int mediaId) async {
    final entries = _readAll()..removeWhere((e) => e.mediaId == mediaId);
    await _writeAll(entries);
  }

  @override
  Future<void> clear() => _writeAll(const []);

  @override
  Future<MediaEntry?> entryFor(int mediaId) async {
    final entries = _readAll();
    final index = entries.indexWhere((e) => e.mediaId == mediaId);
    return index >= 0 ? entries[index] : null;
  }

  // ---------------------------------------------------------------------------
  // Status and progress rules (single place, so every mutation agrees).
  // ---------------------------------------------------------------------------

  static int _clampScore(int score) => score.clamp(0, 10).toInt();

  static int _clampProgress(int progress, int? total) {
    final floor = progress < 0 ? 0 : progress;
    if (total == null) return floor;
    return floor > total ? total : floor;
  }

  /// Applies [status] and [progress] together and keeps the dates consistent.
  ///
  /// Progress changes ([fromProgressChange]) drive the status:
  /// * Reaching a known total completes the entry.
  /// * Dropping below the total of a completed entry reopens it as watching
  ///   (this is what "restart" relies on).
  /// * Progress above zero moves a planned entry to watching.
  ///
  /// Explicit status changes are applied as requested. Completing an entry
  /// fills its progress to the known total.
  static MediaEntry _withStatus(
    MediaEntry entry,
    ListStatus requested, {
    required int progress,
    required DateTime now,
    bool fromProgressChange = false,
  }) {
    final total = entry.totalUnits;
    final ListStatus status;
    if (fromProgressChange) {
      final reached = total != null && progress >= total;
      if (reached) {
        status = ListStatus.completed;
      } else if (entry.status == ListStatus.completed && total != null) {
        status = ListStatus.watching;
      } else if (entry.status == ListStatus.planning && progress > 0) {
        status = ListStatus.watching;
      } else {
        status = entry.status;
      }
    } else {
      status = requested;
    }

    final isCompleted = status == ListStatus.completed;
    final effectiveProgress = isCompleted && total != null ? total : progress;

    return entry.copyWith(
      status: status,
      progress: effectiveProgress,
      startedAt: entry.startedAt ?? (effectiveProgress > 0 ? now : null),
      completedAt: isCompleted ? (entry.completedAt ?? now) : null,
    );
  }

  Future<MediaEntry> _mutate(
    int mediaId,
    MediaEntry Function(MediaEntry entry) transform,
  ) async {
    final entries = _readAll();
    final index = entries.indexWhere((e) => e.mediaId == mediaId);
    if (index < 0) {
      throw const AppException(
        ErrorKind.notFound,
        'That title is not on your list',
      );
    }
    final updated = transform(entries[index]);
    entries[index] = updated;
    await _writeAll(entries);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Persistence.
  // ---------------------------------------------------------------------------

  /// Parses the stored JSON. Returns null when anything in it is unreadable,
  /// so callers can tell "empty" apart from "corrupt".
  static List<MediaEntry>? _parseStrict(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return [
        for (final item in decoded)
          MediaEntry.fromJson(item as Map<String, dynamic>),
      ];
    } on Object {
      return null;
    }
  }

  String? _storedRaw() {
    final raw =
        _prefs.getString(_storageKey) ?? _prefs.getString(_legacyStorageKey);
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  List<MediaEntry> _readAll() {
    final raw = _storedRaw();
    if (raw == null) return [];
    return _parseStrict(raw) ?? [];
  }

  Future<void> _writeAll(List<MediaEntry> entries) async {
    // Before replacing the stored list, keep a copy of anything that could
    // not be read. Previously an unreadable store was treated as empty and
    // the next add or remove silently overwrote it.
    final raw = _storedRaw();
    if (raw != null && _parseStrict(raw) == null) {
      await _prefs.setString(_corruptBackupKey, raw);
    }

    final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
    final ok = await _prefs.setString(_storageKey, encoded);
    if (!ok) {
      throw const AppException(ErrorKind.storage, 'Could not persist entries');
    }
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_readAll());
  }

  void dispose() => _controller.close();
}
