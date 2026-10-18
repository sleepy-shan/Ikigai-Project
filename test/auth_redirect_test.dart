import 'package:flutter_test/flutter_test.dart';
import 'package:ikigai_project/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const redirect = 'https://x.test/#access_token=NEW&token_type=Bearer&expires_in=3600';

  test('query-string tokens are ignored', () {
    expect(
      parseAccessTokenFromUri(Uri.parse('https://x.test/?access_token=evil')),
      isNull,
    );
    expect(parseAccessTokenFromUri(Uri.parse(redirect)), 'NEW');
    expect(
      parseExpiresInFromFragment(Uri.parse(redirect).fragment),
      const Duration(seconds: 3600),
    );
  });

  test('a redirect nobody asked for is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(
      await AniListAuthRepository.acceptRedirect(prefs, Uri.parse(redirect)),
      isFalse,
    );
    expect(prefs.getString(AniListAuthRepository.tokenKey), isNull);
  });

  test('accepted redirect stores token + expiry and drops the old profile',
      () async {
    SharedPreferences.setMockInitialValues({
      AniListAuthRepository.tokenKey: 'OLD',
      AniListAuthRepository.userKey: '{"id":1,"name":"previous"}',
    });
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime(2026, 10, 18, 12);
    await AniListAuthRepository.markLoginStarted(prefs, now: now);
    final ok = await AniListAuthRepository.acceptRedirect(
      prefs,
      Uri.parse(redirect),
      now: now.add(const Duration(minutes: 1)),
    );
    expect(ok, isTrue);
    expect(prefs.getString(AniListAuthRepository.tokenKey), 'NEW');
    expect(prefs.getString(AniListAuthRepository.userKey), isNull);
    expect(prefs.getInt(AniListAuthRepository.tokenExpiryKey), isNotNull);
    // One sign-in allows one redirect.
    expect(prefs.getInt(AniListAuthRepository.loginStartedKey), isNull);
  });

  test('a stale sign-in marker is rejected', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime(2026, 10, 18, 12);
    await AniListAuthRepository.markLoginStarted(prefs, now: now);
    expect(
      await AniListAuthRepository.acceptRedirect(
        prefs,
        Uri.parse(redirect),
        now: now.add(const Duration(hours: 2)),
      ),
      isFalse,
    );
  });
}
