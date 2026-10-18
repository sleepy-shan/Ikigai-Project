import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/repositories/auth_repository.dart';
import '../data/repositories/tracking_repository.dart';

/// Overridden at startup with the resolved [SharedPreferences] instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw StateError('sharedPreferencesProvider must be overridden in main()');
});

/// The tracking store used by the whole app (browser localStorage).
final trackingRepositoryProvider = Provider<TrackingRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LocalTrackingRepository(prefs);
});

/// AniList account backend (OAuth token + Viewer profile).
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repo = createAuthRepository(prefs);
  ref.onDispose(() {
    if (repo is AniListAuthRepository) repo.dispose();
  });
  return repo;
});

/// Waits between background attempts to confirm a saved token after a
/// transient failure (timeout, rate limit, AniList hiccup).
const List<Duration> _authRetryDelays = [
  Duration(seconds: 2),
  Duration(seconds: 5),
  Duration(seconds: 15),
  Duration(seconds: 30),
  Duration(seconds: 60),
];

/// Current AniList user (null = guest browsing). Restores the saved session
/// on first listen and re-emits on sign-in/sign-out.
///
/// If the first validation fails transiently (common right after signing in,
/// when there is no cached profile yet) the token is kept and validation is
/// retried in the background, so the user appears as soon as AniList answers
/// instead of staying a "guest" until the page is refreshed.
final authStateProvider = StreamProvider<AuthUser?>((ref) async* {
  final repo = ref.watch(authRepositoryProvider);

  Timer? retryTimer;
  var attempt = 0;
  void scheduleRetry() {
    if (!repo.needsValidation || attempt >= _authRetryDelays.length) return;
    retryTimer = Timer(_authRetryDelays[attempt++], () async {
      try {
        // Emits through `userChanges` once validation settles.
        await repo.restore();
      } on Object {
        // Still failing: keep backing off.
      }
      scheduleRetry();
    });
  }

  ref.onDispose(() => retryTimer?.cancel());

  try {
    await repo.restore();
  } on Object {
    // Restore failures fall back to guest mode; errors surface on next
    // explicit sign-in attempt instead of breaking the whole app.
  }
  scheduleRetry();
  yield repo.currentUser;
  yield* repo.userChanges.skip(1);
});
