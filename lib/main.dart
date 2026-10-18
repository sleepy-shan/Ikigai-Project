import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/utils/url_cleaner.dart';
import 'data/repositories/auth_repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Never leave the user on a blank page: surface startup failures in the
  // console and keep going with a degraded (in-memory) start when possible.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught async error: $error');
    return true; // handled — don't kill the app on background failures.
  };

  // Clean, shareable URLs (/anime instead of /#/anime). Works when the
  // host rewrites unknown paths to index.html — see the README.
  usePathUrlStrategy();

  final prefs = await _loadPreferences();

  // AniList OAuth implicit flow: AniList redirects back to the registered
  // Redirect URL with `#access_token=...&expires_in=...`. Capture it once and
  // persist it so the auth provider can validate it on first listen.
  //
  // Only the fragment is read, and only right after this browser started a
  // sign-in (see `AniListAuthRepository.acceptRedirect`), so a crafted link
  // cannot sign someone into another person's account.
  try {
    final base = Uri.base;
    if (parseAccessTokenFromUri(base) != null) {
      await AniListAuthRepository.acceptRedirect(prefs, base);
      // Whether it was accepted or ignored, a token must not stay in the
      // address bar and browser history.
      clearUrlFragment();
    }
  } on Object catch (error) {
    // Token capture must never block startup (e.g. blocked storage).
    debugPrint('Ignoring OAuth token capture failure: $error');
  }

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const IkigaiApp(),
    ),
  );
}

/// Loads [SharedPreferences], falling back to an in-memory store when the
/// browser blocks storage (private mode, disabled cookies, sandboxed
/// iframe). Without this fallback `main()` would throw before `runApp`,
/// leaving a white screen on the deployed site.
Future<SharedPreferences> _loadPreferences() async {
  try {
    return await SharedPreferences.getInstance();
  } on Object catch (error) {
    debugPrint('SharedPreferences unavailable, using in-memory: $error');
    // Intentional: this is the only way to get an in-memory SharedPreferences
    // when platform storage is blocked, so the app can still start.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(const {});
    return SharedPreferences.getInstance();
  }
}
