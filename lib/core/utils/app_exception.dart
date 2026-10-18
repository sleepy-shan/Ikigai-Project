/// Typed failures used across the app.
///
/// Every network/data failure is converted into an [AppException] so screens
/// can render a helpful message and offer a retry without exposing
/// internal error details or credentials.
library;

enum ErrorKind {
  /// Device is offline or the request timed out.
  network,

  /// Third-party API rate limit was hit (AniList returns HTTP 429).
  rateLimit,

  /// The user is not authenticated or the session expired.
  unauthorized,

  /// Signed in, but the user is not allowed to touch this record.
  forbidden,

  /// The requested resource does not exist.
  notFound,

  /// The service rejected the request itself (HTTP 400: malformed query or
  /// bad variables). This is a bug on our side, not a missing title, so it is
  /// kept separate from [notFound] and never reported as "not found".
  badRequest,

  /// The third-party service returned an unexpected response.
  server,

  /// Storage (localStorage) read/write failed.
  storage,

  /// Validation of user input failed.
  validation,

  /// Anything else.
  unknown,
}

class AppException implements Exception {
  const AppException(
    this.kind,
    this.message, {
    this.cause,
    this.statusCode,
    this.retryAfter,
  });

  final ErrorKind kind;

  /// Developer-facing detail (status code, GraphQL error text). Never shown
  /// to users — see [userMessage].
  final String message;
  final Object? cause;

  /// HTTP status that produced this failure, when there was one.
  final int? statusCode;

  /// How long the server asked us to wait before retrying (rate limits).
  final Duration? retryAfter;

  /// Message that is safe to show to an end user.
  String get userMessage => switch (kind) {
    ErrorKind.network => 'No connection. Check your internet and try again.',
    ErrorKind.rateLimit => _rateLimitMessage(retryAfter),
    ErrorKind.unauthorized => 'Your session expired. Please sign in again.',
    ErrorKind.forbidden => 'You do not have permission to do that.',
    ErrorKind.notFound => 'That title could not be found.',
    ErrorKind.badRequest =>
      'AniList could not process that request. Please try again later.',
    ErrorKind.server =>
      'The service is having trouble right now. Try again later.',
    ErrorKind.storage => 'Could not save data on this device.',
    ErrorKind.validation => message,
    ErrorKind.unknown => 'Something went wrong. Please try again.',
  };

  static String _rateLimitMessage(Duration? wait) {
    const base = 'AniList is rate-limiting requests right now.';
    if (wait == null) return '$base Wait a moment and retry.';
    final minutes = (wait.inSeconds / 60).ceil();
    if (minutes <= 1) return '$base Wait a minute and retry.';
    return '$base Try again in about $minutes minutes.';
  }

  @override
  String toString() => 'AppException($kind, $message)';
}
