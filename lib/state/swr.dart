import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gql/ast.dart' show DocumentNode;
import 'package:graphql_flutter/graphql_flutter.dart';

import '../data/graphql/graphql_bootstrap.dart' show FreshnessTracker;
import 'graphql_providers.dart';

/// A value plus what the UI needs to render stale-while-revalidate honestly.
class SwrResult<T> {
  const SwrResult(
    this.data, {
    required this.isRefreshing,
    required this.fromCache,
    this.refreshError,
  });

  final T data;

  /// A network revalidation is in flight. Show a subtle indicator, NOT a
  /// full-screen spinner: the data on screen is real, just possibly old.
  final bool isRefreshing;

  /// This emission came from the persisted cache (the 0 ms paint).
  final bool fromCache;

  /// Revalidation failed but old data exists. Keep showing the data and
  /// offer a retry instead of replacing the screen with an error.
  final Object? refreshError;
}

/// Stale-while-revalidate for one query.
///
/// Why `watchQuery` and not `client.query`: with cacheAndNetwork,
/// `client.query` resolves with the NETWORK result, so you would wait for the
/// request and lose the instant cache paint. `watchQuery` is a stream that
/// emits the cache hit first, then the network result, then any later cache
/// change (for example a mutation updating the same `Media:123` record).
///
/// Freshness: inside [ttl] after the last successful network fetch the policy
/// is cacheFirst (zero requests); after that it is cacheAndNetwork.
Stream<SwrResult<T>> swrQuery<T>(
  Ref ref, {
  required DocumentNode document,
  required String operation,
  required Map<String, dynamic> variables,
  required T Function(Map<String, dynamic> data) parse,
  Duration ttl = const Duration(minutes: 5),
  bool forceNetwork = false,
}) async* {
  final client = ref.watch(graphQLClientProvider);
  final freshness = ref.watch(gqlStorageProvider).freshness;

  final key = FreshnessTracker.keyFor(operation, variables);
  final fresh = !forceNetwork && freshness.isFresh(key, ttl);

  final observable = client.watchQuery<T>(
    WatchQueryOptions<T>(
      document: document,
      variables: variables,
      fetchPolicy: fresh ? FetchPolicy.cacheFirst : FetchPolicy.cacheAndNetwork,
      errorPolicy: ErrorPolicy.all,
      cacheRereadPolicy: CacheRereadPolicy.mergeOptimistic,
      fetchResults: true, // start the request immediately
      parserFn: parse,
    ),
  );
  ref.onDispose(observable.close);

  T? last;
  await for (final result in observable.stream) {
    final data = result.data;

    if (data == null) {
      if (result.isLoading) continue; // nothing cached yet: stay AsyncLoading
      final error = result.exception;
      if (last != null) {
        yield SwrResult<T>(last, isRefreshing: false, fromCache: false,
            refreshError: error);
        continue;
      }
      throw error == null ? StateError('Empty GraphQL result') : toAppError(error);
    }

    final parsed = result.parsedData as T;
    last = parsed;
    final fromNetwork = result.source == QueryResultSource.network;
    if (fromNetwork && !result.hasException) freshness.touch(key);

    yield SwrResult<T>(
      parsed,
      isRefreshing: result.isLoading,
      fromCache: result.source == QueryResultSource.cache,
      refreshError: result.exception,
    );
  }
}
