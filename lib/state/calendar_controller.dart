import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/app_exception.dart';
import '../data/models/airing_schedule.dart';
import '../data/models/media.dart';
import '../data/repositories/media_repository.dart';
import 'load_state.dart';
import 'media_providers.dart';
import 'providers.dart';

/// Which section of the release calendar is visible.
///
/// AniList only provides an hourly airing schedule for anime. Manga has no
/// episode times, so it gets its own tab grouped by `startDate` (date-only).
enum CalendarTab { anime, manga }

/// How the selected day's anime episodes are ordered.
enum CalendarSort {
  airTime('Air Time'),
  popularity('Popularity'),
  countdown('Countdown');

  const CalendarSort(this.label);

  final String label;
}

/// Time zone the schedule is shown in: it decides which day an episode
/// lands on, the week boundaries and the clock times on the cards.
///
/// Only zones without daylight saving are offered as fixed offsets, so their
/// UTC offset never drifts; [device] follows the device (including DST).
enum CalendarZone {
  device('Local', null),
  utc('UTC', Duration.zero),
  jst('JST', Duration(hours: 9)),
  sgt('SGT', Duration(hours: 8)),
  ist('IST', Duration(hours: 5, minutes: 30));

  const CalendarZone(this.code, this.fixedOffset);

  final String code;

  /// Null for [device].
  final Duration? fixedOffset;

  Duration get offset => fixedOffset ?? DateTime.now().timeZoneOffset;

  /// "UTC+9", "UTC+5:30", "UTC".
  String get offsetLabel {
    final total = offset.inMinutes;
    if (total == 0) return 'UTC';
    final sign = total < 0 ? '-' : '+';
    final hours = total.abs() ~/ 60;
    final minutes = total.abs() % 60;
    return 'UTC$sign$hours${minutes == 0 ? '' : ':${minutes.toString().padLeft(2, '0')}'}';
  }

  /// "JST (UTC+9)"; the device zone reads "Local (UTC+8)".
  String get label => this == utc ? 'UTC' : '$code ($offsetLabel)';

  /// Wall-clock reading of an instant in this zone. Only the date/time
  /// *fields* are meaningful (format them or read `.day`); never compare the
  /// result against a normal `DateTime`.
  DateTime wall(int epochSeconds) {
    final ms = epochSeconds * 1000;
    final fixed = fixedOffset;
    if (fixed == null) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(fixed);
  }

  DateTime get wallNow => wall(DateTime.now().millisecondsSinceEpoch ~/ 1000);

  /// Epoch seconds of 00:00 on the given calendar date in this zone.
  int epochOfMidnight(int year, int month, int day) {
    final fixed = fixedOffset;
    if (fixed == null) {
      return DateTime(year, month, day).millisecondsSinceEpoch ~/ 1000;
    }
    return (DateTime.utc(year, month, day).millisecondsSinceEpoch -
            fixed.inMilliseconds) ~/
        1000;
  }
}

/// Monday of the week [weekOffset] weeks from now, as a date-only value
/// (read `.year/.month/.day`) in [zone].
///
/// Calendar arithmetic (not Duration) so DST changes cannot shift the day.
DateTime calendarWeekStart(CalendarZone zone, int weekOffset) {
  final now = zone.wallNow;
  return DateTime(
    now.year,
    now.month,
    now.day - (now.weekday - 1) + 7 * weekOffset,
  );
}

/// Airing calendar state: anime episodes grouped by day plus manga releases
/// grouped by start date are derived in the UI from [items]/[mangaItems].
class CalendarState {
  const CalendarState({
    this.status = LoadStatus.initial,
    this.items = const [],
    this.mangaStatus = LoadStatus.initial,
    this.mangaItems = const [],
    this.tab = CalendarTab.anime,
    this.weekOffset = 0,
    this.zone = CalendarZone.device,
    this.sort = CalendarSort.airTime,
    this.errorMessage,
    this.mangaErrorMessage,
  });

  final LoadStatus status;

  /// The airing episodes for the selected week, ordered by time.
  final List<AiringScheduleItem> items;

  final LoadStatus mangaStatus;

  /// Manga with a `startDate` inside the selected week, ordered by date.
  final List<Media> mangaItems;

  final CalendarTab tab;

  /// 0 = current week, 1 = next week, ...
  final int weekOffset;

  final CalendarZone zone;
  final CalendarSort sort;
  final String? errorMessage;
  final String? mangaErrorMessage;

  CalendarState copyWith({
    LoadStatus? status,
    List<AiringScheduleItem>? items,
    LoadStatus? mangaStatus,
    List<Media>? mangaItems,
    CalendarTab? tab,
    int? weekOffset,
    CalendarZone? zone,
    CalendarSort? sort,
    Object? errorMessage = _keep,
    Object? mangaErrorMessage = _keep,
  }) {
    return CalendarState(
      status: status ?? this.status,
      items: items ?? this.items,
      mangaStatus: mangaStatus ?? this.mangaStatus,
      mangaItems: mangaItems ?? this.mangaItems,
      tab: tab ?? this.tab,
      weekOffset: weekOffset ?? this.weekOffset,
      zone: zone ?? this.zone,
      sort: sort ?? this.sort,
      errorMessage: errorMessage == _keep
          ? this.errorMessage
          : errorMessage as String?,
      mangaErrorMessage: mangaErrorMessage == _keep
          ? this.mangaErrorMessage
          : mangaErrorMessage as String?,
    );
  }

  static const Object _keep = Object();
}

/// Loads the airing schedule for the selected week from AniList.
///
/// Smart state: a monotonic [_loadId] discards out-of-order responses when
/// the user taps prev/next rapidly. While reloading, previous [items] are
/// kept so the list does not flash empty (keep-previous-data).
class CalendarController extends Notifier<CalendarState> {
  MediaRepository get _repo => ref.read(mediaRepositoryProvider);

  // Independent monotonic ids: the anime and manga loads run concurrently, and
  // each must only discard *its own* superseded responses.
  int _loadId = 0;
  int _mangaLoadId = 0;

  static const _zoneKey = 'ikigai.calendar.zone';

  @override
  CalendarState build() {
    final stored = ref.read(sharedPreferencesProvider).getString(_zoneKey);
    final zone = CalendarZone.values.firstWhere(
      (z) => z.name == stored,
      orElse: () => CalendarZone.device,
    );
    Future.microtask(load);
    return CalendarState(zone: zone);
  }

  /// Monday of the selected week (date-only) in the chosen time zone.
  DateTime get _weekStart => calendarWeekStart(state.zone, state.weekOffset);

  /// Exclusive end of the selected week (next Monday, date-only).
  DateTime get _weekEnd {
    final start = _weekStart;
    return DateTime(start.year, start.month, start.day + 7);
  }

  void setTab(CalendarTab tab) {
    if (state.tab == tab) return;
    state = state.copyWith(tab: tab);
    // Lazily load manga the first time its tab is opened.
    if (tab == CalendarTab.manga &&
        state.mangaStatus == LoadStatus.initial &&
        state.mangaItems.isEmpty) {
      loadManga();
    }
  }

  void setSort(CalendarSort sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }

  /// Switches the display zone and reloads: week boundaries move with it.
  Future<void> setZone(CalendarZone zone) async {
    if (state.zone == zone) return;
    state = state.copyWith(zone: zone);
    await ref.read(sharedPreferencesProvider).setString(_zoneKey, zone.name);
    await load();
  }

  Future<void> load() async {
    await Future.wait([loadAnime(), loadManga()]);
  }

  Future<void> loadAnime() async {
    final id = ++_loadId;
    state = state.copyWith(status: LoadStatus.loading, errorMessage: null);
    try {
      final start = _weekStart;
      final end = _weekEnd;
      final zone = state.zone;
      // The whole week, not just the first page: a real week has hundreds
      // of episodes.
      final items = await _repo.airingScheduleAll(
        from: zone.epochOfMidnight(start.year, start.month, start.day),
        to: zone.epochOfMidnight(end.year, end.month, end.day),
      );
      if (id != _loadId) return;
      state = state.copyWith(
        status: LoadStatus.success,
        items: items,
        errorMessage: null,
      );
    } on AppException catch (error) {
      if (id != _loadId) return;
      state = state.copyWith(
        status: LoadStatus.error,
        errorMessage: error.userMessage,
      );
    } catch (error) {
      if (id != _loadId) return;
      state = state.copyWith(
        status: LoadStatus.error,
        errorMessage: 'Could not load the schedule: $error',
      );
    }
  }

  /// Manga has no hourly airing schedule on AniList, so the manga tab shows
  /// titles whose `startDate` falls inside the selected week (date-only).
  ///
  /// The week is passed to AniList as a start-date window, so every week
  /// fetches its own titles (previously one fixed "newest first" query was
  /// filtered locally, which left the current week empty).
  Future<void> loadManga() async {
    final id = ++_mangaLoadId;
    state = state.copyWith(
      mangaStatus: LoadStatus.loading,
      mangaErrorMessage: null,
    );
    try {
      final start = _weekStart;
      final end = _weekEnd;
      final fetched = await _repo.mangaReleases(from: start, to: end);
      if (id != _mangaLoadId) return; // a newer week was requested.
      // Defensive: only titles with a full start date inside the week.
      final inWeek =
          fetched.where((m) {
            final date = m.startDate == null
                ? null
                : DateTime.tryParse(m.startDate!);
            if (date == null) return false;
            final day = DateTime(date.year, date.month, date.day);
            return !day.isBefore(start) && day.isBefore(end);
          }).toList()..sort((a, b) {
            final byDate = (a.startDate ?? '').compareTo(b.startDate ?? '');
            return byDate != 0
                ? byDate
                : (b.popularity ?? 0).compareTo(a.popularity ?? 0);
          });
      state = state.copyWith(
        mangaStatus: LoadStatus.success,
        mangaItems: inWeek,
        mangaErrorMessage: null,
      );
    } on AppException catch (error) {
      if (id != _mangaLoadId) return;
      state = state.copyWith(
        mangaStatus: LoadStatus.error,
        mangaErrorMessage: error.userMessage,
      );
    } catch (error) {
      if (id != _mangaLoadId) return;
      state = state.copyWith(
        mangaStatus: LoadStatus.error,
        mangaErrorMessage: 'Could not load manga releases: $error',
      );
    }
  }

  Future<void> nextWeek() async {
    if (state.status == LoadStatus.loading ||
        state.mangaStatus == LoadStatus.loading) {
      return; // throttle spam.
    }
    state = state.copyWith(weekOffset: state.weekOffset + 1);
    await load();
  }

  Future<void> previousWeek() async {
    if (state.status == LoadStatus.loading ||
        state.mangaStatus == LoadStatus.loading) {
      return;
    }
    state = state.copyWith(weekOffset: state.weekOffset - 1);
    await load();
  }

  Future<void> thisWeek() async {
    if ((state.status == LoadStatus.loading ||
            state.mangaStatus == LoadStatus.loading) &&
        state.weekOffset == 0) {
      return;
    }
    state = state.copyWith(weekOffset: 0);
    await load();
  }
}

final calendarControllerProvider =
    NotifierProvider<CalendarController, CalendarState>(CalendarController.new);

/// Titles the person asked to be reminded about (the bell on a card).
///
/// Stored locally by AniList media id. This only remembers the choice; it
/// does not schedule any notification by itself.
class CalendarRemindersController extends Notifier<Set<int>> {
  static const _key = 'ikigai.calendar.reminders';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Set<int> build() {
    final stored = _prefs.getStringList(_key) ?? const <String>[];
    return {
      for (final id in stored)
        if (int.tryParse(id) != null) int.parse(id),
    };
  }

  Future<void> toggle(int mediaId) async {
    final next = {...state};
    if (!next.remove(mediaId)) next.add(mediaId);
    state = next;
    await _prefs.setStringList(_key, [for (final id in next) '$id']);
  }
}

final calendarRemindersProvider =
    NotifierProvider<CalendarRemindersController, Set<int>>(
      CalendarRemindersController.new,
    );
