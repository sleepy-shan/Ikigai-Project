# Ikigai: GraphQL data layer blueprint

Drop-in files for `lib/` (paths match your repo). Nothing here has been
compiled: the sandbox had no Flutter SDK or pub.dev access. Expect a small
fix-up pass after `pub get` + `build_runner` (see "Verify first").

## Where this fits in your current code

Your app already has a hand-written `AniListClient` (retry, backoff,
`Retry-After`, partial-data handling), a 5-minute in-memory TTL cache and
in-flight dedupe in `MediaRepository`, and tracking that is **local only**
(`LocalTrackingRepository`, localStorage). This blueprint replaces the fetch +
cache + model layers and adds the first real AniList list sync.

```
UI (existing screens)
  │  ref.watch(animePageProvider(args)) / displayEntryProvider(id)
  ▼
Riverpod: anime_providers.dart, tracked_entries_notifier.dart
  │  swrQuery(): watchQuery stream, cache first then network
  ▼
GraphQLClient (graphql_bootstrap.dart)
  ├─ GraphQLCache(HiveStore)  ← IndexedDB on web, versioned box
  ├─ BearerAuthLink           ← header only while a token exists
  └─ HttpLink(AniListHttpClient)  ← rate gate, 429 pause, retries, AppException
  ▼
https://graphql.anilist.co
```

## Setup

1. Merge `pubspec_additions.yaml`, copy `build.yaml`.
2. `dart run build_runner build --delete-conflicting-outputs`
3. `main.dart`:

```dart
final prefs = await _loadPreferences();
final gql = await openGqlStorage();          // never throws
runApp(ProviderScope(
  overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    gqlStorageProvider.overrideWithValue(gql),
  ],
  child: const IkigaiApp(),
));
```

4. Migrate screen by screen. `AnimeMedia.toMedia()` returns your existing
   `Media`, so widgets can keep their current model while providers change.

## Design decisions worth knowing

- **`watchQuery`, not `client.query`.** With `cacheAndNetwork`, `client.query`
  resolves with the network result, so you lose the instant cache paint.
  `swrQuery()` is a stream: cache emission, then network emission.
- **cacheAndNetwork alone costs requests, it does not save them.** Every visit
  would hit AniList. `FreshnessTracker` records the last successful fetch per
  query and uses `cacheFirst` inside the TTL, `cacheAndNetwork` after it.
  That is what actually protects the rate limit. You cannot "bypass" AniList's
  limit; this keeps you under it.
- **Rate limiting lives in `AniListHttpClient`**: 80 req/min sliding window
  per tab, one 429 pauses all queued requests, and failures are thrown as
  your existing `AppException`, so current error UI keeps working.
- **Keep user data out of the shared fragment.** `MediaCard` has no
  `mediaListEntry`. User entries use a separate light query, and the cache is
  wiped when the signed-in user changes or signs out.
- **Optimistic updates use an overlay**, not mutated server state. Rollback is
  deleting the overlay entry. Taps are debounced into one absolute-progress
  mutation, and taps are refused until the server entry has loaded (otherwise
  progress 1 could overwrite a real 11).
- **Riverpod 3 retries failed providers automatically.** Every provider here
  passes `retry: noProviderRetry`, since the HTTP client already retries.

## Flutter Web caveats (the stutter part)

- Dart isolates do not exist on web, so `compute()` will not move JSON parsing
  off the main thread. The real levers: small pages (`perPage <= 25`), no
  relations/recommendations in list queries, `select()` so only the changed
  widget rebuilds, and `ListView.builder`/slivers.
- graphql_flutter normalizes every response into `Type:id` records on the main
  thread. It is fast for cards, noticeable for huge payloads.
- Hive loads an opened box into memory and is not multi-tab safe. Fine for a
  cache; never store tokens or the only copy of user data in it. If IndexedDB
  is blocked, `openGqlStorage()` falls back to an in-memory cache.
- Bump `kGqlBox` whenever the fragment or models change shape.

## Verify first (APIs I could not compile against)

- `GraphQLClient(queryRequestTimeout: ...)` exists in your installed version.
- `WatchQueryOptions(parserFn: ...)` and `QueryResult.parsedData`.
- `HttpLinkHeaders` / `updateContextEntry` come through `graphql_flutter`'s
  exports; `LinkException.originalException` is how `toAppError` unwraps.
- `Hive.openBox<int>` next to graphql's box after `initHiveForFlutter`.
- One resolved hive version: `flutter pub deps | grep -i hive`.

## Not covered yet

- "My Lists" (full `MediaListCollection`): add a document + SWR provider the
  same way; it can be large, so page or filter by status.
- Hybrid tracking: guests keep `LocalTrackingRepository`, signed-in users use
  the AniList path above.
- A tap in the last 500 ms before the tab closes is not flushed.

## Migration status

All network traffic now goes through the GraphQL client (rate gate, 429 pause,
retries, persisted cache):

- Home rails: `animePageStream` (MediaCard fragment).
- Browse, Search, Calendar, "airing today": `GqlCatalog` (state/gql_catalog.dart).
- Detail page: `mediaDetailProvider` is a `StreamProvider` (SWR, 30 min TTL).
- Everything still in `MediaRepository` (staff, character and studio pages,
  notifications, viewer profile, activity, AniList list, favourites) uses the
  same client through `MediaRepository.transport` = `GqlCatalog.raw`.
  Requests that carry a token always go to the network (never answered from the
  cache); public ones follow a 10 minute freshness window.
- Tracking: the local list is the UI source of truth. When signed in, add /
  status / progress / score / remove are mirrored to AniList
  (`OptimisticEntries.applyEdit` / `removeEntry`): debounced, absolute values,
  the server entry is awaited first so nothing is overwritten from a guess.
- My Lists: "Import from AniList" button (cloud icon, signed in only) copies
  anime and manga lists into the local list; only missing titles are added.
- Sync feedback: failures show a snackbar (app shell), and the detail page's
  tracking card says "syncing to AniList…" while an edit is pending.

Known limits: import never overwrites or removes local entries and does not
delete anything that exists only locally; a local edit made while a title's
AniList entry cannot be read is not synced (nothing is sent on a guess);
`MediaRepository` is kept as a thin layer (mapping + in-memory cache), not
deleted. `AniListClient` is still used by it as the fallback when no transport
is set.
