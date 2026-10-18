import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/app_exception.dart';
import '../anilist/anilist_client.dart';
import '../anilist/anilist_queries.dart';

/// The signed-in AniList user.
class AuthUser {
  const AuthUser({required this.id, required this.name, this.avatarUrl});

  final int id;
  final String name;
  final String? avatarUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
  };

  static AuthUser? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    return AuthUser(
      id: id,
      name: name,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

/// Authentication contract. AniList is the only account backend:
/// OAuth implicit grant (`response_type=token`), token stored locally,
/// identity verified with the `Viewer` query.
abstract interface class AuthRepository {
  AuthUser? get currentUser;
  String? get accessToken;
  Stream<AuthUser?> get userChanges;

  /// Null when no `ANILIST_CLIENT_ID` was supplied at build time.
  Uri? get loginUri;

  /// Validates [token] against AniList, persists it + the profile, emits user.
  Future<AuthUser> signInWithToken(String token, {Duration? expiresIn});

  Future<void> signOut();

  /// Loads the saved session (if any) and re-validates it with AniList.
  /// Invalid tokens are cleared so the app falls back to guest mode.
  ///
  /// Safe to call again: after a transient failure (timeout, rate limit,
  /// AniList hiccup) a later call re-attempts validation instead of returning
  /// early; once a run has settled it is a no-op.
  Future<void> restore();

  /// True while a saved token exists that AniList has not confirmed yet
  /// because the last validation attempt failed transiently.
  bool get needsValidation;
}

/// Extracts a parameter from an OAuth implicit redirect fragment such as
/// `access_token=abc&token_type=Bearer&expires_in=3600`.
String? _fragmentParam(String fragment, String name) {
  final clean = fragment.startsWith('#') ? fragment.substring(1) : fragment;
  if (clean.isEmpty) return null;
  for (final part in clean.split('&')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final key = Uri.decodeComponent(part.substring(0, eq));
    if (key == name) {
      final value = Uri.decodeComponent(part.substring(eq + 1));
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// Extracts `access_token` from an OAuth implicit redirect fragment.
String? parseAccessTokenFromFragment(String fragment) =>
    _fragmentParam(fragment, 'access_token');

/// Extracts `expires_in` (seconds) from an OAuth implicit redirect fragment.
Duration? parseExpiresInFromFragment(String fragment) {
  final seconds = int.tryParse(_fragmentParam(fragment, 'expires_in') ?? '');
  if (seconds == null || seconds <= 0) return null;
  return Duration(seconds: seconds);
}

/// Convenience wrapper around [parseAccessTokenFromFragment] for [Uri.base].
///
/// Only the URL **fragment** is read. A `?access_token=` query parameter is
/// deliberately ignored: the implicit grant never delivers a token there, and
/// accepting one would let anyone craft a link that silently signs a victim
/// into the attacker's AniList account.
String? parseAccessTokenFromUri(Uri uri) =>
    parseAccessTokenFromFragment(uri.fragment);

class AniListAuthRepository implements AuthRepository {
  AniListAuthRepository(this._prefs, [AniListClient? client])
    : _client = client ?? AniListClient(),
      _ownsClient = client == null;

  static const String tokenKey = 'ikigai.anilist.token';
  static const String userKey = 'ikigai.anilist.user';

  /// Epoch milliseconds at which the saved token stops being valid, from the
  /// redirect's `expires_in`. Lets an expired token be dropped up front rather
  /// than discovered by a failed request.
  static const String tokenExpiryKey = 'ikigai.anilist.tokenExpiresAt';

  /// Epoch milliseconds of the last "Sign in with AniList" tap in this
  /// browser. A redirect token is only accepted shortly after one, so a link
  /// someone else crafted cannot sign this browser into their account.
  static const String loginStartedKey = 'ikigai.anilist.loginStartedAt';

  /// How long after tapping "Sign in" a redirect token is still accepted.
  static const Duration loginWindow = Duration(minutes: 30);
  // Pre-rebrand keys — read once for migration, new writes use ikigai.*.
  static const String legacyTokenKey = 'sandwich.anilist.token';
  static const String legacyUserKey = 'sandwich.anilist.user';

  final SharedPreferences _prefs;
  final AniListClient _client;
  final bool _ownsClient;

  AuthUser? _user;
  String? _token;
  final _controller = StreamController<AuthUser?>.broadcast();

  /// Saved session has been loaded from storage (done once).
  bool _restored = false;

  /// The last validation attempt failed transiently, so the token is still
  /// unconfirmed and [restore] should be allowed to run again.
  bool _needsValidation = false;
  Future<void>? _restoring;

  @override
  AuthUser? get currentUser => _user;

  @override
  String? get accessToken => _token;

  @override
  bool get needsValidation => _needsValidation;

  @override
  Stream<AuthUser?> get userChanges async* {
    yield _user;
    yield* _controller.stream;
  }

  /// Records that the user just asked to sign in, arming [acceptRedirect].
  static Future<void> markLoginStarted(
    SharedPreferences prefs, {
    DateTime? now,
  }) async {
    await prefs.setInt(
      loginStartedKey,
      (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  /// Stores the token from an OAuth redirect [uri], if it is legitimate.
  ///
  /// Returns true when a token was accepted. A token is only accepted when
  /// this browser started a sign-in within [loginWindow]; the marker is
  /// consumed either way, so one sign-in allows one redirect.
  ///
  /// When the token differs from the one already saved, the previously cached
  /// profile is dropped so the old account's name and avatar can never be
  /// shown next to the new token if validation fails.
  static Future<bool> acceptRedirect(
    SharedPreferences prefs,
    Uri uri, {
    DateTime? now,
  }) async {
    final token = parseAccessTokenFromFragment(uri.fragment);
    if (token == null || token.isEmpty) return false;

    final clock = now ?? DateTime.now();
    final startedMs = prefs.getInt(loginStartedKey);
    await prefs.remove(loginStartedKey);
    if (startedMs == null) return false; // nobody here asked to sign in.
    final age = clock.difference(
      DateTime.fromMillisecondsSinceEpoch(startedMs),
    );
    if (age > loginWindow) return false;

    final previous = prefs.getString(tokenKey) ?? prefs.getString(legacyTokenKey);
    if (previous != token) {
      await prefs.remove(userKey);
      await prefs.remove(legacyUserKey);
    }
    await prefs.setString(tokenKey, token);
    await prefs.remove(legacyTokenKey);

    final expiresIn = parseExpiresInFromFragment(uri.fragment);
    if (expiresIn == null) {
      await prefs.remove(tokenExpiryKey);
    } else {
      await prefs.setInt(
        tokenExpiryKey,
        clock.add(expiresIn).millisecondsSinceEpoch,
      );
    }
    return true;
  }

  @override
  Uri? get loginUri =>
      AppConfig.hasAnilistClient ? AppConfig.anilistLoginUri() : null;

  @override
  Future<AuthUser> signInWithToken(String token, {Duration? expiresIn}) async {
    final clean = token.trim();
    if (clean.isEmpty) {
      throw const AppException(
        ErrorKind.validation,
        'Received an empty sign-in token — please try again.',
      );
    }
    final viewer = await _fetchViewer(clean);
    _token = clean;
    _user = viewer;
    _needsValidation = false;
    await _prefs.setString(tokenKey, clean);
    await _prefs.setString(
      userKey,
      jsonEncode(viewer.toJson()),
    );
    if (expiresIn == null) {
      await _prefs.remove(tokenExpiryKey);
    } else {
      await _prefs.setInt(
        tokenExpiryKey,
        DateTime.now().add(expiresIn).millisecondsSinceEpoch,
      );
    }
    if (!_controller.isClosed) _controller.add(_user);
    return viewer;
  }

  @override
  Future<void> signOut() async {
    _token = null;
    _user = null;
    _needsValidation = false;
    await _prefs.remove(tokenKey);
    await _prefs.remove(userKey);
    await _prefs.remove(tokenExpiryKey);
    await _prefs.remove(legacyTokenKey);
    await _prefs.remove(legacyUserKey);
    if (!_controller.isClosed) _controller.add(null);
  }

  @override
  Future<void> restore() {
    // A settled run is a no-op; a run that ended on a transient failure may
    // be repeated. Concurrent callers share the run that is in flight.
    if (_restored && !_needsValidation) return Future<void>.value();
    return _restoring ??= _restore().whenComplete(() => _restoring = null);
  }

  Future<void> _restore() async {
    if (!_restored) {
      _restored = true;
      _token = _prefs.getString(tokenKey) ?? _prefs.getString(legacyTokenKey);
      _user = _cachedUser();
      if (_token == null || _token!.isEmpty) {
        _token = null;
        _user = null;
        _needsValidation = false;
        if (!_controller.isClosed) _controller.add(null);
        return;
      }
      final expiresAtMs = _prefs.getInt(tokenExpiryKey);
      if (expiresAtMs != null &&
          DateTime.now().millisecondsSinceEpoch >= expiresAtMs) {
        // Known to be expired already: no request needed to find out.
        await signOut();
        return;
      }
    }

    final token = _token;
    if (token == null) {
      _needsValidation = false;
      return;
    }
    try {
      final viewer = await _fetchViewer(token);
      if (_token != token) return; // signed out / replaced while waiting.
      _user = viewer;
      _needsValidation = false;
      await _prefs.setString(userKey, jsonEncode(viewer.toJson()));
    } on AppException catch (error) {
      if (_token != token) return;
      if (error.kind == ErrorKind.unauthorized) {
        // Expired/revoked token — drop it and stay in guest mode.
        await signOut();
        return;
      }
      // Network/rate-limit/server: keep any cached profile so the UI still
      // shows who is signed in, and remember that the token is unconfirmed.
      // Unlike before, this does NOT end the attempt for good: restore() can
      // be called again (the auth provider retries with backoff, and the
      // profile page offers a retry button).
      _needsValidation = true;
    }
    if (!_controller.isClosed) _controller.add(_user);
  }

  AuthUser? _cachedUser() {
    final raw =
        _prefs.getString(userKey) ?? _prefs.getString(legacyUserKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return AuthUser.fromJson(decoded);
      if (decoded is Map) {
        return AuthUser.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on Object {
      // Corrupt cache — ignore and re-fetch.
    }
    return null;
  }

  Future<AuthUser> _fetchViewer(String token) async {
    final Map<String, dynamic> data;
    try {
      data = await _client.query(kViewerQuery, const {}, token: token);
    } on AppException catch (error) {
      // `Viewer` is a fixed, known-valid query with no variables, so the only
      // way AniList can answer it with HTTP 400 is by rejecting the token
      // itself (AniList reports an invalid token as a 400, not a 401).
      if (error.kind == ErrorKind.badRequest) {
        throw AppException(
          ErrorKind.unauthorized,
          'AniList rejected the saved token',
          cause: error,
          statusCode: error.statusCode,
        );
      }
      rethrow;
    }
    final viewer = data['Viewer'];
    if (viewer is! Map) {
      throw const AppException(
        ErrorKind.server,
        'AniList did not return a profile for this token.',
      );
    }
    final map = viewer is Map<String, dynamic>
        ? viewer
        : Map<String, dynamic>.from(viewer);
    final id = (map['id'] as num?)?.toInt();
    final name = map['name'] as String?;
    if (id == null || name == null || name.isEmpty) {
      throw const AppException(
        ErrorKind.server,
        'AniList did not return a profile for this token.',
      );
    }
    final avatar = map['avatar'];
    String? avatarUrl;
    if (avatar is Map) {
      avatarUrl = avatar['large'] as String?;
    }
    return AuthUser(id: id, name: name, avatarUrl: avatarUrl);
  }

  void dispose() {
    _controller.close();
    if (_ownsClient) _client.close();
  }
}

/// Picks the AniList implementation for the current build configuration.
AuthRepository createAuthRepository(
  SharedPreferences prefs, [
  AniListClient? client,
]) => AniListAuthRepository(prefs, client);
