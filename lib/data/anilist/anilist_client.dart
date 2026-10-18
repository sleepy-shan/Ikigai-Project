import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import '../../core/utils/app_exception.dart';

/// Thin GraphQL client for the public AniList API.
///
/// AniList needs no credentials for public metadata (browse, search,
/// details, airing schedule) and exposes a single POST endpoint.
/// Rate limits: 90 requests/minute, degrading to 30 when abused — the app
/// surfaces HTTP 429 as a friendly [AppException] with a retry action.
///
/// ### How failures are classified
///
/// AniList reports GraphQL failures in the response body *and* mirrors the
/// error's own `status` into the HTTP status (a missing title is a 404 with
/// `data: { Media: null }`). Classification therefore uses numeric statuses
/// only — never the wording of an error message, which AniList may change.
///
/// * 400 → [ErrorKind.badRequest] (our query/variables are wrong; not a
///   missing title).
/// * 404 → [ErrorKind.notFound].
/// * 401 → [ErrorKind.unauthorized], but only when a token was sent. A guest
///   request has no session to expire.
/// * 403 → [ErrorKind.forbidden] when a token was sent, otherwise
///   [ErrorKind.server] (e.g. a Cloudflare block), never "sign in again".
/// * 429 → [ErrorKind.rateLimit]; 5xx → [ErrorKind.server].
///
/// A response that carries usable `data` is returned even if `errors` is also
/// present: AniList can answer a query with partial data plus an error on one
/// field (a private or deleted item) and the rest should still render.
class AniListClient {
  AniListClient({http.Client? httpClient, this.maxRetries = 2})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final int maxRetries;
  final math.Random _random = math.Random();

  static const Duration timeout = Duration(seconds: 20);

  /// Longest `Retry-After` the client will sit out before retrying. A server
  /// asking for more than this is not going to be satisfied by a short wait,
  /// so the failure is surfaced immediately instead of burning retries that
  /// would be rate-limited again.
  static const Duration maxAutoRetryWait = Duration(seconds: 60);

  /// Reads `Retry-After` (delta-seconds form) from a 429 response.
  Duration? _retryAfterOf(http.Response response) {
    final raw = response.headers['retry-after'];
    if (raw == null || raw.isEmpty) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  /// Executes [document] with [variables] and returns the `data` payload.
  ///
  /// Retries transient failures (network, 429, 5xx) with exponential
  /// backoff + jitter because AniList occasionally bursts 429s. Honors
  /// `Retry-After` when it is short enough to wait out.
  ///
  /// Pass [token] for authenticated operations (e.g. the Viewer query).
  /// The token is sent as `Authorization: Bearer <token>` and never logged.
  Future<Map<String, dynamic>> query(
    String document,
    Map<String, dynamic> variables, {
    String? token,
  }) async {
    var attempt = 0;
    // Encode once per query (not per retry) to avoid re-encoding the
    // large GraphQL document on every backoff.
    final body = jsonEncode({'query': document, 'variables': variables});
    while (true) {
      attempt++;
      try {
        return await _attempt(body, token: token);
      } on _RetryAfter catch (retry) {
        if (attempt > maxRetries) {
          throw AppException(
            ErrorKind.rateLimit,
            'AniList rate limit exceeded',
            statusCode: 429,
            retryAfter: retry.delay,
          );
        }
        await Future<void>.delayed(retry.delay);
      } on AppException catch (error) {
        // The server named a wait longer than we are willing to sit out:
        // retrying now would just be rate-limited again.
        final tooLong =
            error.kind == ErrorKind.rateLimit && error.retryAfter != null;
        final retryable =
            error.kind == ErrorKind.network ||
            error.kind == ErrorKind.rateLimit ||
            error.kind == ErrorKind.server;
        if (tooLong || !retryable || attempt > maxRetries) rethrow;
        // Exponential backoff with ±25% jitter to avoid retry storms.
        final base = 500 * math.pow(2, attempt - 1).toInt();
        final jitter = (base * 0.25 * (_random.nextDouble() * 2 - 1)).toInt();
        await Future<void>.delayed(Duration(milliseconds: base + jitter));
      }
    }
  }

  Future<Map<String, dynamic>> _attempt(String body, {String? token}) async {
    final hasToken = token != null && token.isNotEmpty;
    late final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(AppConfig.aniListEndpoint),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (hasToken) 'Authorization': 'Bearer $token',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AppException(ErrorKind.network, 'AniList request timed out');
    } on Object catch (error) {
      throw AppException(ErrorKind.network, 'Network request failed: $error');
    }

    final status = response.statusCode;

    if (status == 429) {
      final retryAfter = _retryAfterOf(response);
      if (retryAfter != null && retryAfter <= maxAutoRetryWait) {
        throw _RetryAfter(retryAfter);
      }
      throw AppException(
        ErrorKind.rateLimit,
        'AniList rate limit exceeded',
        statusCode: 429,
        // Null when the header was missing: the generic retry/backoff path
        // then applies. Present-but-long is surfaced without retrying.
        retryAfter: retryAfter,
      );
    }

    // AniList sends a JSON body with errors even on non-200 statuses, so the
    // body is parsed first and the status only decides when it is unusable.
    final Object? decoded = _tryDecode(response.body);
    final payload = decoded is Map<String, dynamic> ? decoded : null;
    final data = payload?['data'];
    final errors = payload?['errors'];
    final hasErrors = errors is List && errors.isNotEmpty;

    // Partial results: usable data wins over a sibling error.
    if (data is Map<String, dynamic> && _hasUsableData(data)) {
      if (hasErrors) {
        developer.log(
          'AniList returned partial data with errors: '
          '${_describeErrors(errors)}',
          name: 'AniListClient',
        );
      }
      return data;
    }

    if (hasErrors || status != 200) {
      throw _classify(
        httpStatus: status,
        errors: errors is List ? errors : const [],
        hasToken: hasToken,
      );
    }

    if (payload == null) {
      throw AppException(
        ErrorKind.server,
        decoded == null
            ? 'AniList returned malformed JSON'
            : 'Unexpected AniList payload shape',
        statusCode: status,
      );
    }
    if (data is Map<String, dynamic>) {
      // 200, no errors, but every root field is null (e.g. an empty lookup).
      return data;
    }
    throw AppException(
      ErrorKind.server,
      'AniList response contained no data',
      statusCode: status,
    );
  }

  /// True when at least one root field carries a value.
  static bool _hasUsableData(Map<String, dynamic> data) =>
      data.values.any((value) => value != null);

  static Object? _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Maps a failed response to an [AppException] using numeric statuses.
  AppException _classify({
    required int httpStatus,
    required List<dynamic> errors,
    required bool hasToken,
  }) {
    // Prefer the error's own status (what AniList mirrors into the HTTP
    // status anyway); fall back to the HTTP status.
    var status = httpStatus;
    if (httpStatus == 200) {
      for (final error in errors) {
        final value = error is Map ? error['status'] : null;
        if (value is num) {
          status = value.toInt();
          break;
        }
      }
    }
    final detail = errors.isEmpty
        ? 'HTTP $httpStatus'
        : 'HTTP $httpStatus: ${_describeErrors(errors)}';

    if (status == 400) {
      return AppException(
        ErrorKind.badRequest,
        'AniList rejected the request. $detail',
        statusCode: status,
      );
    }
    if (status == 404) {
      return AppException(ErrorKind.notFound, detail, statusCode: status);
    }
    if (status == 401) {
      return hasToken
          ? AppException(
              ErrorKind.unauthorized,
              'AniList token expired or invalid. $detail',
              statusCode: status,
            )
          : AppException(
              ErrorKind.server,
              'AniList refused an unauthenticated request. $detail',
              statusCode: status,
            );
    }
    if (status == 403) {
      return hasToken
          ? AppException(ErrorKind.forbidden, detail, statusCode: status)
          : AppException(
              ErrorKind.server,
              'AniList (or a proxy in front of it) blocked the request. '
              '$detail',
              statusCode: status,
            );
    }
    if (status == 429) {
      return AppException(
        ErrorKind.rateLimit,
        'AniList rate limit exceeded',
        statusCode: status,
      );
    }
    return AppException(
      ErrorKind.server,
      status >= 500
          ? 'AniList responded with $status. $detail'
          : 'Unexpected status $status from AniList. $detail',
      statusCode: status,
    );
  }

  static String _describeErrors(List<dynamic> errors) {
    final messages = <String>[];
    for (final error in errors) {
      if (error is Map && error['message'] is String) {
        messages.add(error['message'] as String);
      }
    }
    return messages.isEmpty ? 'unknown GraphQL error' : messages.join('; ');
  }

  void close() => _http.close();
}

/// Internal signal: the server asked us to wait [delay] before retrying.
class _RetryAfter {
  const _RetryAfter(this.delay);

  final Duration delay;
}
