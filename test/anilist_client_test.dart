import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ikigai_project/core/utils/app_exception.dart';
import 'package:ikigai_project/data/anilist/anilist_client.dart';

http.Response _json(Object body, {int status = 200, Map<String, String>? h}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json', ...?h},
    );

Future<AppException> _fail(Future<Object?> Function() run) async {
  try {
    await run();
  } on AppException catch (e) {
    return e;
  }
  fail('expected an AppException');
}

void main() {
  AniListClient client(MockClient mock) =>
      AniListClient(httpClient: mock, maxRetries: 0);

  test('HTTP 400 is badRequest, not notFound', () async {
    final c = client(
      MockClient(
        (_) async => _json({
          'errors': [
            {'message': 'Bad variable', 'status': 400},
          ],
          'data': null,
        }, status: 400),
      ),
    );
    final e = await _fail(() => c.query('q', {}));
    expect(e.kind, ErrorKind.badRequest);
  });

  test('HTTP 404 is notFound', () async {
    final c = client(
      MockClient(
        (_) async => _json({
          'errors': [
            {'message': 'anything', 'status': 404},
          ],
          'data': {'Media': null},
        }, status: 404),
      ),
    );
    expect((await _fail(() => c.query('q', {}))).kind, ErrorKind.notFound);
  });

  test('guest 403 is not "session expired"; with a token it is forbidden',
      () async {
    final c = client(MockClient((_) async => http.Response('blocked', 403)));
    expect((await _fail(() => c.query('q', {}))).kind, ErrorKind.server);
    expect(
      (await _fail(() => c.query('q', {}, token: 't'))).kind,
      ErrorKind.forbidden,
    );
  });

  test('401 is unauthorized only when a token was sent', () async {
    final c = client(MockClient((_) async => http.Response('', 401)));
    expect((await _fail(() => c.query('q', {}))).kind, ErrorKind.server);
    expect(
      (await _fail(() => c.query('q', {}, token: 't'))).kind,
      ErrorKind.unauthorized,
    );
  });

  test('classification ignores message wording', () async {
    final c = client(
      MockClient(
        (_) async => _json({
          'errors': [
            {'message': 'totally new wording', 'status': 404},
          ],
          'data': {'Media': null},
        }),
      ),
    );
    expect((await _fail(() => c.query('q', {}))).kind, ErrorKind.notFound);
  });

  test('partial data with an error is returned, not thrown', () async {
    final c = client(
      MockClient(
        (_) async => _json({
          'errors': [
            {'message': 'private item', 'status': 403},
          ],
          'data': {
            'Page': {'media': []},
            'Other': null,
          },
        }),
      ),
    );
    final data = await c.query('q', {});
    expect(data['Page'], isNotNull);
  });

  test('Retry-After above 60s fails fast without retrying', () async {
    var calls = 0;
    final c = AniListClient(
      maxRetries: 3,
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('', 429, headers: {'retry-after': '600'});
      }),
    );
    final e = await _fail(() => c.query('q', {}));
    expect(e.kind, ErrorKind.rateLimit);
    expect(e.retryAfter, const Duration(seconds: 600));
    expect(calls, 1);
  });
}
