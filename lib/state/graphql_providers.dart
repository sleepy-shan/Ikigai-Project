import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../core/utils/app_exception.dart';
import '../data/graphql/graphql_bootstrap.dart';
import 'providers.dart'; // authRepositoryProvider, authStateProvider (existing)

/// Overridden in main() with the opened storage:
///   ProviderScope(overrides: [gqlStorageProvider.overrideWithValue(storage)])
final gqlStorageProvider = Provider<GqlStorage>((ref) {
  throw StateError('gqlStorageProvider must be overridden in main()');
});

/// The single GraphQL client. Public by default; the Bearer token is attached
/// per request, only while the user is signed in.
final graphQLClientProvider = Provider<GraphQLClient>((ref) {
  final storage = ref.watch(gqlStorageProvider);
  final auth = ref.watch(authRepositoryProvider);

  // Read the token lazily so sign-in/out needs no client rebuild.
  final client = buildGraphQLClient(
    store: storage.store,
    readToken: () => auth.accessToken,
  );

  // User-specific records (mediaListEntry) live in the same cache as catalog
  // data. When the account changes or signs out, wipe it so one person's list
  // can never show up for the next person on this browser.
  // Guest -> user does NOT purge (nothing user-specific exists yet).
  ref.listen<int?>(authStateProvider.select((a) => a.value?.id), (prev, next) {
    if (prev != null && prev != next) {
      client.cache.store.reset();
      storage.freshness.clear();
    }
  });

  return client;
});

/// Turns a graphql OperationException into the app's [AppException] so the
/// existing error widgets keep working.
Object toAppError(OperationException e) {
  final original = e.linkException?.originalException;
  if (original is AppException) return original;
  if (e.linkException != null) {
    return const AppException(ErrorKind.network, 'Network request failed');
  }
  final message = e.graphqlErrors.map((g) => g.message).join('; ');
  return AppException(
    ErrorKind.server,
    message.isEmpty ? 'Unknown GraphQL error' : message,
  );
}

/// Riverpod 3 retries failed providers automatically (exponential backoff).
/// AniListHttpClient already retries 429/5xx, so provider-level retry would
/// multiply requests against a rate limit. Opt every GraphQL provider out.
Duration? noProviderRetry(int retryCount, Object error) => null;
