import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ikigai_project/data/anilist/anilist_client.dart';
import 'package:ikigai_project/data/repositories/auth_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a saved token is validated on page load and the user appears',
      () async {
    SharedPreferences.setMockInitialValues({
      AniListAuthRepository.tokenKey: 'tok',
    });
    final prefs = await SharedPreferences.getInstance();

    var viewerCalls = 0;
    final client = MockClient((request) async {
      viewerCalls++;
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode({
          'data': {
            'Viewer': {
              'id': 7,
              'name': 'Sean',
              'avatar': {'large': null},
            },
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final repo = AniListAuthRepository(
      prefs,
      AniListClient(httpClient: client, maxRetries: 0),
    );

    // Same order as the app's auth provider: load first, then restore.
    repo.loadSavedSession();
    expect(repo.currentUser, isNull, reason: 'no cached profile yet');

    await repo.restore();

    expect(viewerCalls, 1, reason: 'the token must be checked with AniList');
    expect(repo.currentUser?.name, 'Sean');
    expect(repo.needsValidation, isFalse);
  });
}
