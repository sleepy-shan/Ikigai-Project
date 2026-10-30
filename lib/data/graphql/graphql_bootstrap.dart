import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import 'anilist_http_client.dart';
import 'bearer_auth_link.dart';

/// Bump the suffix whenever the MediaCard fragment or the models change shape.
/// A new box name means old cached records are simply never read again
/// (delete the stale box in [openGqlStorage] to reclaim the space).
const String kGqlBox = 'ikigai_gql_v1';
const String kMetaBox = 'ikigai_gql_meta_v1';

/// Everything the GraphQL layer persists, opened once in main().
class GqlStorage {
  GqlStorage({
    required this.store,
    required this.freshness,
    required this.persistent,
  });

  final Store store;
  final FreshnessTracker freshness;

  /// False when IndexedDB was unavailable (private mode, blocked storage) and
  /// the app silently fell back to an in-memory cache for this session.
  final bool persistent;
}

/// Call before runApp(). Never throws: the app must still start when the
/// browser blocks IndexedDB.
///
/// Flutter Web notes
///  * `initHiveForFlutter` is hive_flutter's init; on web Hive uses IndexedDB.
///  * Hive keeps an opened box fully in memory, so keep the cache small
///    (list pages of <= 25 items, no relations/recommendations in list
///    queries) and bump [kGqlBox] instead of letting it grow forever.
///  * Hive is NOT multi-tab safe. Two open tabs can overwrite each other's
///    cache writes. That is acceptable for a cache (worst case: a refetch)
///    but never keep tokens or the only copy of user data in these boxes.
Future<GqlStorage> openGqlStorage() async {
  try {
    // Use graphql_flutter's own Hive init + HiveStore.open so the Box type
    // always matches the Hive package graphql itself depends on (a separate
    // hive_flutter dependency can resolve to a different, incompatible Box).
    await initHiveForFlutter();
    final store = await HiveStore.open(boxName: kGqlBox);
    final meta = await HiveStore.open(boxName: kMetaBox);
    return GqlStorage(
      store: store,
      freshness: FreshnessTracker(meta),
      persistent: true,
    );
  } on Object catch (error) {
    debugPrint('Hive unavailable, using in-memory GraphQL cache: $error');
    return GqlStorage(
      store: InMemoryStore(),
      freshness: FreshnessTracker(null),
      persistent: false,
    );
  }
}

/// Remembers WHEN each query last succeeded on the network, so the app can
/// choose between "show cache only" and "show cache, then revalidate".
///
/// This is what turns cacheAndNetwork from "one request per screen visit"
/// into real stale-while-revalidate with a freshness window, which is the part
/// that actually protects the rate limit.
class FreshnessTracker {
  FreshnessTracker(this._store);

  /// Timestamps are stored as `{'at': millis}` documents in a second
  /// HiveStore. null => in-memory fallback.
  final HiveStore? _store;
  final Map<String, int> _mem = <String, int>{};

  /// Hive string keys must be ASCII and <= 255 chars, so hash the variables.
  static String keyFor(String operation, Map<String, dynamic> variables) {
    final sorted = Map<String, dynamic>.fromEntries(
      variables.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final bytes = utf8.encode(jsonEncode(sorted));
    var h = 0x811c9dc5; // FNV-1a 32-bit
    for (final b in bytes) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return '$operation:${h.toRadixString(16)}';
  }

  bool isFresh(String key, Duration ttl) {
    final at = (_store?.get(key)?['at'] as int?) ?? _mem[key];
    if (at == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - at;
    return age >= 0 && age < ttl.inMilliseconds;
  }

  /// Marks [key] stale so the next read goes to the network (used after a
  /// write that the cache cannot reflect by itself, e.g. a deleted list entry).
  void forget(String key) {
    _mem.remove(key);
    _store?.delete(key);
  }

  void touch(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _mem[key] = now;
    _store?.put(key, <String, dynamic>{'at': now}); // fire-and-forget: a lost write only means a refetch
  }

  Future<void> clear() async {
    _mem.clear();
    _store?.reset();
  }
}

/// Builds the one app-wide client.
///
/// Link chain (request flows left to right):
///   BearerAuthLink -> HttpLink(AniListHttpClient)
GraphQLClient buildGraphQLClient({
  required Store store,
  required String? Function() readToken,
  http.Client? httpClient,
}) {
  final httpLink = HttpLink(
    AppConfig.aniListEndpoint,
    httpClient: AniListHttpClient(inner: httpClient),
    defaultHeaders: const {'Accept': 'application/json'},
  );

  return GraphQLClient(
    link: Link.from([BearerAuthLink(readToken), httpLink]),
    cache: GraphQLCache(store: store),
    // The client's own default request timeout is short; AniList can be slow.
    // (Verify this parameter name against your installed graphql version.)
    queryRequestTimeout: const Duration(seconds: 25),
    defaultPolicies: DefaultPolicies(
      watchQuery: Policies(
        fetch: FetchPolicy.cacheAndNetwork,
        // AniList can return partial data plus an error; keep rendering it.
        error: ErrorPolicy.all,
        cacheReread: CacheRereadPolicy.mergeOptimistic,
      ),
      query: Policies(
        fetch: FetchPolicy.cacheFirst,
        error: ErrorPolicy.all,
        cacheReread: CacheRereadPolicy.mergeOptimistic,
      ),
    ),
  );
}
