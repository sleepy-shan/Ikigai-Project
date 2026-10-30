import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/utils/app_exception.dart';

/// `http.Client` handed to `HttpLink`. It is the single choke point where the
/// app stays inside AniList's rate limit (90 req/min nominal, 30 when AniList
/// is degraded):
///
///  * a sliding-window gate delays requests instead of letting them 429,
///  * a 429 pauses EVERY queued request until `Retry-After` passes,
///  * 429/5xx are retried with backoff + jitter (queries and the absolute-
///    progress mutation are idempotent),
///  * AniList's "HTTP 404 + partial data" responses are passed through as
///    usable data, matching what your hand-written client does today,
///  * other failures are thrown as the app's own [AppException], so the UI
///    error handling you already have keeps working.
///
/// The window is per browser tab. Two open tabs share the real limit.
class AniListHttpClient extends http.BaseClient {
  AniListHttpClient({
    http.Client? inner,
    this.maxRetries = 2,
    this.requestsPerMinute = 80, // headroom under 90
    this.timeout = const Duration(seconds: 20),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final int maxRetries;
  final int requestsPerMinute;
  final Duration timeout;

  static const Duration _window = Duration(minutes: 1);
  static const Duration _maxAutoWait = Duration(seconds: 60);

  final Queue<DateTime> _sent = Queue<DateTime>();
  DateTime? _blockedUntil;
  final math.Random _random = math.Random();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is! http.Request) {
      // Multipart/streamed uploads cannot be replayed; AniList needs neither.
      await _acquire();
      return _inner.send(request).timeout(timeout);
    }
    final hasToken = request.headers.containsKey('Authorization');

    for (var attempt = 0; ; attempt++) {
      await _acquire();

      final http.StreamedResponse response;
      try {
        response = await _inner.send(_copy(request)).timeout(timeout);
      } on TimeoutException {
        throw const AppException(ErrorKind.network, 'AniList request timed out');
      } on http.ClientException catch (e) {
        if (attempt < maxRetries) {
          await _backoff(attempt);
          continue;
        }
        throw AppException(ErrorKind.network, 'Network request failed: $e');
      }

      final status = response.statusCode;
      if (status >= 200 && status < 300) return response;

      // Buffer the (small) error body once so we can inspect it and, if
      // needed, hand an intact copy back to HttpLink.
      final bytes = await response.stream.toBytes();

      if (status == 429) {
        // On web, CORS usually hides `Retry-After`, so the fallback must be
        // long enough to outlast AniList's block (a 0.5-1s backoff just hits
        // the limit again and burns the retries): 5s, then 10s.
        final wait =
            _retryAfter(response) ?? Duration(seconds: 5 * (attempt + 1));
        _blockedUntil = DateTime.now().add(wait); // pause everyone
        if (wait > _maxAutoWait || attempt >= maxRetries) {
          throw AppException(
            ErrorKind.rateLimit,
            'AniList rate limit exceeded',
            statusCode: 429,
            retryAfter: _retryAfter(response),
          );
        }
        continue; // _acquire() above waits out _blockedUntil
      }

      if (status >= 500 && attempt < maxRetries) {
        await _backoff(attempt);
        continue;
      }

      // AniList mirrors a field-level error status into the HTTP status but
      // may still send usable `data`. Keep it, like the current client does.
      if (_hasUsableData(bytes)) {
        return http.StreamedResponse(
          Stream<List<int>>.value(bytes),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }
      throw _classify(status, hasToken);
    }
  }

  // -- rate gate -------------------------------------------------------------
  Future<void> _acquire() async {
    while (true) {
      final now = DateTime.now();

      final blocked = _blockedUntil;
      if (blocked != null && blocked.isAfter(now)) {
        await Future<void>.delayed(blocked.difference(now));
        continue;
      }

      while (_sent.isNotEmpty && now.difference(_sent.first) >= _window) {
        _sent.removeFirst();
      }
      if (_sent.length < requestsPerMinute) {
        _sent.addLast(now); // reserve synchronously: no race between waiters
        return;
      }
      final wait = _window - now.difference(_sent.first);
      await Future<void>.delayed(wait + const Duration(milliseconds: 25));
    }
  }

  // -- helpers ---------------------------------------------------------------
  static http.Request _copy(http.Request r) => http.Request(r.method, r.url)
    ..headers.addAll(r.headers)
    ..bodyBytes = r.bodyBytes;

  static Duration? _retryAfter(http.BaseResponse r) {
    final seconds = int.tryParse((r.headers['retry-after'] ?? '').trim());
    return (seconds == null || seconds <= 0) ? null : Duration(seconds: seconds);
  }

  Duration _backoffDelay(int attempt) {
    final base = 500 * math.pow(2, attempt).toInt();
    final jitter = (base * 0.25 * (_random.nextDouble() * 2 - 1)).toInt();
    return Duration(milliseconds: base + jitter);
  }

  Future<void> _backoff(int attempt) =>
      Future<void>.delayed(_backoffDelay(attempt));

  static bool _hasUsableData(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final data = decoded is Map ? decoded['data'] : null;
      return data is Map && data.values.any((v) => v != null);
    } on Object {
      return false;
    }
  }

  static AppException _classify(int status, bool hasToken) => switch (status) {
    400 => AppException(ErrorKind.badRequest, 'AniList rejected the request',
        statusCode: status),
    404 => AppException(ErrorKind.notFound, 'Not found', statusCode: status),
    401 when hasToken => AppException(
        ErrorKind.unauthorized, 'AniList token expired or invalid',
        statusCode: status),
    403 when hasToken =>
      AppException(ErrorKind.forbidden, 'Forbidden', statusCode: status),
    _ => AppException(ErrorKind.server, 'AniList responded with $status',
        statusCode: status),
  };

  @override
  void close() => _inner.close();
}
