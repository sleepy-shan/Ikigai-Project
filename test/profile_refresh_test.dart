import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ikigai_project/app.dart';
import 'package:ikigai_project/data/anilist/anilist_client.dart';
import 'package:ikigai_project/data/models/account.dart';
import 'package:ikigai_project/data/repositories/auth_repository.dart';
import 'package:ikigai_project/state/media_providers.dart';
import 'package:ikigai_project/state/providers.dart';

/// Answers AniList GraphQL requests from canned payloads.
///
/// The request body is the GraphQL document; the matching payload is picked
/// by the root field the document asks for, so one fake covers every request
/// the profile page fires (Viewer validation, statistics, notifications,
/// activity, list collection).
class _FakeAniList extends http.BaseClient {
  _FakeAniList({this.failViewer = false, this.hold});

  /// When true, requests asking for `Viewer` answer with a 429, simulating
  /// the transient failure that happens on a fresh page load.
  final bool failViewer;

  /// When set, every request waits for this completer — used to observe what
  /// the UI shows *before* the network has answered.
  final Completer<void>? hold;

  final List<String> queries = [];

  /// Lets every request held at [hold] through.
  ///
  /// Completing the gate schedules the waiting responses; they land on the
  /// next `pump`, so this must not itself await a timer (the test body runs
  /// in a fake-async zone where timers only fire while pumping).
  void release() {
    final gate = hold;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().bytesToString();
    final document = (jsonDecode(body) as Map<String, dynamic>)['query'];
    final query = document is String ? document : '';
    queries.add(query);

    await hold?.future;

    final payload = failViewer && query.contains('Viewer')
        ? jsonEncode({
            'errors': [
              {'message': 'Too Many Requests', 'status': 429},
            ],
          })
        : jsonEncode(_payloadFor(query));
    final status = failViewer && query.contains('Viewer') ? 429 : 200;
    final response = http.Response(
      payload,
      status,
      headers: const {'content-type': 'application/json'},
    );
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([response.bodyBytes]),
      status,
      headers: const {'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _payloadFor(String query) {
    if (query.contains('statistics')) return _viewerStatistics;
    if (query.contains('Viewer')) return _viewer;
    if (query.contains('notifications')) {
      return {
        'data': {
          'Page': {'notifications': <Object?>[]},
        },
      };
    }
    if (query.contains('activities(')) {
      return {
        'data': {
          'Page': {
            'pageInfo': {'currentPage': 1, 'hasNextPage': false},
            'activities': <Object?>[],
          },
        },
      };
    }
    if (query.contains('MediaListCollection')) {
      return {
        'data': {
          'MediaListCollection': {
            'user': {
              'mediaListOptions': {'scoreFormat': 'POINT_10'},
            },
            'lists': <Object?>[],
          },
        },
      };
    }
    if (query.contains('Page(')) {
      return {
        'data': {
          'Page': {
            'pageInfo': {'currentPage': 1, 'hasNextPage': false},
            'media': <Object?>[],
          },
        },
      };
    }
    return const {'data': <String, Object?>{}};
  }
}

const Map<String, Object?> _viewer = {
  'data': {
    'Viewer': {
      'id': 1234,
      'name': 'RefreshUser',
      'avatar': {'large': null},
    },
  },
};

const Map<String, Object?> _viewerStatistics = {
  'data': {
    'Viewer': {
      'id': 1234,
      'name': 'RefreshUser',
      'avatar': {'large': null},
      'bannerImage': null,
      'favourites': {
        'anime': {
          'pageInfo': {'total': 7},
        },
      },
      'statistics': {
        'anime': {
          'count': 42,
          'episodesWatched': 1200,
          'minutesWatched': 26000,
          'meanScore': 82.5,
          'statuses': [
            {'status': 'CURRENT', 'count': 5},
            {'status': 'COMPLETED', 'count': 30},
          ],
          'genres': [
            {'genre': 'Action', 'count': 10},
          ],
        },
        'manga': {
          'count': 10,
          'chaptersRead': 500,
          'volumesRead': 50,
          'meanScore': 78,
          'genres': <Object?>[],
        },
      },
    },
  },
};

/// The profile statistics as they were when the page was last loaded — what
/// local storage holds between visits.
final ViewerProfile _snapshot = ViewerProfile(
  name: 'RefreshUser',
  totalCount: 42,
  watching: 5,
  completed: 30,
  episodesWatched: 1200,
  minutesWatched: 26000,
  meanScore: 82.5,
  mangaCount: 10,
  chaptersRead: 500,
  volumesRead: 50,
  mangaMeanScore: 78,
);

/// Builds the app exactly the way a browser reload does: preferences already
/// hold the saved session and every provider starts from scratch at /profile.
Future<void> _pumpColdStart(
  WidgetTester tester, {
  required _FakeAniList http,
  Map<String, Object> extraPrefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    AniListAuthRepository.tokenKey: 'saved-token',
    AniListAuthRepository.userKey: jsonEncode(const AuthUser(
      id: 1234,
      name: 'RefreshUser',
    ).toJson()),
    ...extraPrefs,
  });
  final prefs = await SharedPreferences.getInstance();

  // Boot the router straight at /profile, exactly like a browser refresh of
  // that URL (no in-app navigation, so no transition to race with).
  tester.binding.platformDispatcher.defaultRouteNameTestValue = '/profile';
  addTearDown(
    tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(
          AniListAuthRepository(prefs, AniListClient(httpClient: http)),
        ),
        aniListClientProvider.overrideWithValue(
          AniListClient(httpClient: http),
        ),
      ],
      child: const IkigaiApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// Runs the clock forward so queued requests, retries and animations settle.
Future<void> _settle(WidgetTester tester, {int frames = 30}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Runs out the background validation retries (2s/5s/15s/30s/60s) so no
/// timer is left pending when the test ends.
Future<void> _flushAuthRetries(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 130));
}

void main() {
  testWidgets('profile data survives a browser refresh on /profile', (
    tester,
  ) async {
    await _pumpColdStart(tester, http: _FakeAniList());
    await _settle(tester);

    expect(
      find.text('RefreshUser'),
      findsWidgets,
      reason: 'the restored session must render the signed-in identity '
          'after a reload',
    );
    expect(
      find.text('42'),
      findsWidgets,
      reason: 'the statistics panel must load rather than stay empty',
    );
    expect(
      find.textContaining("Couldn't load"),
      findsNothing,
      reason: 'a successful refresh must not fall back to the error card',
    );
    await _flushAuthRetries(tester);
  });

  testWidgets('the saved identity shows before AniList answers', (
    tester,
  ) async {
    final gate = Completer<void>();
    final fake = _FakeAniList(hold: gate);
    await _pumpColdStart(tester, http: fake);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('RefreshUser'),
      findsWidgets,
      reason: 'a reload must not wait for the Viewer request to say who is '
          'signed in — the session is already in local storage',
    );
    expect(
      find.text('Sign in'),
      findsNothing,
      reason: 'the account button must not fall back to the guest state '
          'while validation is still in flight',
    );

    fake.release();
    await _settle(tester);
    expect(find.text('42'), findsWidgets, reason: 'statistics arrive once '
        'the held request completes');
    await _flushAuthRetries(tester);
  });

  testWidgets('a persisted snapshot keeps the statistics visible when '
      'AniList is unreachable', (tester) async {
    await _pumpColdStart(
      tester,
      http: _FakeAniList(failViewer: true),
      extraPrefs: {
        AniListAuthRepository.profileSnapshotKey(1234):
            jsonEncode(_snapshot.toJson()),
      },
    );
    await _settle(tester);

    expect(
      find.text('RefreshUser'),
      findsWidgets,
      reason: 'a rate-limited reload must not drop the saved identity',
    );
    expect(
      find.text('42'),
      findsWidgets,
      reason: 'the snapshot must fill the statistics panels instead of '
          'showing empty "—" values',
    );
    expect(
      find.text('Sign in'),
      findsNothing,
      reason: 'a 429 must not silently sign the user out',
    );
    expect(
      find.textContaining("Couldn't load"),
      findsNothing,
      reason: 'with a snapshot on hand the page has data, not an error',
    );
    await _flushAuthRetries(tester);
  });

  testWidgets('an advertised expiry does not sign the user out on reload', (
    tester,
  ) async {
    await _pumpColdStart(
      tester,
      http: _FakeAniList(),
      extraPrefs: {
        // AniList advertised `expires_in` an hour ago; the token still works.
        AniListAuthRepository.tokenExpiryKey:
            DateTime.now()
                .subtract(const Duration(hours: 2))
                .millisecondsSinceEpoch,
      },
    );
    await _settle(tester);

    expect(
      find.text('RefreshUser'),
      findsWidgets,
      reason: 'only AniList may declare the token dead — the client used to '
          'clear the session locally on the advertised deadline',
    );
    expect(
      find.text('42'),
      findsWidgets,
      reason: 'statistics must load for the still-valid session',
    );
    expect(find.text('Sign in'), findsNothing);
    await _flushAuthRetries(tester);
  });
}
