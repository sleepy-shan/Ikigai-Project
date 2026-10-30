import 'package:graphql_flutter/graphql_flutter.dart';

/// Adds `Authorization: Bearer <token>` ONLY when a token exists at the moment
/// the request is made; otherwise the request goes out as a plain public call.
///
/// The token is read per request (not captured at construction), so signing in
/// or out never requires rebuilding the client or its cache. It is never
/// logged. (Written as a tiny custom Link so the "no token => no header"
/// behaviour is explicit rather than dependent on AuthLink's null handling.)
class BearerAuthLink extends Link {
  BearerAuthLink(this._readToken);

  final String? Function() _readToken;

  @override
  Stream<Response> request(Request request, [NextLink? forward]) {
    final next = forward!;
    final token = _readToken();
    if (token == null || token.isEmpty) return next(request);

    return next(
      request.updateContextEntry<HttpLinkHeaders>(
        (headers) => HttpLinkHeaders(
          headers: {...?headers?.headers, 'Authorization': 'Bearer $token'},
        ),
      ),
    );
  }
}
